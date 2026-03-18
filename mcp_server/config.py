import os
from pathlib import Path
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).parent

# Load local development environment by default
dev_env_path = PROJECT_ROOT / "config_dev" / ".env.local"
if dev_env_path.exists():
    load_dotenv(dotenv_path=dev_env_path)
else:
    load_dotenv()

# Authentication configured in Azure
AZURE_TENANT_ID = os.getenv("AZURE_TENANT_ID")
AZURE_CLIENT_ID = os.getenv("AZURE_CLIENT_ID")
USE_AUTH = os.getenv("USE_AUTH", "true").lower() == "true"

# Langfuse observability
LANGFUSE_PUBLIC_KEY = os.getenv("LANGFUSE_PUBLIC_KEY")
LANGFUSE_SECRET_KEY = os.getenv("LANGFUSE_SECRET_KEY")
LANGFUSE_HOST = os.getenv("LANGFUSE_HOST", "https://cloud.langfuse.com")
USE_LANGFUSE = os.getenv("USE_LANGFUSE", "false").lower() == "true"

# OpenViking connection
OPENVIKING_ENTERPRISE_URL = os.getenv("OPENVIKING_ENTERPRISE_URL", "http://localhost:1934")
