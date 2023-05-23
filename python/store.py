import zlib
import os
import glob
import json

import sys
import numpy as np
import numpy.typing as npt
import openai
import tiktoken

from typing import TypedDict, Optional

# TODO make token counting optional
# TODO we probably just want to store the entire files in store.json instead of re-reading them
# TODO all paths relative to store.json

enc = tiktoken.encoding_for_model('gpt-4')

# https://platform.openai.com/docs/api-reference/embeddings/create
INPUT_TOKEN_LIMIT = 8192

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def tap(x, label: Optional[str] = None):
    if label is not None:
        eprint('<<', label)
    eprint(x)
    if label is not None:
        eprint(label, '>>')
    return x

def count_tokens(text: str) -> int:
    return len(enc.encode(text))

def hash_content(data: bytes) -> str:
    return f'{zlib.adler32(data):08x}'

def normalize_filepath(filepath: str) -> str:
    return filepath.replace('\\', '/')

class Item(TypedDict):
    id: str
    content_hash: str
    meta: Optional[dict] # NotRequired not supported

class StoreItem(Item):
    embedder: str

class Store(TypedDict):
    items: list[StoreItem]
    vectors: npt.NDArray[np.float32] | None

def load_or_initialize_store (store_path: str) -> Store:
    def initialize_empty_store () -> Store:
        return {
            'items': [],
            'vectors': np.array([])
        }

    try:
        with open(store_path, encoding='utf-8') as f:
            store_raw = json.loads(f.read()) 
            store: Store = {
                'items': store_raw['items'],
                'vectors': np.array(store_raw['vectors'])
            }

            return store

    except FileNotFoundError:
        return initialize_empty_store()

def save_store(store: Store, store_path: str):
    if store['vectors'] is None: return

    store_raw = {
        'items': store['items'],
        'vectors': [ v.tolist() for v in store['vectors'] ]
    }

    os.makedirs(os.path.dirname(store_path), exist_ok=True)

    with open(store_path, mode='w', encoding='utf-8') as f:
        f.write(json.dumps(store_raw))

class File(TypedDict):
    id: str
    content: str
    content_hash: str

content_cache = {}

def cache_content(content: str):
    hash = hash_content(content.encode('utf-8'))
    content_cache[hash] = content
    return hash

def try_inject_content(item: Item):
    if item['content_hash'] in content_cache:
        return { **item, 'content':content_cache[item['content_hash']] }
    else:
        match item['meta']:
            case {'type': 'file'}:
                # this seems problematic
                # assuming id is path
                # path should always be relative to store.json
                # need to add path util to re-normalize paths
                # this can fail
                # file content can be stale
                try:
                    with open(item['id'], mode='r') as f:
                        return {
                            **item,
                            'content': f.read()
                        }
                except:
                    return item

def ingest_files(root_dir, glob_pattern) -> list[Item]:
    "Ingest files down from root_dir assuming utf-8 encoding. Skips files which fail to decode."

    def ingest_file(filepath: str) -> Optional[Item]:
        with open(filepath, mode='r') as f:
            content = f.read()
            try:
                return {
                    'id': normalize_filepath(filepath),
                    'content_hash': cache_content(content),
                    'meta': {
                        'type': 'file'
                    }
                }
            except:
                return None

    def glob_files():
        return [
            normalize_filepath(path) for path in
                glob.glob(os.path.join(root_dir, glob_pattern), recursive=True)
            if os.path.isfile(path)
        ]

    return [ f for f in map(ingest_file, tap(glob_files())) if f ]

def get_embeddings(inputs: list[str], print_token_counts=True):
    if not inputs: return []

    input_tokens = [ (count_tokens(input), input) for input in inputs ]

    if print_token_counts:
        eprint([ (x[1][:30], x[0]) for x in input_tokens ])

    if all(limit[0] < INPUT_TOKEN_LIMIT for limit in input_tokens):
        response = openai.Embedding.create(input=inputs, model="text-embedding-ada-002")
        return [item['embedding'] for item in response['data']]
    else:
        over_limits = [limit[1][:30] for limit in input_tokens if not limit[0] < INPUT_TOKEN_LIMIT]
        eprint('Input(s) over the token limit:')
        eprint(over_limits)
        raise ValueError('Embedding input over token limit')

