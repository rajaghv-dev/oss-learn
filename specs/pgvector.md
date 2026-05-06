# pgvector

> PostgreSQL extension that adds a `vector` column type and ANN indexes for similarity search.

| Field | Value |
|-------|-------|
| Category | database / vector search |
| Repo role | core |
| Install script | scripts/setup/postgres.sh |
| Validate suite | scripts/validate/db.sh |
| Compose / config | infra/postgres/docker-compose.yml (extension enabled by infra/postgres/init.sql) |
| Default port(s) | 5432 (shared with PostgreSQL) |
| Default credentials | postgres / postgres (DB: osslearn) |
| Resource footprint | shared with postgres, +~50 MB index per million 768-d vectors |

## What it is

pgvector is an open-source PostgreSQL extension that introduces a
fixed-dimension `vector` data type along with cosine, L2, and
inner-product distance operators and IVFFlat / HNSW indexes. In
oss-learn it ships pre-built inside the `pgvector/pgvector:pg16` base
image, so it becomes available the moment the container starts.

## Why it's in oss-learn

Vector search is the connective tissue between classical SQL and modern
LLM workflows; pgvector lets learners practise embeddings, top-k
similarity, and RAG patterns without standing up a separate vector
database.

## How this repo wires it up

- Bundled with the Postgres container — the Dockerfile inherits from
  `pgvector/pgvector:pg16`, so there is no separate install step or
  build stage for the extension itself.
- Enabled per database via `CREATE EXTENSION IF NOT EXISTS vector;` in
  `infra/postgres/init.sql`; `infra/postgres/extensions.sql` does the
  same for any additional databases learners create.
- Demo schema includes `demo.products.embedding vector(3)` and
  `demo.documents.embedding vector(3)` (3-dim for didactic simplicity;
  production code typically uses 768 / 1024 / 1536).
- IVFFlat cosine index pre-built:
  `idx_products_embedding ... USING ivfflat (embedding vector_cosine_ops) WITH (lists = 10)`.
- Depends on PostgreSQL 16; consumed by `examples/advanced/01_rag_pipeline.py`
  together with Ollama for embedding generation and answer synthesis.
- No extra ports, env vars, or compose services beyond the base
  Postgres entry — pgvector is purely an in-process extension.

## Key concepts

- **vector(N)** — Fixed-dimension float4 array column type; the
  dimension is part of the type and is validated on every insert.
- **Distance operators** — `<=>` cosine, `<->` L2, `<#>` (negative)
  inner product; pick the one that matches how the embeddings were
  trained.
- **IVFFlat index** — Inverted-file ANN index; trades a small recall hit
  for big speed wins, and needs a `lists` parameter sized to row count.
- **HNSW index** — Graph-based ANN alternative (no training step,
  higher build cost, better recall at high QPS); a useful upgrade once
  learners outgrow IVFFlat.
- **Top-k query shape** — `ORDER BY embedding <=> $1 LIMIT k` is the
  canonical similarity search pattern and the one used by every example.

## Quick verification

```bash
docker exec -it oss-postgres psql -U postgres -d osslearn -c "SELECT name, embedding <=> '[1,0,0]'::vector AS dist FROM demo.products ORDER BY dist LIMIT 3;"
```

Returns the three products closest (cosine) to `[1,0,0]`, with
`Widget A` at the top — proves the extension, the index, and the seed
data are all live.

## Common pitfalls

- **Extension version is pinned to the base image** — pgvector ships
  pre-built inside `pgvector/pgvector:pg16`, so you cannot upgrade it
  independently without rebuilding the Postgres image. A client
  library expecting a newer `vector` type (e.g. `halfvec` from
  pgvector 0.7+) will fail at `CREATE EXTENSION` time on an older
  base.
- **Dimension mismatch** — `vector(N)` validates the dimension on
  every insert; the demo tables use `vector(3)` for didactic clarity,
  so embeddings from a real model (768 / 1024 / 1536) will be rejected
  unless you `ALTER TABLE demo.products ALTER COLUMN embedding TYPE
  vector(N)` first and rebuild the IVFFlat index.
- **Distance operator vs index ops class must match** — An IVFFlat
  index built `WITH vector_cosine_ops` will not be used by an `<->`
  (L2) query; pick one distance metric and stick with it across the
  schema, the index, and the query. Use `EXPLAIN` to confirm the
  index is actually being chosen.
- **First-boot only init** — The pre-built `idx_products_embedding`
  IVFFlat index and the seeded rows are created by `init.sql`, which
  only runs on a fresh `pgdata` volume. Re-run
  `scripts/setup/postgres.sh --force` to drop the volume and rebuild
  if the index gets out of sync.
- **Port 5432 conflict on the host** blocks the whole stack — including
  this extension — because it can't run without the Postgres
  container. Change `POSTGRES_PORT` in `.env` and the compose port
  mapping if you need a different host port.
- **IVFFlat needs training data** — The `lists` parameter should
  roughly equal `sqrt(rows)`; the demo uses `lists = 10` for the tiny
  seed dataset, but real workloads must rebuild the index with a sane
  value after bulk-loading, otherwise recall and latency both suffer.
- **Probes vs recall trade-off** — Tune `SET ivfflat.probes = N` per
  session to widen the search; higher `N` means better recall at the
  cost of more list scans.

## Suggested example progression

- **Beginner** — `examples/beginner/02_pgvector_hello.py` — insert a few
  hand-coded vectors into a tiny table and read them back *(planned)*
- **Intermediate** — `examples/intermediate/01_pgvector_search.py` —
  cosine top-k query against `demo.products` *(existing)*
- **Advanced** — `examples/advanced/01_rag_pipeline.py` — Ollama embed,
  pgvector store + ANN search, Ollama generate; full RAG loop *(existing)*

## Related specs

- [postgres](postgres.md) — base server that hosts this extension, the
  `osslearn` database, and the `demo` schema with seeded vectors.
- [apache-age](apache-age.md) — sibling extension compiled into the
  same image so graph and vector queries can share a transaction.
- [ollama](ollama.md) — generates the embeddings consumed by the
  advanced RAG example, which writes them into the `vector(N)` columns
  defined here.

## References

- Docs: https://github.com/pgvector/pgvector#readme
- Source: https://github.com/pgvector/pgvector
- Docker image: https://hub.docker.com/r/pgvector/pgvector
