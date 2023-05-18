import numpy as np
import numpy.typing as npt
import zlib
import os
import glob
from typing import TypedDict, Optional

Vector = npt.NDArray[np.float32]

class Item(TypedDict):
    content_hash: str
    embedder: str

class Store(TypedDict):
    items: dict[str, Item]
    vectors: dict[str, Vector]

def hash_content(data: bytes) -> str:
    return f'{zlib.adler32(data):08x}'

def normalize_filepath(filepath: str) -> str:
    return filepath.replace('\\', '/')

def initialize_empty_store () -> Store:
    return {
        'items': {},
        'vectors': {}
    }

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

    return [ f for f in map(ingest_file, glob_files()) if f ]

print(ingest_files(root_dir='../lua'))