def get_stale_or_new_item_idxs(items: list[Item], store: Store):
    id_to_content_hash = {x['id']: x['content_hash'] for x in store['items'] }

    return [
        idx for idx, item in enumerate(items) if
            item['id'] not in id_to_content_hash
            or item['content_hash'] != id_to_content_hash[item['id']]
    ]

def get_removed_item_store_idx(items: list[Item], store: Store):
    current_ids = set([item['id'] for item in items])

    return [
        idx
        for idx, item in enumerate(store['items'])
        if item['id'] not in current_ids
    ]

def _update_embeddings(items: list[Item], store: Store, remove_missing, print_updating_items=True) -> bool:
    """
    Update stale store data returning True if items were updated. remove_missing removes any items in store that aren't in provided items.
    For partial updates (only adding items), disable remove_missing.
    """
    needs_update_idx = get_stale_or_new_item_idxs(items, store)
    needs_update_content = [ items[idx]['content'] for idx in needs_update_idx ]

    if print_updating_items:
        eprint('Updating items:')
        eprint([ items[idx]['id'] for idx in needs_update_idx ])

    embeddings = get_embeddings(needs_update_content)

    if len(embeddings) == 0: return False

    if store['vectors'] is None:
        vector_dimensions = len(embeddings[0])
        store['vectors'] = np.empty([0, vector_dimensions], dtype=np.float32)

    assert store['vectors'] is not None

    if remove_missing:
        idxs = get_removed_item_store_idx(items, store)
        for idx in idxs:
            del store['items'][idx]
            np.delete(store['vectors'], idx, axis=0)

    id_to_idx = { item['id']: idx for idx, item in enumerate(store['items']) }

    for i, embedding in enumerate(embeddings):
        item_idx = needs_update_idx[i]
        item = items[item_idx]
        item['embedder'] = 'openai_ada_002'
        # NOTE pretty sure mutation here has no consequences?

        if item['id'] in id_to_idx:
            idx = id_to_idx[item['id']]

            store['items'][idx] = item
            store['vectors'][idx] = np.array(embedding).astype(np.float32)
        else:
            store['items'].append(item)
            store['vectors'] = np.vstack((store['vectors'], embedding))

    return True

def add_embeddings(items: list[Item], store):
    return _update_embeddings(items, store, remove_missing=False)

def sync_embeddings(items: list[Item], store):
    return _update_embeddings(items, store, remove_missing=True)

class Query(TypedDict):
    prompt: str
    count: int

def query_store(prompt: str, count: int, store: Store, filter=None):
    assert store['vectors'] is not None

    embedding = get_embeddings([prompt], print_token_counts=False)[0]
    query_vector = np.array(embedding, dtype=np.float32)
    similarities = np.dot(store['vectors'], query_vector.T)
    ranks = np.argsort(similarities)[::-1]

    if filter is None:
        return [ store['items'][idx] for idx in ranks[:count] ]
    else:
        results = []

        for idx in ranks:
            item = store['items'][idx]

            if filter(item):
                results.append(item)

            if len(results) >= count:
                break

        return results

class Opts(TypedDict):
    prompt: str
    count: Optional[int]
    store_path: str
    files_ingest_root: Optional[str]
    files_ingest_glob: Optional[str]

def get_opts() -> Opts:
    if len(sys.argv) < 2:
        raise ValueError('Missing options json argument')

    opts : Opts = json.loads(sys.argv[1])

    assert type(opts['prompt']) == str, 'Missing prompt'
    assert (opts['count'] == None or type(opts['count']) == int), 'count not a number'
    assert type(opts['store_path']) == str, 'Missing store_path'
    assert type(opts['files_ingest_root']) == str, 'Missing files_ingest_root'
    assert (opts['files_ingest_glob'] == None or type(opts['files_ingest_glob'] == str)), 'files_ingest_glob not a string'

    return opts

opts = get_opts()
store = load_or_initialize_store(opts['store_path'])
updated = add_embeddings(
    ingest_files(
        opts['files_ingest_root'] or '.',
        opts['files_ingest_glob'] or '**/*'
    ),
    store
)
if updated: save_store(store, opts['store_path'])

results = list(map(
    try_inject_content,
    query_store(
        opts['prompt'],
        opts['count'] or 1,
        store
    )
))

print(json.dumps(results))
