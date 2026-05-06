# Apache AGE

> PostgreSQL extension that adds property graphs and openCypher queries to the same server that holds the relational data.

| Field | Value |
|-------|-------|
| Category | database / graph |
| Repo role | core |
| Install script | scripts/setup/postgres.sh |
| Validate suite | scripts/validate/db.sh |
| Compose / config | infra/postgres/docker-compose.yml (extension enabled by infra/postgres/init.sql) |
| Default port(s) | 5432 (shared with PostgreSQL) |
| Default credentials | postgres / postgres (DB: osslearn, graph: demo_graph) |
| Resource footprint | shared with postgres, +~10 MB extension |

## What it is

Apache AGE (A Graph Extension) is an Apache-licensed PostgreSQL
extension that stores property graphs in regular tables and exposes
them through openCypher via the `ag_catalog.cypher(...)` function. In
oss-learn it is compiled from source inside the Postgres image, so
graph and relational queries hit the same database and run inside the
same transaction.

## Why it's in oss-learn

It teaches the graph model on infrastructure that learners already
understand — Postgres — so the focus stays on Cypher semantics (MATCH,
MERGE, variable-length paths) rather than on operating a brand-new
database server.

## How this repo wires it up

- Built into the Postgres image: `infra/postgres/Dockerfile` unpacks
  `deps/age.tar.gz` and runs `make install` against PG16, then purges
  the build toolchain to keep the image small.
- AGE source is host-side cloned by `scripts/setup/postgres.sh` (default
  tag `PG16/v1.5.0-rc0`, opt-in `PG16/v1.6.0-rc0` via `--age`) and
  pre-packed as a tarball to dodge WSL2 SSL / rate-limit issues during
  the Docker build.
- `infra/postgres/init.sql` runs `CREATE EXTENSION IF NOT EXISTS age;`,
  `LOAD 'age';`, and `ag_catalog.create_graph('demo_graph')` — the
  graph exists out of the box.
- The chosen AGE tag is recorded in the install manifest at
  `manifests/postgres.yaml` so re-runs are reproducible.
- Depends on PostgreSQL 16; no other component depends on AGE
  directly, but it shares the `osslearn` DB and `demo` schema with
  pgvector.
- Same port, container, and credentials as PostgreSQL — there is no
  separate AGE service.

## Key concepts

- **Graph** — A named container of vertices and edges (`demo_graph`);
  created with `ag_catalog.create_graph(...)` and dropped with
  `drop_graph(...)`.
- **Vertex / edge labels** — Roughly analogous to table names; assigned
  via `MERGE (n:Person {...})` or `MATCH (a)-[r:KNOWS]->(b)`.
- **`cypher()` function** — Cypher is invoked from SQL:
  `SELECT * FROM cypher('demo_graph', $$ MATCH (n) RETURN n $$) AS (n agtype);`
- **agtype** — AGE's JSON-like return type; results must be cast or
  declared in the `AS` clause and unpacked client-side.
- **`LOAD 'age'` + search_path** — Each session must load the AGE
  library and put `ag_catalog` on the search path before Cypher works,
  which is the most common gotcha for new users.

## Quick verification

```bash
docker exec -it oss-postgres psql -U postgres -d osslearn -c "LOAD 'age'; SET search_path = ag_catalog, public; SELECT * FROM cypher('demo_graph', \$\$ RETURN 1 AS one \$\$) AS (one agtype);"
```

Returns a single row containing `1`, proving AGE is installed, the
`demo_graph` exists, and the session can execute Cypher.

## Common pitfalls

- **`LOAD 'age'` is per-session** — Every new connection must run
  `LOAD 'age'; SET search_path = ag_catalog, "$user", public;` before
  Cypher works; this is the most common "function `cypher` does not
  exist" gotcha. Connection-pooling clients should configure this as
  the connection-init query so it is replayed on every checkout.
- **Only `-rc0` tags exist for PG16** — Apache AGE upstream does not
  ship a non-rc release for PG16; the setup script defaults to
  `PG16/v1.5.0-rc0` and accepts `--age v1.6.0-rc0` opt-in. Any other
  tag will fail at `git clone` time during STEP 2 of the setup script.
- **WSL2 SSL / rate-limit issues** — The Dockerfile cannot reliably
  `git clone` from inside WSL2 builds, which is why
  `scripts/setup/postgres.sh` clones AGE on the host and packs it into
  `infra/postgres/deps/age.tar.gz`. Deleting that tarball forces a
  re-clone on the next setup run.
- **First-boot only graph creation** —
  `ag_catalog.create_graph('demo_graph')` runs from `init.sql` against
  an empty `pgdata` volume; if you wipe the database manually, re-run
  `scripts/setup/postgres.sh --force` or call `create_graph` yourself
  before issuing Cypher.
- **`agtype` results need declaring** — Cypher returned via SQL must
  spell out the column types in the `AS (...)` clause (e.g.
  `AS (n agtype)`), otherwise Postgres errors with "a column
  definition list is required for functions returning record".
- **`--local` install path is unimplemented** — Native AGE installs
  are documented in `scripts/setup/postgres.sh` but the `--local`
  branch exits with "not yet implemented"; use Docker mode (the
  default).
- **Image rebuild after `--age` change** — Switching between
  `v1.5.0-rc0` and `v1.6.0-rc0` requires rebuilding the
  `oss-postgres` image; pass `--force` so the existing container is
  torn down before the rebuild.

## Suggested example progression

- **Beginner** — `examples/beginner/03_age_hello.py` — load AGE and run
  `RETURN 1` against `demo_graph` to confirm the round trip *(existing)*
- **Intermediate** — `examples/intermediate/02_age_graph.py` — Cypher
  MATCH / MERGE over a small Person / KNOWS graph *(existing)*
- **Advanced** — `examples/advanced/02_age_pathfinding.py` —
  variable-length paths and shortest-path-style traversals on a seeded
  graph *(existing)*

## Related specs

- [postgres](postgres.md) — base server that hosts this extension, the
  `osslearn` database, and the `demo_graph`; AGE shares its
  transaction model and connection pool.
- [pgvector](pgvector.md) — sibling extension compiled into the same
  image, sharing the `osslearn` database so graph traversals and
  vector search can run in one query.

## References

- Docs: https://age.apache.org/age-manual/master/index.html
- Source: https://github.com/apache/age
- Docker image (pgvector base for AGE build): https://hub.docker.com/r/pgvector/pgvector
