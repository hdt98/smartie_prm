# SMARTIE PRM - MVP1

Enterprise Priority Relationship Management AI Agent - MVP1.

## The 3-Tier Architecture

| Component | Dev Environment (Local) | Prod Environment (Cloud) |
|-----------|-------------------------|--------------------------|
| **1. PRM Desktop App** | OpenWork pointing to local MCP server | Installed on User PCs → Cloud Agent |
| **2. Enterprise Agent** | `mcp_server.py` → OpenViking Server (`:1934`) | ECS/Fargate → VPC OpenViking API |
| **3. Knowledge Service** | OpenViking Server (`:1934`) + Docker Qdrant + worker | Auto-scaled OpenViking + EC2 Qdrant + workers |

---

## Dev Environment Setup

### Prerequisites
- Docker installed
- AWS CLI configured (`aws configure`)
- Python 3.10+ with venv

### 1. Start Qdrant (Docker Backend for OpenViking)
```bash
docker run -d --name qdrant -p 6333:6333 -p 6334:6334 qdrant/qdrant
```

### 2. Set Up AWS Infrastructure
Make sure your AWS `ai-dev` IAM user has the permissions defined in `enterprise_service/aws_iam_policy.json`.
```bash
cd ~/Documents/smartie_prm
bash enterprise_service/setup_aws_dev.sh
# Note the QUEUE_URL printed at the end → add to mcp_server/config_dev/.env.local
```

### 3. Start OpenViking Server
OpenViking serves as the primary gateway for both the background Indexing Worker and the live Enterprise Agent.
```bash
cd ~/Documents/smartie_prm
source .venv/bin/activate
nohup openviking-server --config enterprise_service/openviking_configs/local_dev.conf --port 1934 > /tmp/ov-dev.log 2>&1 &
```

### 4. Start the Indexing Worker
The worker polls SQS for S3 drop events and submits them to OpenViking:
```bash
cd ~/Documents/smartie_prm
source .venv/bin/activate
pip install -r enterprise_service/indexing_worker/requirements.txt
python enterprise_service/indexing_worker/worker.py
```

### 5. Start the Enterprise Agent (MCP Server)
The agent will route queries directly to OpenViking on port 1934.
```bash
cd ~/Documents/smartie_prm
source .venv/bin/activate
pip install -r mcp_server/requirements.txt
python mcp_server/mcp_server.py
```

---

## End-to-End Verification

**1. Trigger an Indexing Event**
```bash
cd ~/Documents/smartie_prm
bash enterprise_service/upload_test_data.sh
```
*(Watch the worker terminal — it will pick up the SQS events and tell OpenViking to index the folders).*

**2. Query via OpenWork Desktop App**
- Open **OpenWork Desktop App**, connect to `smartie_prm/`.
- Authenticate.
- Tell the agent to use `search_enterprise_documents` to find information on "thuế thu nhập doanh nghiệp".
