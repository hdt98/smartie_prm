# SMARTIE PRM - MVP1 Solution Design

## 1. Overview

**Project**: SMARTIE PRM (Priority Relationship Management)  
**Version**: MVP1  
**Objective**: Develop an enterprise-wide Priority Relationship Management system. For MVP1, user `sonln4@sonle161290gmail.onmicrosoft.com` is designated as the UAT test user representing the broader enterprise rollout. The system enables users to log in via Microsoft Entra ID and perform AI-driven QnA on enterprise knowledge bases and local files.

---

## 2. Architecture

SMARTIE PRM uses a simplified architecture with direct OpenCode + OpenViking integration:

### Search Flow (Direct)
- PRM Desktop (OpenCode) → **OpenCode Plugin** → OpenViking → Qdrant

The OpenCode plugin directly calls OpenViking's search API, bypassing the MCP server layer. This follows the [OpenViking Memory Plugin](https://github.com/volcengine/OpenViking/blob/main/examples/opencode-memory-plugin/README.md) pattern.

### Indexing Flow (Event-Driven)
- Documents uploaded to S3 → SQS event → Indexing Worker → OpenViking → Qdrant

### Components

| Component | Description |
|-----------|-------------|
| **PRM Desktop (OpenCode)** | User-facing frontend. Uses OpenCode plugin for direct OpenViking search. |
| **OpenCode Plugin** | Direct integration with OpenViking's search API (`memsearch`, `memread`, etc.) |
| **OpenViking Server** | Handles `add_resource` indexing and `search` query evaluation |
| **Qdrant Vector DB** | Storage backend for persisting dense vectors |
| **Indexing Worker** | Polls SQS for S3 events, pushes file paths to OpenViking |

---

## 3. Architecture Diagrams

### Development Environment (Local)

```mermaid
flowchart LR
    subgraph OpenCode["PRM Desktop (OpenCode)"]
        Plugin["OpenCode Plugin\n(memsearch, memread)"]
    end

    subgraph Services["Services"]
        OV[("OpenViking\nPort 1934")]
        Qdrant[("Qdrant\n:6333")]
        SQS[("AWS SQS\nDev")]
    end

    subgraph Worker["Indexing Worker"]
        WorkerProc[("Python Worker\nPolls SQS")]
    end

    S3[(S3 Bucket\nsmartie-dev-docs)] -->|S3 Event| SQS
    SQS -->|poll| WorkerProc
    WorkerProc -->|add path| OV
    Plugin -->|search| OV
    OV -->|upsert| Qdrant
```

### Production Environment (Cloud Deployment - EKS)

```mermaid
flowchart TB
    subgraph Client["Client Side"]
        App["PRM Desktop\n(OpenCode)"]
    end

    subgraph CloudVPC["Cloud VPC"]
        subgraph EKS["Amazon EKS"]
            subgraph K8s["Kubernetes Namespace: smartie-prm"]
                PluginPod["OpenCode Plugin\n(Deployment)"]
                WorkerPod["Indexing Worker\n(Deployment)"]
                OVPod["OpenViking\n(Deployment)"]
            end
        end

        subgraph Storage["AWS Storage"]
            QdrantEC2["Qdrant\nEC2 + EBS"]
        end
    end

    subgraph AWS["AWS Services"]
        S3["S3 Bucket"]
        SQS["SQS Queue"]
        ECR["ECR\nContainer Registry"]
    end

    App -->|search| PluginPod
    PluginPod -->|search| OVPod
    S3 -->|S3 Event| SQS
    SQS -->|poll| WorkerPod
    WorkerPod -->|add path| OVPod
    OVPod -->|upsert| QdrantEC2
```

---

## 4. CI/CD Pipeline (GitOps with GitHub + ArgoCD)

### Overview

The CI/CD follows enterprise-grade GitOps pattern:

```mermaid
flowchart TB
    subgraph CI["Phase 1: CI (GitHub Actions)"]
        Dev["Developer\nPush/MR"]
        GHA["GitHub\nActions"]
        Test["Tests\n& Scan"]
        Build["Build\nImage"]
        ECR["Amazon ECR"]
        Update["Update Helm\nvalues.yaml"]
        GitOps["GitOps Repo\n(hdt98/smartie-prm-gitops)"]
    end

    subgraph CD["Phase 2: CD (ArgoCD)"]
        Argo["ArgoCD\n(in EKS)"]
        Sync["Sync & Deploy"]
        EKSCluster["EKS Cluster"]
    end

    Dev -->|1. Push Code| GHA
    GHA -->|2. Run Tests| Test
    Test -->|3. Security Scan| Build
    Build -->|4. Push Image| ECR
    ECR -->|5. Update Image Tag| Update
    Update -->|6. Commit| GitOps
    GitOps -->|7. Detect Change| Argo
    Argo -->|8. Sync| EKSCluster
```

