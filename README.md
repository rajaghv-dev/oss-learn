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

bash validate.sh --suite db        # run one validation suite
bash validate.sh --quick           # fast healthz-only check

bash start.sh --ai                 # + AI inference containers
bash start.sh --opensearch         # + OpenSearch

bash cleanup.sh                    # remove containers, data, venv
```

## Workflow

```
setup.sh  →  validate.sh  →  start.sh
```

## Dashboards

After `bash start.sh`:

| URL | Credentials |
|-----|-------------|
| http://localhost:3000 | admin / oss-admin |
| http://localhost:9090 | — |
| http://localhost:9200 | — (OpenSearch, optional) |
| http://localhost:11434 | — (Ollama) |

## Running tests

```bash
# Quick test with dummy data
pytest tests/ -v

# Specific suites
pytest tests/db/ -v          # PostgreSQL + pgvector + AGE
pytest tests/ai/ -v          # ONNX Runtime + Ollama
pytest tests/observability/ -v  # Prometheus + Grafana
```

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
│   ├── setup/             per-component install scripts
│   ├── validate/          per-suite validation scripts
│   └── start/             per-step startup scripts
├── infra/
│   ├── postgres/          Dockerfile + docker-compose + init.sql
│   ├── observability/     Prometheus + Grafana + OTel + Blackbox
│   └── opensearch/        OpenSearch + Dashboards
└── tests/
    ├── db/                PostgreSQL, pgvector, AGE tests with dummy data
    ├── ai/                ONNX Runtime, Ollama tests
    └── observability/     Prometheus, Grafana health tests
```
