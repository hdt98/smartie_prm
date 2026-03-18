import os
from pathlib import Path
from dotenv import load_dotenv

env_path = Path(__file__).parent.parent.parent / "mcp_server" / "config_dev" / ".env.local"
load_dotenv(dotenv_path=env_path)

# AWS
AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")
S3_BUCKET = os.getenv("S3_BUCKET", "smartie-enterprise-docs")
S3_REGION = os.getenv("S3_REGION", "us-east-1")
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "")

# Qdrant
QDRANT_HOST = os.getenv("QDRANT_HOST", "localhost")
QDRANT_PORT = int(os.getenv("QDRANT_PORT", "6333"))
QDRANT_COLLECTION = os.getenv("QDRANT_COLLECTION", "smartie_enterprise")

# OpenAI Embeddings
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "text-embedding-3-large")
EMBEDDING_DIMENSION = int(os.getenv("EMBEDDING_DIMENSION", "3072"))

# Worker settings
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "5"))  # seconds
MAX_MESSAGES = int(os.getenv("MAX_MESSAGES", "10"))
VISIBILITY_TIMEOUT = int(os.getenv("VISIBILITY_TIMEOUT", "300"))