### Why This Stack for Enterprise

| Feature | Tool | Benefit |
|---------|------|----------|
| **Separation of Duties** | GitHub Actions vs ArgoCD | CI builds code but never accesses production. Only ArgoCD has cluster credentials. |
| **Auditability** | GitHub | Every production change is a Git commit with full traceability. |
| **State Consistency** | ArgoCD | If someone manually alters a setting in EKS, ArgoCD automatically reverts to Git state. |

### Workflow

1. **Developer** pushes code or opens PR
2. **GitHub Actions** triggers pipeline:
   - Run unit & integration tests
   - Security scan (Trivy/SonarQube)
   - Build Docker image
   - Push to Amazon ECR
3. **GitHub Actions** updates Helm chart image tag in GitOps repo
4. **ArgoCD** detects drift and syncs to EKS

---

## 5. Repository Structure

```
smartie_prm/
├── opencode.json                         # OpenCode config with plugin
│
├── openviking/                           # OpenCode plugin for direct search
│   ├── plugin/                           #   TypeScript plugin
│   │   ├── src/                         #     Source code
│   │   ├── dist/                        #     Compiled JS
│   │   ├── package.json                 #     Build config
│   │   └── tests/                       #     Unit tests
│   └── sync.py                          #   Python sync client
│
├── enterprise_service/                   # Knowledge Service
│   ├── indexing_worker/                  #   SQS consumer → OpenViking
│   │   ├── worker.py                    #     Main worker
│   │   ├── config.py                   #     Config
│   │   └── Dockerfile                  #     Container definition
│   ├── openviking_configs/              #   OpenViking configs
│   │   ├── local_dev.conf               #     Dev environment
│   │   └── cloud_prod.conf              #     Production
│   ├── setup_aws_dev.sh                #   AWS setup
│   └── upload_test_data.sh             #   Test data upload
│
├── .github/
│   └── workflows/
│       └── ci.yml                      # GitHub Actions CI workflow
│
├── k8s/                                 # Kubernetes manifests
│   ├── base/                           #   Base Helm charts
│   └── overlays/                      #   Environment overlays
│
└── docs/                                # Documentation
    └── SOLUTION_DESIGN.md
```

---

## 6. OpenCode Plugin

The OpenCode plugin provides direct access to OpenViking's search capabilities:

### Available Tools
- `memsearch` - Search across memories, resources, skills
- `memread` - Read content from URI
- `membrowse` - Browse filesystem structure
- `memcommit` - Trigger memory extraction

### Configuration
```json
{
  "endpoint": "http://localhost:1934",
  "apiKey": "your-openviking-api-key",
  "enabled": true
}
```

---

## 7. Kubernetes Deployment

### Services Deployed to EKS

| Service | Type | Replicas | Description |
|---------|------|----------|-------------|
| `openviking` | Deployment | 2 | OpenViking API server |
| `indexing-worker` | Deployment | 2 | SQS polling worker |
| `qdrant` | StatefulSet | 1 | Vector database (EC2 with EBS) |

### AWS Resources

| Resource | Type | Purpose |
|----------|------|---------|
| EKS Cluster | Managed K8s | Compute layer |
| ECR | Container Registry | Docker image storage |
| S3 | Object Storage | Document storage |
| SQS | Queue | Event queue |
| EBS | Block Storage | Qdrant persistence |
| IAM | Identity | Pod execution role |

---

## 8. Success Criteria

1. ✅ OpenCode directly integrates with OpenViking via plugin for search
2. ✅ S3 document uploads trigger SQS events that Indexing Worker processes
3. ✅ OpenViking handles all semantic intelligence (embedding, parsing)
4. ✅ Qdrant serves as the vector database backend
5. ✅ Simplified architecture - no MCP server layer for MVP1
6. ✅ Enterprise CI/CD with GitHub Actions + ArgoCD + GitOps
7. ✅ EKS as managed Kubernetes for production workloads
