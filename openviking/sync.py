import json
import shutil
from pathlib import Path
from typing import List, Tuple
from openviking import HybridStorage, OpenVikingClient


TVPL_CORPUS_PATH = Path("/Users/sonln4/Documents/tvpl_corpus/docs")


def find_valid_documents(corpus_path: Path) -> List[Tuple[Path, Path, Path]]:
    valid_docs = []
    for folder in corpus_path.iterdir():
        if not folder.is_dir():
            continue
        folder_id = folder.name
        metadata_file = folder / "metadata.json"
        doc_files = [f for f in folder.iterdir() if f.is_file() and f.name != "metadata.json"]
        
        if metadata_file.exists() and doc_files:
            for doc_file in doc_files:
                valid_docs.append((folder_id, doc_file, metadata_file))
    return valid_docs


def import_to_s3(hybrid_storage: HybridStorage) -> dict:
    valid_docs = find_valid_documents(TVPL_CORPUS_PATH)
    
    imported = []
    for folder_id, doc_file, metadata_file in valid_docs:
        metadata = json.loads(metadata_file.read_text(encoding="utf-8"))
        
        s3_path = hybrid_storage.upload_to_s3(doc_file, str(folder_id), doc_file.name)
        metadata_path = hybrid_storage.upload_metadata_to_s3(str(folder_id), metadata)
        
        imported.append({
            "folder_id": folder_id,
            "document": doc_file.name,
            "s3_location": s3_path,
            "metadata_location": metadata_path
        })
    
    return {
        "total_found": len(valid_docs),
        "imported": imported
    }


def import_to_local(hybrid_storage: HybridStorage, local_dir: Path) -> dict:
    valid_docs = find_valid_documents(TVPL_CORPUS_PATH)
    
    imported = []
    for folder_id, doc_file, metadata_file in valid_docs:
        target_dir = local_dir / folder_id
        target_doc = target_dir / doc_file.name
        target_meta = target_dir / "metadata.json"
        
        shutil.copy2(doc_file, target_doc)
        shutil.copy2(metadata_file, target_meta)
        
        imported.append({
            "folder_id": folder_id,
            "document": doc_file.name,
            "local_path": str(target_doc)
        })
    
    return {
        "total_found": len(valid_docs),
        "imported": imported
    }
