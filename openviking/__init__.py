import json
import boto3
from pathlib import Path
from typing import Optional
import aiohttp
import asyncio

from config import S3_BUCKET, S3_REGION, S3_PREFIX


class S3Client:
    def __init__(self):
        self.client = boto3.client(
            "s3",
            region_name=S3_REGION,
        )
        self.bucket = S3_BUCKET

    def upload_file(self, local_path: Path, s3_key: str) -> str:
        self.client.upload_file(str(local_path), self.bucket, s3_key)
        return f"s3://{self.bucket}/{s3_key}"

    def upload_json(self, data: dict, s3_key: str) -> str:
        self.client.put_object(
            Body=json.dumps(data, ensure_ascii=False, indent=2),
            Bucket=self.bucket,
            Key=s3_key,
            ContentType="application/json"
        )
        return f"s3://{self.bucket}/{s3_key}"

    def download_file(self, s3_key: str, local_path: Path) -> None:
        self.client.download_file(self.bucket, s3_key, str(local_path))

    def list_objects(self, prefix: str = "") -> list:
        response = self.client.list_objects_v2(Bucket=self.bucket, Prefix=prefix)
        return response.get("Contents", [])

    def object_exists(self, s3_key: str) -> bool:
        try:
            self.client.head_object(Bucket=self.bucket, Key=s3_key)
            return True
        except self.client.exceptions.ClientError:
            return False


class HybridStorage:
    def __init__(self, local_base: Path):
        self.s3 = S3Client()
        self.local_base = local_base
        self.local_base.mkdir(parents=True, exist_ok=True)

    def upload_to_s3(self, local_path: Path, doc_id: str, filename: str) -> str:
        s3_key = f"{S3_PREFIX}{doc_id}/{filename}"
        return self.s3.upload_file(local_path, s3_key)

    def upload_metadata_to_s3(self, doc_id: str, metadata: dict) -> str:
        s3_key = f"{S3_PREFIX}{doc_id}/metadata.json"
        return self.s3.upload_json(metadata, s3_key)

    def save_locally(self, local_path: Path, content: bytes) -> Path:
        local_path.parent.mkdir(parents=True, exist_ok=True)
        local_path.write_bytes(content)
        return local_path


class OpenVikingClient:
    def __init__(self, api_url: str = "http://localhost:1934"):
        self.api_url = api_url

    async def health(self) -> bool:
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.api_url}/health", timeout=5) as resp:
                    return resp.status == 200
        except Exception:
            return False

    async def system_status(self) -> dict:
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.api_url}/api/v1/system/status", timeout=5) as resp:
                    return await resp.json()
        except Exception as e:
            return {"status": "error", "error": str(e)}

    async def add_resource(self, path: str, wait: bool = True) -> dict:
        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.api_url}/resources",
                json={"path": path, "wait": wait}
            ) as resp:
                return await resp.json()

    async def search(self, query: str, limit: int = 10) -> list:
        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.api_url}/api/v1/search/find",
                json={"query": query, "limit": limit}
            ) as resp:
                result = await resp.json()
                return result.get("result", [])

    async def get_resource(self, resource_id: str) -> dict:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{self.api_url}/resources/{resource_id}") as resp:
                return await resp.json()
