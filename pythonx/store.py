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
from typing_extensions import TypeGuard

# TODO make token counting optional
# TODO we probably just want to store the entire files in store.json instead of re-reading them
# TODO all paths relative to store.json

enc = tiktoken.encoding_for_model('gpt-4')

# https://platform.openai.com/docs/api-reference/embeddings/create
INPUT_TOKEN_LIMIT = 8192
DEFAULT_STORE_PATH = 'store.json'

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
    content: str
    meta: Optional[dict] # NotRequired not supported

class StoreItem(TypedDict):
    id: str
    content_hash: str
    embedder: str
    meta: Optional[dict] # NotRequired not supported

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

def try_inject_content(item: StoreItem):
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
                    'content': content,
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

def update_embeddings(
    items: list[Item],
    store: Store,
    sync
) -> list[str]:
    """
    Update stale store data returning updated item ids. sync=True removes any items in store that aren't in provided items.
    For partial updates (only adding items), set sync=False.
    """
    needs_update_idx = get_stale_or_new_item_idxs(items, store)

    if len(needs_update_idx) == 0:
        eprint('all ' + str(len(items)) + ' were stale')
        return []

    needs_update_content = [ items[idx]['content'] for idx in needs_update_idx ]

    embeddings = get_embeddings(needs_update_content)

    if store['vectors'] is None:
        vector_dimensions = len(embeddings[0])
        store['vectors'] = np.empty([0, vector_dimensions], dtype=np.float32)

    assert store['vectors'] is not None

    if sync:
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

    return [ items[idx]['id'] for idx in needs_update_idx ]

class Query(TypedDict):
    prompt: str
    count: int

def _query_store(prompt: str, count: int, store: Store, filter=None):
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

class UpdateStoreOpts(TypedDict):
    sync: bool
    store_path: Optional[str]
    files_ingest_root: Optional[str]
    files_ingest_glob: Optional[str]

class QueryOpts(TypedDict):
    prompt: str
    count: Optional[int]
    store_path: str

Opts = QueryOpts | UpdateStoreOpts

def is_query(opts: Opts) -> TypeGuard[QueryOpts]:
    return 'prompt' in opts

def is_update_store(opts: Opts) -> TypeGuard[UpdateStoreOpts]:
    return 'sync' in opts

def get_opts() -> Opts:
    if len(sys.argv) < 2:
        raise ValueError('Missing options json argument')

    def assert_query():
        assert type(opts['prompt']) == str, 'Missing prompt'
        assert opts.get('count') == None or type(opts['count']) == int, 'count not a number'

    def assert_update_store():
        assert type(opts['sync'] == bool), 'Missing sync option'
        assert opts.get('store_path') == None or type(opts['store_path']) == str, 'Missing store_path'
        assert opts.get('files_ingest_root') == None or type(opts.get('files_ingest_root')) == str, 'Missing files_ingest_root'
        assert opts.get('files_ingest_glob') == None or type(opts.get('files_ingest_glob') == str), 'files_ingest_glob not a string'

    opts = json.loads(sys.argv[1])

    if is_query(opts):
        assert_query()
    else:
        assert_update_store()

    return opts

def update_store(updateOpts: UpdateStoreOpts, store: Store):
    updated = update_embeddings(
        ingest_files(
            updateOpts.get('files_ingest_root') or '.',
            updateOpts.get('files_ingest_glob') or '**/*'
        ),
        store,
        updateOpts['sync']
    )

    if len(updated) > 0:
        save_store(store, opts.get('store_path') or DEFAULT_STORE_PATH)

    return updated

def query_store(queryOpts: QueryOpts, store: Store):
    return list(map(
        try_inject_content,
        _query_store(
            queryOpts['prompt'],
            queryOpts.get('count') or 1,
            store
        )
    ))

if __name__ == '__main__':
    opts = get_opts()
    store = load_or_initialize_store(opts['store_path'] or DEFAULT_STORE_PATH)

    if is_update_store(opts):
        print(json.dumps(update_store(opts, store)))
    elif is_query(opts):
        print(json.dumps(query_store(opts, store)))
