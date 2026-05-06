# oss-learn

A portable, cross-platform environment for learning and experimenting with open-source ML/data tools. One command sets up a fully running stack on Linux (Ubuntu), macOS (Docker Desktop), or WSL2.

## What's included

| Tool | Port | Purpose |
|------|------|---------|
| PostgreSQL 16 + pgvector + Apache AGE | 5432 | Relational DB + vector similarity + graph queries |
| Prometheus | 9090 | Metrics collection |
| Grafana | 3000 | Dashboards (admin / oss-admin) |
| OpenTelemetry Collector | 4317/4318 | Distributed tracing / metrics ingestion |
| Blackbox Exporter | 9115 | HTTP endpoint probing |
| Ollama | 11434 | Local LLM server |
| ONNX Runtime | pip | CPU inference (Python library) |
| Intel OpenVINO | pip | CPU inference (Python library) |
| OpenSearch + Dashboards | 9200 / 5601 | Full-text search + analytics (optional) |
| Gitea | 3001 | Self-hosted git server (optional) |
| Plane | 4000 | Project management (optional) |
| NocoBase | 13000 | Low-code platform (optional) |
| k3s / minikube | — | Kubernetes (Linux+WSL2 / cross-platform) |
| Wireshark + tshark + pyshark | — | Packet capture / analysis |

## Prerequisites

- **Docker** (Docker Desktop on macOS/WSL2, Docker Engine on Linux)
- **Python 3.10+**
- **Git**
- **8 GB+ RAM** (16 GB recommended for LLM models)
- **20 GB+ free disk** (for model downloads)

## Quick start

```bash
# 1 — Install everything (run once)
bash setup.sh

# 2 — Verify the installation
bash validate.sh

# 3 — Start containers
bash start.sh

# Optional add-ons
bash start.sh --ai           # Ollama + AI inference containers
bash start.sh --opensearch   # OpenSearch + Dashboards
bash start.sh --git          # Gitea
bash start.sh --plane        # Plane project management
bash start.sh --nocobase     # NocoBase low-code platform
bash start.sh --k8s          # k3s cluster (Linux/WSL2)
bash start.sh --minikube     # minikube cluster (cross-platform)
```

## Common commands

```bash
bash setup.sh --check              # show status, no changes
bash setup.sh --step postgres      # run one step only
bash setup.sh --skip ollama        # skip a step
bash setup.sh --force              # redo all steps
bash setup.sh --no-model           # skip LLM model downloads
bash setup.sh --dry-run            # print actions only

bash validate.sh --suite db        # run one validation suite (db|ai|observability|opensearch|git|plane|nocobase|k8s)
bash validate.sh --quick           # fast healthz-only check

bash start.sh --ai                 # + Ollama + AI inference containers
bash start.sh --opensearch         # + OpenSearch + Dashboards
bash start.sh --git                # + Gitea
bash start.sh --plane              # + Plane
bash start.sh --nocobase           # + NocoBase
bash start.sh --k8s                # + k3s cluster (Linux/WSL2)
bash start.sh --minikube           # + minikube cluster (cross-platform)

bash cleanup.sh                    # remove containers, data, venv
```

## Workflow

```
setup.sh  →  validate.sh  →  start.sh
```

## Dashboards

After `bash start.sh`:

| URL | Service | Credentials |
|-----|---------|-------------|
| http://localhost:3000 | Grafana | admin / oss-admin |
| http://localhost:9090 | Prometheus | — |
| http://localhost:9115 | Blackbox Exporter | — |
| http://localhost:11434 | Ollama (with `--ai`) | — |
| http://localhost:9200 | OpenSearch (with `--opensearch`) | — |
| http://localhost:5601 | OpenSearch Dashboards | — |
| http://localhost:3001 | Gitea (with `--git`) | set on first visit |
| http://localhost:4000 | Plane (with `--plane`) | admin@oss-learn.local / admin1234 |
| http://localhost:13000 | NocoBase (with `--nocobase`) | set on first visit |

## Running tests

```bash
# Quick test with dummy data
pytest tests/ -v

# Specific suites
pytest tests/db/ -v             # PostgreSQL + pgvector + AGE
pytest tests/ai/ -v              # ONNX Runtime + Ollama
pytest tests/observability/ -v   # Prometheus + Grafana + Blackbox + OTel
pytest tests/git/ -v             # Gitea API
pytest tests/plane/ -v           # Plane API
pytest tests/nocobase/ -v        # NocoBase API
pytest tests/k8s/ -v             # kubectl + cluster nodes
pytest tests/wireshark/ -v       # tshark + pyshark
```

Tests with no matching service running are skipped automatically.

## Platform notes

| Platform | Docker socket | Notes |
|----------|--------------|-------|
| Linux (Ubuntu 20.04+) | `/var/run/docker.sock` | Standard Docker Engine |
| macOS (Intel/Apple Silicon) | Docker Desktop | Enable in Preferences |
| WSL2 (Windows 10/11) | Docker Desktop WSL2 integration | Enable in Settings → Resources → WSL Integration |

## Structure

```
oss-learn/
├── setup.sh / validate.sh / start.sh / cleanup.sh
├── scripts/
│   ├── common.sh          shared utilities
│   ├── setup/             per-component install scripts (20)
│   ├── validate/          per-suite validation scripts (10)
│   └── start/             per-step startup scripts (11)
├── infra/
│   ├── postgres/          Dockerfile + docker-compose + init.sql (demo schema)
│   ├── observability/     Prometheus + Grafana + OTel + Blackbox + state-exporter
│   ├── opensearch/        OpenSearch + Dashboards
│   ├── git/               Gitea
│   ├── plane/             Plane project management
│   └── nocobase/          NocoBase low-code platform
└── tests/
    ├── db/                PostgreSQL, pgvector, AGE — dummy data CRUD + similarity search + Cypher
    ├── ai/                ONNX Runtime (linear inference), Ollama (generate, embeddings)
    ├── observability/     Prometheus PromQL, Grafana auth, Blackbox probes, OTel health
    ├── git/               Gitea API health
    ├── plane/             Plane API health
    ├── nocobase/          NocoBase API health
    ├── k8s/               kubectl version, cluster nodes, namespace CRUD
    └── wireshark/         tshark CLI + pyshark loopback capture
```
