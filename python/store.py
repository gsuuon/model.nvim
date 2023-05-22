import numpy as np
import numpy.typing as npt
import openai
import zlib
import os
import glob
import json
import tiktoken

from typing import TypedDict, Optional

enc = tiktoken.encoding_for_model('gpt-4')
# https://platform.openai.com/docs/api-reference/embeddings/create
INPUT_TOKEN_LIMIT = 8192

def tap(x, label: Optional[str] = None):
    if label is not None:
        print(label)
    print(x)
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
    embedder: str

class Store(TypedDict):
    items: list[Item]
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

def ingest_files(root_dir='.', glob_pattern='**/*') -> list[File]:
    "Ingest files down from root_dir assuming utf-8 encoding. Skips files which fail to decode."

    def ingest_file(filepath: str) -> Optional[File]:
        with open(filepath, mode='rb') as f:
            content_bytes = f.read()
            try:
                return {
                    'id': normalize_filepath(filepath),
                    'content': content_bytes.decode('utf-8'),
                    'content_hash': hash_content(content_bytes)
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
        print([ (x[1][:30], x[0]) for x in input_tokens ])

    if all(limit[0] < INPUT_TOKEN_LIMIT for limit in input_tokens):
        response = openai.Embedding.create(input=inputs, model="text-embedding-ada-002")
        return [item['embedding'] for item in response['data']]
    else:
        over_limits = [limit[1][:30] for limit in input_tokens if not limit[0] < INPUT_TOKEN_LIMIT]
        print('Input(s) over the token limit:')
        print(over_limits)
        raise ValueError('Embedding input over token limit')

def get_stale_or_new_file_idxs(files: list[File], store: Store):
    id_to_content_hash = {f['id']: f['content_hash'] for f in store['items'] }

    return [
        idx for idx, file in enumerate(files) if
            file['id'] not in id_to_content_hash
            or file['content_hash'] != id_to_content_hash[file['id']]
    ]

def get_removed_file_store_idx(files: list[File], store: Store):
    current_ids = set([file['id'] for file in files])

    return [
        idx
        for idx, item in enumerate(store['items'])
        if item['id'] not in current_ids
    ]

def _update_embeddings(files: list[File], store: Store, remove_missing, print_updating_files=True):
    """
    Update store data. remove_missing removes any files in store that aren't in files.
    For partial updates (only adding files), disable remove_missing.
    """
    needs_update_idx = get_stale_or_new_file_idxs(files, store)
    needs_update_content = [ files[i]['content'] for i in needs_update_idx ]

    if print_updating_files:
        print('Updating files:')
        print([ files[i]['id'] for i in needs_update_idx ])

    embeddings = get_embeddings(needs_update_content)

    if len(embeddings) == 0: return

    if store['vectors'] is None:
        vector_dimensions = len(embeddings[0])
        store['vectors'] = np.empty([0, vector_dimensions], dtype=np.float32)

    assert store['vectors'] is not None

    if remove_missing:
        idxs = get_removed_file_store_idx(files, store)
        for idx in idxs:
            del store['items'][idx]
            np.delete(store['vectors'], idx, axis=0)

    id_to_idx = { item['id']: idx for idx, item in enumerate(store['items']) }

    for i, embedding in enumerate(embeddings):
        file_idx = needs_update_idx[i]
        file = files[file_idx]
        item : Item = {
            'id': file['id'],
            'content_hash': file['content_hash'],
            'embedder': 'openai_ada_002'
        }

        if file['id'] in id_to_idx:
            idx = id_to_idx[file['id']]

            store['items'][idx] = item
            store['vectors'][idx] = np.array(embedding).astype(np.float32)
        else:
            store['items'].append(item)
            store['vectors'] = np.vstack((store['vectors'], embedding))

def add_embeddings(files: list[File], store):
    return _update_embeddings(files, store, remove_missing=False)

def sync_embeddings(files: list[File], store):
    return _update_embeddings(files, store, remove_missing=True)

def query_store(query: str, store: Store, count=1, filter=None):
    assert store['vectors'] is not None

    tap([item['id'] for item in store['items']])
    embedding = get_embeddings([query], print_token_counts=False)[0]
    query_vector = np.array(embedding, dtype=np.float32)
    tap(query_vector, 'query')
    similarities = np.dot(store['vectors'], query_vector.T)
    tap(similarities, 'similarities')
    ranks = np.argsort(similarities)[::-1]
    tap(ranks, 'ranks')

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




store = load_or_initialize_store('./store.json')
files = tap(ingest_files('../corpus'), label='ingested files')
sync_embeddings(files, store)

print('query:', query_store('bap', store))
save_store(store, './store.json')
