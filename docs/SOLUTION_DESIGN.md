# SMARTIE PRM - MVP1 Solution Design

## 1. Overview

**Project**: SMARTIE PRM (Priority Relationship Management)  
**Version**: MVP1  
**Objective**: Develop an enterprise-wide Priority Relationship Management system. For MVP1, user `sonln4@sonle161290gmail.onmicrosoft.com` is designated as the UAT test user representing the broader enterprise rollout. The system enables users to log in via Microsoft Entra ID and perform AI-driven QnA on enterprise knowledge bases and local files.

---

## 2. The 3-Tier Architecture

The SMARTIE PRM solution is strictly modularized into three distinct functional components. Each component is designed with a clear boundary between its **Local/Development** environment and its **Production (Cloud)** environment.

### Component 1: PRM Desktop App
- **What it is**: The user-facing frontend native application based on OpenWork.
- **Local/Dev Environment**: Runs natively on the developer's machine using `opencode` for local agentic actions. Can either:
  - Route requests via MCP server for Enterprise Agent features (auth, guardrails)
  - OR directly integrate OpenViking via OpenCode plugin for memory search
- **Production Environment**: Packaged and distributed to end-users across the enterprise. Evaluates enterprise queries by communicating with the Cloud-hosted Enterprise Agent.

### Component 2: Enterprise Agent
- **What it is**: The orchestration and security layer. It hosts the MCP Server, Observability (Langfuse telemetry), Guardrails (PII shielding), and Microsoft Entra Auth integration. It delegates all search queries to the **OpenViking Knowledge API**.
- **Local/Dev Environment**: Runs as a local Python process (`mcp_server/mcp_server.py`) using configurations from `mcp_server/config_dev/.env.local`. Connects to a local OpenViking server on port 1934.
- **Production Environment**: Deployed centrally in the Cloud (AWS ECS/Fargate). Connects to the Cloud OpenViking Knowledge Service endpoint.

### Component 3: Enterprise Knowledge Service
- **What it is**: The system of record for parsing, indexing, and serving semantic chunks of enterprise documents. It logically splits into three sub-components:
  - **OpenViking Server**: The active intelligence layer serving as the exclusive entry point. It handles `add_resource` indexing jobs and `search` query evaluation.
  - **Qdrant Vector DB**: The underlying, "dumb" storage backend attached to OpenViking to persist dense vectors.
  - **Event-Driven Indexing Worker**: A background service polling SQS for S3 ObjectCreated events. Instead of doing the heavy embedding work itself, it proxies the S3 paths to OpenViking's `add_resource` API.
- **Local/Dev Environment**: Runs locally. OpenViking on port 1934, Qdrant on Docker (port 6333), and a local Python worker polling the Dev SQS queue.
- **Production Environment**: OpenViking deployed on AWS ECS/Fargate as an auto-scaled API handling both active queries from the Agent and background indexing jobs. Qdrant on EC2 with EBS storage. Indexing Worker deployed on AWS ECS/Fargate as a scalable background service.

---

## 3. Architecture Diagrams

### Development Environment (Local)
```
┌─────────────────┐       ┌────────────────────┐
│ PRM Desktop App │──────▶│  Enterprise Agent  │ search
│ (OpenWork UI)   │       │  (MCP Server)     │───────────────┐
│ opencode stdio  │       │  config_dev/.env  │               ▼
└─────────────────┘       └────────────────────┘       ┌─────────────┐
                                                       │  OpenViking │
  S3 Event    ┌─────────┐   poll      ┌───────────────▶│ (Port 1934) │
 ────────────▶│ AWS SQS │────────────▶│  Indexing     └──────┬──────┘
              │ (Dev)   │             │  Worker              │ upsert
              └─────────┘             │ (Pushes path to)     ▼
                                     └───────────────▶  ┌─────────────┘
                                                          │   Qdrant    │
                                                          │   (:6333)   │
                                                          └─────────────┘
```

### Production Environment (Cloud Deployment)
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLOUD VPC                                      │
│                                                                              │
│   ┌─────────────────┐       ┌──────────────┐                               │
│   │ PRM Desktop App │       │ Ent. Agent   │                               │
│   │ (OpenWork UI)   │──SSE─▶│(ECS/Fargate)│                               │
│   └─────────────────┘       └──────┬───────┘                               │
│                                     │ search                                 │
│                                     ▼                                       │
│                            ┌────────────────┐                                │
│                            │  OpenViking   │                                │
│                            │(ECS/Fargate)  │◀──────┐                        │
│                            └───────┬────────┘       │ add                   │
│                                    │ upsert         │                        │
│                                    ▼               │                        │
│                            ┌──────────────┐       │                        │
│                            │   Qdrant     │       │                        │
│                            │ (EC2 + EBS)  │       │                        │
│                            └──────────────┘       │                        │
│                                                     │                        │
│   ┌──────────┐  S3 Event    ┌─────────────────┐  │                        │
│   │  AWS S3  │─────────────▶│ Indexing Worker │──┘                        │
│   └──────────┘              │ (ECS/Fargate)  │                            │
│                              └─────────────────┘                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Repository Structure & Boundaries

```
smartie_prm/
├── opencode.json                         # COMPONENT 1: PRM Desktop config
│
├── mcp_server/                           # COMPONENT 2: Enterprise Agent
│   ├── config_dev/.env.local             #   Dev environment vars
│   ├── mcp_server.py                     #   MCP server (queries OpenViking)
│   └── ...
│
├── enterprise_service/                   # COMPONENT 3: Knowledge Service
│   ├── indexing_worker/                  #   SQS consumer → OpenViking proxy
│   │   └── worker.py                     #     Main Python worker
│   ├── openviking_configs/               #   OpenViking (AGFS=S3, DB=Qdrant)
│   │   ├── local_dev.conf                
│   │   └── cloud_prod.conf               
│   ├── setup_aws_dev.sh                  #   Creates SQS & S3 notifications
│   ├── aws_iam_policy.json               #   Required Cloud IAM Permissions
│   └── upload_test_data.sh               #   Test data ingestion trigger
│
└── openviking/                           #   OpenViking shared Python client
```

---

## 5. Success Criteria

1. ✅ 3-Tier architecture explicitly defines boundaries between the UI, the Agent, and the Knowledge Service.
2. ✅ S3 document uploads trigger SQS events that the Indexing Worker processes in real-time.
3. ✅ OpenViking handles all semantic intelligence (embedding, tracking metadata).
4. ✅ Qdrant serves purely as the scalable vector database backend.
5. ✅ Enterprise Agent queries strictly hit OpenViking, completely isolating the core Agent from DB implementation details.
