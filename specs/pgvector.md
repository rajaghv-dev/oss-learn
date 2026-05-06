# pgvector

> PostgreSQL extension that adds a `vector` column type and ANN indexes for similarity search.

| Field | Value |
|-------|-------|
| Category | Database / Vector search |
| Repo role | core |
| Install script | scripts/setup/postgres.sh |
| Validate suite | scripts/validate/db.sh |
| Compose / config | infra/postgres/docker-compose.yml (extension enabled by infra/postgres/init.sql) |
| Default port(s) | 5432 (shared with PostgreSQL) |
| Default credentials | postgres / postgres (DB: osslearn) |

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

## Suggested example progression

- **Beginner** — `examples/beginner/02_pgvector_hello.py` — insert a few
  hand-coded vectors into a tiny table and read them back *(planned)*
- **Intermediate** — `examples/intermediate/01_pgvector_search.py` —
  cosine top-k query against `demo.products` *(existing)*
- **Advanced** — `examples/advanced/01_rag_pipeline.py` — Ollama embed,
  pgvector store + ANN search, Ollama generate; full RAG loop *(existing)*

## References

- Docs: https://github.com/pgvector/pgvector#readme
- Source: https://github.com/pgvector/pgvector
