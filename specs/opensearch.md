# OpenSearch + Dashboards

> Full-text search engine plus a Kibana-compatible UI for indexing,
> querying, and exploring documents.

| Field | Value |
|-------|-------|
| Category | search / analytics |
| Repo role | optional |
| Install script | scripts/setup/opensearch.sh |
| Validate suite | scripts/validate/opensearch.sh |
| Compose / config | infra/opensearch/docker-compose.yml |
| Default port(s) | 9200 (OpenSearch), 5601 (Dashboards) |
| Default credentials | — (security plugin disabled in dev) |
| Resource footprint | OpenSearch ~1.5 GB RAM (single node, default JVM heap 512 MB), ~700 MB image; Dashboards ~200 MB RAM, ~600 MB image |

## What it is
OpenSearch is the open-source, Elasticsearch-compatible search engine that
exposes a REST API for indexing JSON documents and running full-text,
structured, and aggregation queries. OpenSearch Dashboards is the bundled
Kibana-compatible web UI that sits on top of the same cluster for ad-hoc
exploration, dev-tools console, and visualisations. In oss-learn both run
together as a two-container stack on the host network.

## Why it's in oss-learn
It rounds out the data track with a search-engine option alongside Postgres
full-text and pgvector, so learners can compare lexical search, BM25
ranking, and aggregation queries against the same example data. Dashboards
gives a low-friction UI for poking at indices without writing client code.

## How this repo wires it up
- Two services in `infra/opensearch/docker-compose.yml`: `oss-opensearch`
  (image `opensearchproject/opensearch:2`) and `oss-opensearch-dashboards`
  (image `opensearchproject/opensearch-dashboards:2`).
- Single-node cluster (`discovery.type=single-node`, cluster name
  `oss-cluster`, node `oss-os01`); Java heap pinned to
  `-Xms512m -Xmx512m` to keep RAM bounded on laptops.
- Security plugin is disabled (`DISABLE_SECURITY_PLUGIN=true` and
  `DISABLE_SECURITY_DASHBOARDS_PLUGIN=true`) so dev traffic is plain HTTP
  with no auth — convenient locally, never enable as-is in production.
- Dashboards is wired to the engine via
  `OPENSEARCH_HOSTS=["http://oss-opensearch:9200"]` and waits for the
  engine's healthcheck via `depends_on: condition: service_healthy`.
- Setup script raises `vm.max_map_count` to 262144 with sudo (kernel
  prerequisite for Lucene mmap) and pre-creates `./data/opensearch` and
  `./data/dashboards` then chowns them to uid 1000:0 so the in-container
  `opensearch` user can write — fixes the "Up (unhealthy)" loop that
  otherwise hits new bind mounts.
- After `docker compose up -d`, the script polls `/_cluster/health` for up
  to 90 s and `/api/status` on Dashboards for up to 60 s, then writes
  `setup/state/installs/opensearch.yaml`.
- Ports `9200` (REST), `9300` (transport), `9600` (perf analyzer) and
  `5601` (Dashboards) are published; data persists in the host bind mount
  `infra/opensearch/data/`.
- `OPENSEARCH_PORT` and `OPENSEARCH_DASHBOARDS_PORT` come from
  `.env` / `.env.example`.
- Opt-in only: started by `bash start.sh --opensearch`; the validate suite
  exits 2 (skip) when Docker or the containers are absent.

## Key concepts
- **Index** — Named collection of JSON documents with a mapping; the unit
  of sharding, replication, and search in OpenSearch.
- **Cluster health** — Green / yellow / red signal exposed at
  `/_cluster/health`; single-node clusters sit at yellow because replicas
  cannot be assigned, and oss-learn treats yellow as healthy.
- **Mapping** — Schema describing how each field is analysed (text vs.
  keyword, numeric, date) and stored; controls how queries match
  documents.
- **Query DSL** — JSON query language (`match`, `term`, `bool`, `range`,
  aggregations) sent to `/<index>/_search` over the REST API.
- **Dashboards Dev Tools** — Built-in console at
  `http://localhost:5601/app/dev_tools` that proxies Query DSL requests
  to the cluster — handy for learning without a client library.

## Quick verification
```bash
curl -s http://localhost:9200/_cluster/health | grep -oE '"status":"(green|yellow|red)"'
```
Returns `"status":"yellow"` (or green) once the cluster is up; pair with
`curl -sI http://localhost:5601/api/status` to confirm Dashboards is
reachable.

## Common pitfalls
- `vm.max_map_count` must be ≥262144 — the setup script may set it via
  `sudo sysctl -w vm.max_map_count=262144`; on macOS/Docker Desktop the VM
  handles this transparently and no host change is needed.
- JVM heap defaults to half the host RAM, which crushes laptops; oss-learn
  pins it via `OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m` — override the same
  way if you bump the workload.
- Single-node mode requires `discovery.type=single-node`; without it the
  cluster waits for a quorum forever and `/_cluster/health` never responds.
- Security plugin is disabled in dev (`DISABLE_SECURITY_PLUGIN=true`) —
  never expose port 9200 outside localhost; anyone on the network can read
  and write every index.
- Dashboards relies on an internal `.kibana` index; first boot can take
  60–90 s while it initializes, during which `/api/status` returns 503 even
  though the container is "healthy".

## Suggested example progression
- **Beginner** — `examples/beginner/opensearch_hello.py` — connect to
  `localhost:9200`, create an index, index one document, fetch it back
  *(planned)*
- **Intermediate** — `examples/intermediate/opensearch_search.py` —
  bulk-index sample docs, run `match` and `bool` queries, inspect BM25
  scores *(planned)*
- **Advanced** — `examples/advanced/opensearch_aggregations.py` —
  date-histogram + terms aggregations over a logs-style index, compared
  against equivalent Postgres `GROUP BY` *(planned)*

## Related specs
- [grafana.md](grafana.md) — alternative visualization for time-series,
  complementary to Dashboards when metrics live in Prometheus rather than
  in indices.
- [postgres.md](postgres.md) — relational alternative for structured data;
  pair with OpenSearch to compare lexical search and BM25 against
  Postgres full-text + pgvector on the same dataset.
- [prometheus.md](prometheus.md) — metrics source that can be scraped into
  OpenSearch via exporters when you want long-term retention or Dev Tools
  exploration over historical samples.

## References
- Docs: https://opensearch.org/docs/latest/
- Dashboards docs: https://opensearch.org/docs/latest/dashboards/
- Docker images: https://hub.docker.com/u/opensearchproject
- Query DSL reference:
  https://opensearch.org/docs/latest/query-dsl/
- Cluster health API:
  https://opensearch.org/docs/latest/api-reference/cluster-api/cluster-health/
- Important system settings (vm.max_map_count, ulimits):
  https://opensearch.org/docs/latest/install-and-configure/install-opensearch/index/#important-settings
- Source: https://github.com/opensearch-project/OpenSearch
