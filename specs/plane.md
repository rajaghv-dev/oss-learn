# Plane

> Self-hosted, open-source project management stack (Jira/Linear alternative) that gives oss-learn a multi-service app to drive issues, cycles, and modules locally.

| Field | Value |
|-------|-------|
| Category | Project management |
| Repo role | optional |
| Install script | scripts/setup/plane.sh |
| Validate suite | scripts/validate/plane.sh |
| Compose / config | infra/plane/docker-compose.yml |
| Default port(s) | 4000 (proxy / web entrypoint) |
| Default credentials | admin@oss-learn.local / admin1234 |

## What it is
Plane is an open-source project management platform with workspaces,
projects, issues, cycles, and modules, served through a Caddy-based
reverse proxy in front of a Django API, a Next.js frontend, a Next.js
public space, Celery workers, Redis, MinIO, and Postgres. In oss-learn
it runs as a nine-container stack from `makeplane/plane-*:stable` images,
exposed on `http://localhost:4000`. The proxy handles path-based routing
so `/api/*`, `/spaces/*`, and `/uploads/*` all flow through a single port,
and the published URL is the one the API and frontend are configured to
trust for CORS and link generation.

## Why it's in oss-learn
It is the curriculum's example of a realistic, multi-service web
application: API + worker + beat + frontend + proxy + object store +
cache + DB, all wired together with health checks and migrations.
Learners can poke at the API, watch Celery jobs run, inspect the proxy
config that fronts everything on a single port, and see how a Django
service is shaped for production rather than a single-process toy app.

## How this repo wires it up
- Docker-only install: `infra/plane/docker-compose.yml` defines nine services — `plane-db` (postgres:15), `plane-redis`, `plane-minio`, `plane-api`, `plane-worker`, `plane-beat`, `plane-web`, `plane-space`, `plane-proxy`.
- The proxy container (`makeplane/plane-proxy:stable`) ships a Caddyfile that expects bare hostnames `api`, `web`, `space`; the compose file adds those as network aliases on the matching containers so reverse proxying works.
- `SITE_ADDRESS=:80`, `BUCKET_NAME=uploads`, and `FILE_SIZE_LIMIT=5MB` are set on the proxy because the baked-in Caddyfile substitutes them — leaving them empty produces an unkeyed global block and a crash loop.
- API env: `DATABASE_URL` to `oss-plane-db`, `REDIS_URL` to `oss-plane-redis`, `AWS_S3_ENDPOINT_URL` to `oss-plane-minio` with bucket `uploads`, plus `DEFAULT_EMAIL=admin@oss-learn.local` / `DEFAULT_PASSWORD=admin1234` to seed the admin account.
- `WEB_URL` and `CORS_ALLOWED_ORIGINS` are pinned to `http://localhost:4000` so cross-origin checks match the published port.
- Worker and beat reuse the same backend image but run `docker-entrypoint-worker.sh` and `docker-entrypoint-beat.sh`, sharing DB/Redis/MinIO env with the API.
- Frontend (`plane-web`) and public space (`plane-space`) read `NEXT_PUBLIC_API_BASE_URL=http://localhost:4000` so browser-side calls go back through the proxy rather than the internal hostnames.
- MinIO is started with `server /export --console-address ":9090"` and seeded credentials `plane` / `plane_minio_secret`; the API reaches it via `http://oss-plane-minio:9000` on the compose network.
- `plane-db` runs `postgres:15-alpine` with creds `plane` / `plane_secret` (DB `plane`) and is the only Postgres on this stack — separate from the main oss-learn `oss-postgres`.
- Persistent data lives under `infra/plane/data/pgdata` (Postgres) and `infra/plane/data/minio` (uploads) via host bind mounts.
- `scripts/setup/plane.sh` polls `GET /` for up to 600 s, logs container health every 30 s, and distinguishes a proxy crash-loop (config error) from "still warming" (all containers up, just slow first boot).
- The setup script tears down with `down -v --remove-orphans` plus a 3 s settle on `--force` to avoid the stale-container race that breaks `depends_on: condition: service_healthy`.
- The script considers three failure modes after the 600 s window: (a) proxy crash-loop (config error, hard fail), (b) all containers up but URL still 4xx/5xx (warn "still warming"), (c) some containers missing (genuine breakage, hard fail).
- The success manifest records `compose=infra/plane/docker-compose.yml, container=oss-plane-proxy, web_url=http://localhost:4000, data_dir=infra/plane/data` for later inspection.
- `scripts/validate/plane.sh` checks `oss-plane-proxy`, `oss-plane-api`, `oss-plane-db` and probes `/` plus `/api/`.
- The same validate suite runs via `bash validate.sh --suite plane` from the repo root.

## Key concepts
- **Proxy / Caddy front door** — `oss-plane-proxy` terminates :80 inside the container (published as host :4000) and routes paths to api/web/space/minio so the whole stack sits behind a single URL.
- **Workspace, project, issue** — The core hierarchy: a workspace contains projects; projects contain issues organised into cycles and modules.
- **Cycles and modules** — Cycles are time-boxed sprints; modules group issues by feature area, both layered on top of the same issue list.
- **Workers and beat** — `plane-worker` runs Celery jobs (notifications, indexing, exports); `plane-beat` schedules periodic tasks via Celery Beat.
- **MinIO uploads** — File attachments and exports go to the `uploads` bucket on the embedded MinIO instance, kept inside the stack rather than the public internet.
- **First-boot warmup** — DB migrations, MinIO bucket creation, and Next.js asset compilation routinely take 4–8 minutes on a cold cache, which is why setup waits 600 s and validate explicitly notes that re-checks may be needed.
- **Network aliases** — The Caddyfile baked into the proxy refers to `api`, `web`, and `space` rather than `oss-plane-*`, so each service registers a matching network alias to keep the upstream config working.
- **Default seeded admin** — `admin@oss-learn.local` / `admin1234` is created from `DEFAULT_EMAIL` / `DEFAULT_PASSWORD` on the API container; rotate these env vars before exposing the stack outside the laptop.
- **Per-service Postgres** — Plane runs its own `postgres:15-alpine` separate from the main `oss-postgres:16` and from Gitea/NocoBase, so each service can be wiped independently.
- **Bind-mounted volumes** — `infra/plane/data/pgdata` and `infra/plane/data/minio` keep state on the host so a `down -v` only drops the named volumes, not the on-disk data.
- **Healthcheck-gated startup** — `plane-api` waits for `plane-db` and `plane-redis` to be healthy; `plane-proxy`, `plane-web`, `plane-space` wait for `plane-api` to start, which keeps the dependency graph deterministic.

## Quick verification
```bash
curl -sI http://localhost:4000/ | head -n1
```
Returns `HTTP/1.1 200 OK` (or a 3xx redirect to the workspace UI) once all nine containers are healthy and Caddy is serving; on a cold start it can take several minutes for the first 200 to appear.

## Suggested example progression
- **Beginner** — `examples/beginner/plane_hello.py` — log in via the API and print the current user / workspace list *(planned)*
- **Intermediate** — `examples/intermediate/plane_issue_crud.py` — create a project, add issues, move them through cycles and states *(planned)*
- **Advanced** — `examples/advanced/plane_automation.py` — drive a full sprint workflow (cycle creation, bulk import, status updates) end-to-end via the REST API *(planned)*

## References
- Docs: https://docs.plane.so/
- Source: https://github.com/makeplane/plane
- API reference: https://developers.plane.so/api-reference/introduction
- Self-host guide: https://developers.plane.so/self-hosting/overview
