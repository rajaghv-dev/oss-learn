# NocoBase

> Self-hosted, extensible low-code platform that turns a Postgres schema into tables, forms, and workflows for hands-on data-app practice.

| Field | Value |
|-------|-------|
| Category | low-code / data app |
| Repo role | optional |
| Install script | scripts/setup/nocobase.sh |
| Validate suite | `scripts/validate/nocobase.sh` |
| Compose / config | infra/nocobase/docker-compose.yml |
| Default port(s) | 13000 |
| Default credentials | set on first visit (seeded as admin@nocobase.com / admin1234 via INIT_ROOT_*) |
| Resource footprint | ~400 MB RAM (app + postgres), ~700 MB images |

## What it is
NocoBase is an open-source, plugin-based low-code platform: collections
(data tables), block-based UI (forms, tables, kanban, calendars), and
workflows backed by a real database. In oss-learn it runs from
`nocobase/nocobase:latest` against a dedicated `postgres:16-alpine`,
exposed on `http://localhost:13000`. Almost every feature, including
auth, file storage, and data sources, is shipped as a plugin, so the
running instance doubles as a worked example of a plugin-driven app
where the same configuration model that builds business apps is also
how the platform extends itself.

## Why it's in oss-learn
It complements the SQL-first track by showing how a low-code layer
composes on top of a relational schema. Learners can model entities,
build a UI without writing frontend code, and then drop down to the
underlying Postgres to see the tables and queries the platform
generates from their visual changes — useful for understanding what a
"low-code" tool actually emits at the storage layer.

## How this repo wires it up
- Docker-only install: `infra/nocobase/docker-compose.yml` defines two containers, `oss-nocobase` (the app) and `oss-nocobase-db` (Postgres 16).
- Image: `nocobase/nocobase:latest` for the app, `postgres:16-alpine` for the database.
- App env: `DB_DIALECT=postgres`, `DB_HOST=oss-nocobase-db`, `DB_PORT=5432`, `DB_DATABASE=nocobase`, `DB_USER=nocobase`, `DB_PASSWORD=nocobase_secret`, plus `SECRET=nocobase-oss-secret-key` for token signing.
- `INIT_ROOT_EMAIL=admin@nocobase.com`, `INIT_ROOT_PASSWORD=admin1234`, `INIT_ROOT_NICKNAME=Admin` seed the root account on first boot, so the credentials field above lists "set on first visit" only because the user is expected to confirm or change them in the UI.
- Container port `80` is published as host `13000`; persistent state lives under `infra/nocobase/data/storage` (app) and `infra/nocobase/data/pgdata` (Postgres) via host bind mounts.
- The `nocobase` service `depends_on` `nocobase-db` with `condition: service_healthy`, so the app only starts once Postgres is accepting connections.
- The DB healthcheck runs `pg_isready -U nocobase`; the app healthcheck pings `http://localhost:80/api/app:getInfo` with a 60 s `start_period`, which is the same endpoint the validate suite uses externally.
- The Postgres backing this app is a separate instance from the main `oss-postgres`, so NocoBase can be torn down with `--force` (which runs `down -v --remove-orphans`) without affecting the rest of the curriculum.
- `scripts/setup/nocobase.sh` waits up to 150 s on `GET /api/app:getInfo` (30 attempts × 5 s) to absorb the first-run schema install, then writes `setup/state/installs/nocobase.yaml`.
- `scripts/setup/nocobase.sh` supports `--check` (status only, no changes) and `--force` (rebuild from scratch) on top of the default install.
- `scripts/validate/nocobase.sh` confirms both containers are running and probes `/api/app:getInfo`; like the other suites it returns exit code 2 if Docker is absent so the umbrella validator can skip cleanly.
- No upstream oss-learn services are required; the stack is self-contained and can be torn down independently of Postgres, Plane, or Gitea.
- The success manifest records `compose=infra/nocobase/docker-compose.yml, container=oss-nocobase, web_url=http://localhost:13000, data_dir=infra/nocobase/data` for later inspection.
- The validate suite is also reachable via `bash validate.sh --suite nocobase` from the repo root.

