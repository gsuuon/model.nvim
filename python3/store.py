import zlib
import os
import glob
import json

import sys
import numpy as np
import numpy.typing as npt
import openai
import tiktoken

from typing import TypedDict, Optional, Sequence, List, cast

# TODO make token counting optional

enc = tiktoken.encoding_for_model('gpt-4')

# https://platform.openai.com/docs/api-reference/embeddings/create
INPUT_TOKEN_LIMIT = 8192
STORE_FILE_NAME = '.llm_store.json'

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def tap(x, label: Optional[str] = None):
    if label is not None:
        print('<<', label)
    print(x)
    if label is not None:
        print(label, '>>')
    return x

def count_tokens(text: str) -> int:
    return len(enc.encode(text))

def hash_content(text: str) -> str:
    data = text.encode('utf-8')
    return f'{zlib.adler32(data):08x}'

def normalize_filepath(filepath: str) -> str:
    return filepath.replace('\\', '/')

class Item(TypedDict):
    id: str
    content: str
    meta: Optional[dict] # NotRequired not supported

class StoreItem(Item):
    embedder: str
    content_hash: str

class Store(TypedDict):
    abs_path: str
    items: list[StoreItem]
    vectors: npt.NDArray[np.float32] | None

def load_or_initialize_store (store_dir: str) -> Store:
    # TODO should I write store on load if it doesn't exist?
    def initialize_empty_store (abs_path) -> Store:
        return {
            'abs_path': abs_path,
            'items': [],
            'vectors': None
        }

    abs_path = os.path.abspath(os.path.join(store_dir, STORE_FILE_NAME))

    try:
        with open(abs_path, encoding='utf-8') as f:
            store_raw = json.loads(f.read()) 
            store: Store = {
                'abs_path': abs_path,
                'items': store_raw['items'],
                'vectors': np.array(store_raw['vectors'], dtype=np.float32)
            }

            return store

    except FileNotFoundError:
        return initialize_empty_store(abs_path)

def save_store(store: Store):
    if store['vectors'] is None: return

    store_raw = {
        'items': store['items'],
        'vectors': [ v.tolist() for v in store['vectors'] ]
    }

    with open(store['abs_path'], mode='w', encoding='utf-8') as f:
        f.write(json.dumps(store_raw))

def ingest_files(root_dir, glob_pattern) -> list[Item]:
    "Ingest files down from root_dir assuming utf-8 encoding. Skips files which fail to decode."

    def ingest_file(filepath: str) -> Optional[Item]:
        with open(filepath, mode='r', encoding='utf-8') as f:
            try:
                return {
                    'id': normalize_filepath(filepath),
                    'content': f.read(),
                    'meta': {
                        'type': 'file'
                    }
                }
            except Exception as e:
                print("Failed to read ", filepath)
                print(e)
                return None

    def glob_files():
        return [
            normalize_filepath(path) for path in
                glob.glob(os.path.join(root_dir, glob_pattern), recursive=True)
            if os.path.isfile(path)
        ]

    return [ f for f in map(ingest_file, glob_files()) if f ]

def get_embeddings(inputs: list[str]):
    if not inputs: return []

    token_counts = [ count_tokens(input) for input in inputs ]

    if all(token_count < INPUT_TOKEN_LIMIT for token_count in token_counts):
        response = openai.Embedding.create(input=inputs, model="text-embedding-ada-002")
        return [item['embedding'] for item in response['data']], token_counts
    else:
        over_limits = [
            idx
            for idx, count in enumerate(token_counts)
            if not count < INPUT_TOKEN_LIMIT
        ]
        eprint('Input(s) over the token limit:')
        eprint(over_limits)
        raise ValueError('Embedding input over token limit')

def get_stale_or_new_item_idxs(items: Sequence[StoreItem], store: Store):
    id_to_content_hash = {x['id']: x['content_hash'] for x in store['items'] }

    return [
        idx for idx, item in enumerate(items) if
            item['id'] not in id_to_content_hash
            or item['content_hash'] != id_to_content_hash[item['id']]
    ]

def get_removed_item_store_idx(items: Sequence[StoreItem], store: Store):
    current_ids = set([item['id'] for item in items])

    return [
        idx
        for idx, item in enumerate(store['items'])
        if item['id'] not in current_ids
    ]

