# PostgreSQL 16

> Relational database that hosts the demo schema and acts as the substrate for pgvector and Apache AGE.

| Field | Value |
|-------|-------|
| Category | database |
| Repo role | core |
| Install script | scripts/setup/postgres.sh |
| Validate suite | scripts/validate/db.sh |
| Compose / config | infra/postgres/docker-compose.yml |
| Default port(s) | 5432 (postgres), 5050 (pgAdmin, profile-gated) |
| Default credentials | postgres / postgres (DB: osslearn); demo / demo_dev (app role) |
| Resource footprint | ~250 MB RAM idle, ~600 MB image |

## What it is

PostgreSQL 16 is the open-source relational database that serves as the
storage backbone of oss-learn. The container is built from
`pgvector/pgvector:pg16` with Apache AGE compiled in, so a single server
provides relational, vector, and graph workloads side by side.

## Why it's in oss-learn

It anchors the database track of the curriculum: every other DB-flavoured
tool in the repo (pgvector, AGE, the RAG pipeline) builds on this one
server, so learners practise schema design, extensions, and SQL on the
same instance they later query with vectors and Cypher.

## How this repo wires it up

- Docker-only install — no `--local` path yet; the script logs an explicit
  "not yet implemented" message and exits if `--local` is passed.
- Image: `oss-postgres:pg16-pgvector-age`, built from
  `infra/postgres/Dockerfile` (base `pgvector/pgvector:pg16`).
- `infra/postgres/init.sql` and `extensions.sql` are mounted into
  `/docker-entrypoint-initdb.d/` so the `osslearn` DB, `demo` schema,
  extensions, and seed rows are created on first boot.
- Persistent state in the named volume `pgdata`; host bind mount
  `./data/postgres` is also created for inspection.
- Compose healthcheck (`pg_isready`) gates dependent services such as
  `oss-pgadmin` (only started under the `pgadmin` profile).
- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_PORT`
  come from `.env` / `.env.example`.
- No upstream dependencies; downstream consumers include the
  Ollama-driven RAG example and the `db` validation suite.

## Key concepts

- **osslearn database** — Single application database created by
  `init.sql`; all demo tables live in the `demo` schema.
- **Extensions** — `vector`, `age`, `pg_trgm`, and `uuid-ossp` are enabled
  at init time so examples never have to bootstrap them.
- **Demo tables** — `demo.products`, `demo.documents`, and `demo.events`
  give learners ready-made rows for SELECT, JSONB, full-text, and vector
  queries.
- **Roles** — A least-privilege `demo` user (password `demo_dev`) is
  created alongside the superuser so app-style code paths can be
  exercised without running as `postgres`.
- **pgAdmin profile** — The compose `pgadmin` service is gated behind a
  Docker Compose profile and only starts when explicitly requested.

## Quick verification

```bash
docker exec -it oss-postgres psql -U postgres -d osslearn -c "SELECT version();"
```

Prints a single row with `PostgreSQL 16.x ...`, confirming the container
is up and the `osslearn` database is reachable.

## Common pitfalls

- **Port 5432 already bound on the host** — A native `postgresql`
  service or another container with `postgres`/`pg` in its name will
  block the bind. The setup script's STEP 1 detects this and warns;
  either stop the offending process (`docker stop <name>`), re-run
  `scripts/setup/postgres.sh --force` to auto-remove conflicting
  containers, or change `POSTGRES_PORT` in `.env` and update the
  compose port mapping.
- **First-boot timing** — The mounted `init.sql` and `extensions.sql`
  scripts only run on the *first* container start, when `pgdata` is
  empty. Editing them after that has no effect until you wipe the
  named volume (`docker compose down -v`) or re-run setup with
  `--force`. The `IF NOT EXISTS` guards everywhere mean re-running by
  hand against an existing DB is also safe.
- **`--local` install path is unimplemented** — Passing `--local` to
  `scripts/setup/postgres.sh` logs an explicit "not yet implemented"
  message and exits non-zero. Use the default Docker path; the local
  branch is documented inline as a future enhancement.
- **Credentials are demo defaults** — `postgres/postgres` and
  `demo/demo_dev` are baked into `init.sql` and `.env.example`; rotate
  them before exposing the port outside localhost. The `demo` role is
  scoped to the `demo` schema so it's safe for example code, but it's
  not safe for shared environments.
- **AGE build is slow on first boot** — The image build compiles AGE
  from source against `postgresql-server-dev-16` (~5 min on WSL2);
  subsequent `docker compose up` calls reuse the cached
  `oss-postgres:pg16-pgvector-age` image and start in seconds.
- **Docker group not yet active** — Newly added `docker` group members
  may hit EACCES on `/var/run/docker.sock`; the setup script
  re-execs itself under `sg docker` automatically, but a fresh shell
  (`newgrp docker`) is the cleanest fix.

## Suggested example progression

- **Beginner** — `examples/beginner/01_postgres_hello.py` — connects to
  `osslearn` and prints the server version *(existing)*
- **Intermediate** — `examples/intermediate/03_postgres_crud.py` —
  INSERT/SELECT/UPDATE against `demo.products` with parameterised
  queries *(existing)*
- **Advanced** — `examples/advanced/01_rag_pipeline.py` — Ollama embed,
  pgvector store, Ollama generate; end-to-end RAG pipeline running on
  this Postgres instance *(existing)*

## Related specs

- [pgvector](pgvector.md) — vector-search extension bundled in the same
  image and database; provides the `vector` type and ANN indexes used
  by the RAG example.
- [apache-age](apache-age.md) — sibling property-graph extension that
  shares this server, the `osslearn` database, and the `5432` port.
- [ollama](ollama.md) — provides embeddings and generation for the
  advanced RAG example that runs against this Postgres instance.

## References

- Docs: https://www.postgresql.org/docs/16/index.html
- Source: https://github.com/postgres/postgres
- Docker image (pgvector base): https://hub.docker.com/r/pgvector/pgvector