## Key concepts
- **Collection** — A schema-defined data table; fields can be plain columns, relations, or computed values, and each collection becomes both a database table in Postgres and an API resource.
- **Block** — A UI building block (table, form, details, kanban, calendar, chart) bound to a collection and composed onto a page in the visual designer.
- **Workflow** — Event- or schedule-triggered automations (record created/updated, cron, manual) built from action nodes such as create/update/query/HTTP-request.
- **Plugin system** — Almost every feature ships as a plugin that can be enabled, disabled, or extended; the same mechanism is how third-party features are added.
- **`/api/app:getInfo`** — The lightweight readiness endpoint used by the container healthcheck and the validate suite to confirm the app has finished booting and is serving the API.
- **REST resource naming** — The API uses `:` to separate resource and action (e.g. `/api/<collection>:list`, `/api/<collection>:create`), which is the same shape as the bootstrap endpoint.
- **`INIT_ROOT_*` seeding** — The first boot reads `INIT_ROOT_EMAIL` / `INIT_ROOT_PASSWORD` / `INIT_ROOT_NICKNAME` from env to create the initial superuser, and ignores them on subsequent starts.
- **Bind-mounted storage** — `/app/nocobase/storage` (uploads, generated files) is mounted at `infra/nocobase/data/storage`; pgdata is at `infra/nocobase/data/pgdata`, both surviving `--force` rebuilds unless `down -v` runs.
- **Healthcheck-gated startup** — The app waits on the DB's `pg_isready` healthcheck before its own boot, and its `start_period: 60s` keeps Docker from killing the container while first-run schema install runs.
- **Postgres backing store** — `oss-nocobase-db` is a dedicated Postgres 16 instance (DB `nocobase`, user `nocobase`) separate from both the main `oss-postgres` and the Plane/Gitea databases.
- **External data sources** — In addition to its own Postgres, NocoBase plugins can connect to additional databases as data sources, so the same UI can wrap an existing schema without copying data.
- **Pre-built admin UI** — `/admin` is the configuration surface used by builders; end-user pages are composed inside the same SPA but rendered without the design chrome.
- **Roles and permissions** — A built-in plugin defines roles (root, admin, member, anonymous) and per-collection action permissions, layered on top of the auth plugin.

## Quick verification
```bash
curl -s http://localhost:13000/api/app:getInfo
```
Returns a small JSON document describing the running NocoBase app (version, lang, etc.) once first-run install has completed; a 404 or empty body means the app process has not yet finished bootstrapping.

## Common pitfalls
- **First-visit setup flow if `INIT_ROOT_*` vars are unset** — the bundled compose file seeds `admin@nocobase.com` / `admin1234` via `INIT_ROOT_EMAIL` / `INIT_ROOT_PASSWORD` / `INIT_ROOT_NICKNAME`; if any are missing the app falls back to an interactive setup wizard on first load and the seeded creds in this spec will not work.
- **Needs Postgres (and Redis for some plugins)** — the app refuses to boot without a healthy DB; `oss-nocobase` waits on `oss-nocobase-db`'s `pg_isready` healthcheck, and several plugins (workflow, queue) further expect a Redis instance — this stack does not ship one, so those plugins stay disabled.
- **150 s readiness window covers first-run schema install** — `scripts/setup/nocobase.sh` polls `GET /api/app:getInfo` for up to 150 s (30 × 5 s) so the initial schema install can finish; before that completes the API returns 404 even though the container is "running".
- **Some plugins require manual install via the UI** — only the core plugins are enabled out of the box; data-source connectors, charts, workflow extensions etc. must be enabled (or in some cases uploaded) from `Settings → Plugins`, and a few need a container restart to register.
- **`--force` wipes the dedicated Postgres** — `down -v --remove-orphans` drops the volume, so any collections, records, and plugin state created during exploration are lost on rebuild.

## Suggested example progression
- **Beginner** — `examples/beginner/nocobase_hello.py` — call `/api/app:getInfo` and print the version + boot status
- **Intermediate** — `examples/intermediate/nocobase_collection_crud.py` — create a `note` collection, insert 3 records, list, update, delete via the REST API
- **Advanced** — `examples/advanced/nocobase_workflow.py` — define a collection plus a workflow that fires on insert and posts to a local webhook

## Related specs
- [postgres.md](postgres.md) — the relational store NocoBase models on top of; useful for inspecting the tables and queries the platform generates from visual changes.
- [gitea.md](gitea.md) — Gitea webhooks make a natural workflow trigger for NocoBase automations on push or pull-request events.

## References
- Docs: https://docs.nocobase.com/
- Source: https://github.com/nocobase/nocobase
- API guide: https://docs.nocobase.com/api
- Plugin development: https://docs.nocobase.com/development
