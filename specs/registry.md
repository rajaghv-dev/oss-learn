# Local Docker Registry

> Private image registry at localhost:5000 that holds every oss-learn service image.

| Field | Value |
|-------|-------|
| Category | container image registry |
| Repo role | core |
| Install script | scripts/setup/registry.sh |
| Validate suite | scripts/setup/registry.sh --check |
| Compose / config | setup/registry/docker-compose.yml |
| Default port(s) | 5000 (HTTP, plain) |
| Default credentials | — (unauthenticated, localhost-only) |
| Resource footprint | registry container: ~20 MB RAM idle, ~30 MB image; on-disk store under `setup/registry/data` grows with every push (the 12 oss-learn images push roughly 2–4 GB total once all services have been built) |

## What it is
A single container running the official `registry:2` image, exposing the
Docker Registry HTTP API v2 at `http://localhost:5000`. It is a private,
on-host image store used by oss-learn to hold the 12 service images built
from the repo, so subsequent `docker compose up` runs pull from a stable
local source instead of rebuilding or hitting Docker Hub.

## Why it's in oss-learn
Learners get to see the full image lifecycle — build, tag, push, pull, list
catalog — against a real registry without any cloud account. It also makes
component startups deterministic and fast, since images are cached on disk
once and reused by every `start.sh` invocation.

## How this repo wires it up
- `scripts/setup/registry.sh` brings up `setup/registry/docker-compose.yml`
  as the container `oss-registry`, polls `GET /v2/` for up to 30 s, then
  invokes `setup/registry/build-and-push.sh` to build and push all 12
  oss-learn service images as `localhost:5000/oss/<service>:latest`.
- Image: `registry:2` (official Docker Hub image, no local Dockerfile).
- Persistent storage lives at `setup/registry/data` on the host.
- Depends on `scripts/setup/docker.sh` having completed — the script
  short-circuits with a warning if `docker` is not on `PATH`.
- The script re-execs itself under `sg docker` if the daemon is only
  reachable that way (newly-created group membership).
- `--force` tears down and recreates the container; `--check` reports
  container state, API reachability, and current `_catalog` contents.
- A manifest is written to `setup/state/installs/registry.yaml` recording
  the container name, image, endpoint, compose path, build script, and
  data directory.

## Key concepts
- **Registry HTTP API v2** — `/v2/` is the liveness probe; `/v2/_catalog`
  lists repositories; `/v2/<name>/tags/list` lists tags per image.
- **Image reference** — `localhost:5000/oss/<service>:latest` — Docker
  treats `localhost:5000` as an insecure-but-allowed registry by default,
  so no TLS or auth config is needed for local use.
- **Push vs pull** — `docker push` uploads layers the registry doesn't yet
  have; `docker pull` is the inverse. Layers are content-addressed, so
  rebuilds with unchanged base layers are nearly free.
- **Storage driver** — `registry:2` defaults to filesystem storage under
  `/var/lib/registry` inside the container, bind-mounted from
  `setup/registry/data` so images survive `docker compose down`.
- **Production alternatives** — Harbor, GitLab Container Registry, ECR/GCR/ACR
  add auth, scanning, replication, and TLS that this learning registry
  intentionally omits.

## Operational notes
- Logs go to `logs/registry.log`; container logs are reachable via
  `docker logs oss-registry`.
- Readiness gate: `curl -sf http://localhost:5000/v2/` polled once per
  second up to 30 attempts before `build-and-push.sh` is invoked.
- `--check` reports container state, API reachability, the live `_catalog`
  response, the compose path, and the manifest path — no changes made.
- `--force` runs `docker compose down -v` plus `docker rm -f oss-registry`
  before rebuilding, wiping the data volume.

## Quick verification
```bash
curl -sf http://localhost:5000/v2/_catalog
```
Returns JSON like `{"repositories":["oss/postgres","oss/grafana", ...]}`
once `build-and-push.sh` has populated the registry.

## Common pitfalls
- **`docker` not on PATH** — the script logs
  `Docker not found — skipping registry` and exits 0; run
  `bash scripts/setup/docker.sh` first so the daemon and CLI exist before
  retrying.
- **Daemon reachable only via `sg docker`** — fresh installs leave the
  current shell without the `docker` group; the script self-re-execs under
  `sg docker` via `docker_reexec_if_needed`, but if that helper isn't
  available, run `newgrp docker` (or open a new terminal) and re-run.
- **Registry API doesn't come up within 30 s** —
  `curl -sf http://localhost:5000/v2/` is polled for 30 attempts; if it
  never responds the script aborts with
  `Registry did not become ready after 30 s`. Inspect with
  `docker logs oss-registry`, check that nothing else is bound to port 5000
  (`ss -ltnp | grep :5000`), and re-run with `--force`.
- **`build-and-push.sh` fails on one image** — the script exits 1 the
  moment any image fails to build or push; fix the offending Dockerfile
  under `setup/<service>/`, then re-run `bash scripts/setup/registry.sh`
  (the registry container itself is left running, so only the build step
  repeats).
- **Stale image cache after a rebuild** — `--force` runs
  `docker compose down -v` plus `docker rm -f oss-registry`, wiping the
  bind-mounted store under `setup/registry/data`; if you only want to
  repush one image, skip `--force` and call
  `setup/registry/build-and-push.sh` directly.

## Suggested example progression
- **Beginner** — `examples/beginner/registry_catalog.py` — list repositories via the v2 API with `requests` *(planned)*
- **Intermediate** — `examples/intermediate/registry_push_image.py` — build a small image, tag it `localhost:5000/demo/app:1`, push, then re-pull *(planned)*
- **Advanced** — `examples/advanced/registry_gc_inspect.py` — walk the storage tree, inspect manifests/blobs, and report layer reuse across tags *(planned)*

## Related specs
- [docker.md](docker.md) — Hard prerequisite: this registry runs as a
  container on Docker Engine, and the setup script short-circuits if the
  `docker` CLI is missing.
- [postgres.md](postgres.md) — Image consumer: built and pushed by
  `setup/registry/build-and-push.sh` as `localhost:5000/oss/postgres:latest`,
  then pulled by `start.sh`.
- [grafana.md](grafana.md) — Image consumer: same build-and-push pipeline;
  the observability stack pulls `localhost:5000/oss/grafana:latest`
  instead of going to Docker Hub on every start.
- [ollama.md](ollama.md) — Image consumer: the Ollama service image is
  tagged `localhost:5000/oss/ollama:latest` so model-server containers
  start from a cached local image rather than re-pulling from Docker Hub
  on every `start.sh` invocation.

## References
- Distribution (registry) docs: https://distribution.github.io/distribution/
- Source: https://github.com/distribution/distribution
- Docker Hub image: https://hub.docker.com/_/registry
- Registry HTTP API v2 spec: https://distribution.github.io/distribution/spec/api/
- Configuration reference (`registry:2`): https://distribution.github.io/distribution/about/configuration/