def as_store_items(items: Sequence[Item]) -> List[StoreItem]:
    "Mutates Item seq to StoreItem list in place"
    items = cast(List[StoreItem], items)

    for item in items:
        item['content_hash'] = hash_content(item['content'])
        item['embedder'] = 'openai_ada_002'

    return items

def update_store(
    items: Sequence[Item],
    store: Store,
    sync: bool
) -> tuple[list[str], list[int]]:
    """
    Update stale store data returning updated item ids. sync=True removes any items in store that aren't in provided items.
    For partial updates (only adding items), set sync=False.
    """

    items = as_store_items(items)

    needs_update_idx = get_stale_or_new_item_idxs(items, store)

    if len(needs_update_idx) == 0:
        print('all ' + str(len(items)) + ' items were stale')
        return [], []

    needs_update_content = [ items[idx]['content'] for idx in needs_update_idx ]

    embeddings, token_counts = get_embeddings(needs_update_content)

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
        # NOTE pretty sure mutation here has no consequences?

        if item['id'] in id_to_idx:
            idx = id_to_idx[item['id']]

            store['items'][idx] = item
            store['vectors'][idx] = np.array(embedding).astype(np.float32)
        else:
            store['items'].append(item)
            store['vectors'] = np.vstack((store['vectors'], embedding))

    return [ items[idx]['id'] for idx in needs_update_idx ], token_counts

def update_store_and_save(items, store, sync=False):
    updated, token_counts = update_store(items, store, sync)

    if len(updated) > 0:
        print("Saving items:")
        print(list(zip(updated, token_counts)))
        save_store(store)
    else:
        print("No new or updated items")

    return updated

def path_relative_to_store(filepath, store: Store):
    return normalize_filepath(os.path.relpath(
        os.path.abspath(filepath),
        os.path.dirname(store['abs_path'])
    ))

class File(TypedDict):
    id: str # filepath relative to project root, eg: project/myfile.py
    content: str

class FileChunk(TypedDict):
    id: str # filepath and starting line number of the file chunk, eg: project/myfile.py:12
    content: str # a chunk of the file's contents

def chunk_by_newlines(file: File) -> List[FileChunk]:
    "Chunks a file by '\n\n' separator. Does not include empty chunks."

    file_chunks: List[FileChunk] = []

    current_chunk_content = ''
    current_chunk_start_line = 0

    lines = file["content"].split('\n')

    for line_number, line in enumerate(lines):
        if current_chunk_content != '':
            current_chunk_content += '\n'

        current_chunk_content += line

        if not line:
            if current_chunk_content:
                file_chunks.append(FileChunk(
                    id=f"{file['id']}:{current_chunk_start_line}",
                    content=current_chunk_content
                ))
            current_chunk_content = ''
            current_chunk_start_line = line_number + 1

    if current_chunk_content:
        file_chunks.append(FileChunk(
            id=f"{file['id']}:{len(lines)}",
            content=current_chunk_content
        ))

    return file_chunks

def update_with_files_and_save(store, files_root=None, files_glob=None, sync=False, chunked=True):
    files = ingest_files(files_root or '.', files_glob or '**/*')

    # Convert ids (paths) from relative to cwd to relative to store
    for file in files:
        file['id'] = path_relative_to_store(file['id'], store)

    if chunked:
        items = [ chunk for file in files for chunk in chunk_by_newlines(file) ]

        return update_store_and_save(
            items,
            store,
            sync=sync
        )
    else:
        return update_store_and_save(
            files,
            store,
            sync=sync
        )

def query_store(prompt: str, count: int, store: Store, filter=None):
    assert store['vectors'] is not None

    embedding = get_embeddings([prompt])[0]
    query_vector = np.array(embedding, dtype=np.float32)
    similarities = np.dot(store['vectors'], query_vector.T).flatten()
    ranks = np.argsort(similarities)[::-1]

    results = []

    for idx in ranks[::]:
        item = store['items'][idx]
        similarity = similarities[idx]

        if filter == None or filter(item, similarity):
            results.append({ **item, 'similarity': similarity.item() })

        if len(results) >= count:
            break

    return results

if __name__ == '__main__':
    s = load_or_initialize_store('.')

    # update_with_files_and_save(s, files_root='.', files_glob='**/*.py')

    # print([ i['id'] for i in s['items']])

    matches = query_store('add function that requests the bard api using curl helpers', 10, s, lambda item, similarity: similarity > 0.6)
    print([ (match['id'], match['similarity']) for match in matches])
