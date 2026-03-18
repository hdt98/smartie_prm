"""
SMARTIE PRM - Indexing Worker
Polls SQS for S3 event notifications and pushes the S3 paths to OpenViking for indexing.
"""
import json
import time
import signal
import sys
import asyncio
from pathlib import Path

import boto3
from config import (
    AWS_ACCESS_KEY_ID,
    AWS_SECRET_ACCESS_KEY,
    S3_REGION,
    SQS_QUEUE_URL,
    POLL_INTERVAL,
    MAX_MESSAGES,
    VISIBILITY_TIMEOUT,
)

import os
import aiohttp
OPENVIKING_ENTERPRISE_URL = os.getenv("OPENVIKING_ENTERPRISE_URL", "http://localhost:1934")

running = True

def signal_handler(sig, frame):
    global running
    print("\n[Worker] Shutting down gracefully...")
    running = False

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

def create_sqs_client():
    return boto3.client(
        "sqs",
        region_name=S3_REGION,
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
    )

def parse_s3_event(message_body: str) -> list[str]:
    keys = []
    try:
        body = json.loads(message_body)
        records = body.get("Records", [])
        for record in records:
            key = record.get("s3", {}).get("object", {}).get("key", "")
            if key:
                keys.append(key)
    except Exception:
        pass
    return keys

async def main():
    print("=" * 60)
    print("SMARTIE PRM - OpenViking Indexing Worker")
    print("=" * 60)
    print(f"  SQS Queue:  {SQS_QUEUE_URL}")
    print(f"  OpenViking: {OPENVIKING_ENTERPRISE_URL}")
    print("=" * 60)

    if not SQS_QUEUE_URL:
        print("[ERROR] SQS_QUEUE_URL is not set.")
        sys.exit(1)

    sqs_client = create_sqs_client()
    
    print("[Worker] Waiting for OpenViking Server...")
    while running:
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{OPENVIKING_ENTERPRISE_URL}/health") as resp:
                    if resp.status == 200:
                        break
        except Exception:
            time.sleep(2)
        
    print("[Worker] OpenViking is healthy! Polling SQS...")

    while running:
        try:
            response = sqs_client.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=MAX_MESSAGES,
                WaitTimeSeconds=POLL_INTERVAL,
                VisibilityTimeout=VISIBILITY_TIMEOUT,
            )

            messages = response.get("Messages", [])
            if not messages:
                continue

            print(f"\n[Worker] Received {len(messages)} message(s)")

            s3_client = boto3.client("s3", region_name=S3_REGION, aws_access_key_id=AWS_ACCESS_KEY_ID, aws_secret_access_key=AWS_SECRET_ACCESS_KEY)
            
            for msg in messages:
                receipt_handle = msg["ReceiptHandle"]
                s3_keys = parse_s3_event(msg["Body"])

                all_success = True
                async with aiohttp.ClientSession() as session:
                    for s3_key in s3_keys:
                        # Prevent infinite loops from OpenViking's own S3 writes
                        if "default/" in s3_key or s3_key.endswith(".md") or s3_key.endswith(".json"):
                            print(f"  [Skip] AGFS metadata / unsupported file: {s3_key}")
                            continue

                        import os
                        import tempfile
                        
                        filename = os.path.basename(s3_key)
                        local_path = os.path.join(tempfile.gettempdir(), filename)
                        
                        print(f"  [Download] s3://smartie-dev-docs-787308165670/{s3_key} -> {local_path}")
                        try:
                            s3_client.download_file("smartie-dev-docs-787308165670", s3_key, local_path)
                        except Exception as e:
                            print(f"  [Error] Failed to download {s3_key}: {e}")
                            all_success = False
                            continue

                        print(f"  [Submit] POST /api/v1/resources {local_path}")
                        try:
                            # Using direct API call to OpenViking
                            payload = {"path": local_path, "wait": True}
                            async with session.post(f"{OPENVIKING_ENTERPRISE_URL}/api/v1/resources", json=payload) as post_resp:
                                result = await post_resp.json()
                                print(f"  [Success] {result}")
                        except Exception as e:
                            print(f"  [Error] Failed to submit {local_path}: {e}")
                            all_success = False

                if all_success:
                    sqs_client.delete_message(QueueUrl=SQS_QUEUE_URL, ReceiptHandle=receipt_handle)

        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"[Worker] Error in poll loop: {e}")
            time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    asyncio.run(main())
