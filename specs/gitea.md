# Gitea

> Lightweight self-hosted Git server that gives oss-learn a local, GitHub-style place to push code and configs without leaving the laptop.

| Field | Value |
|-------|-------|
| Category | source control |
| Repo role | optional |
| Install script | scripts/setup/git.sh |
| Validate suite | `scripts/validate/git.sh` |
| Compose / config | infra/git/docker-compose.yml |
| Default port(s) | 3001 (HTTP), 222 (SSH) |
| Default credentials | set on first visit (first-run wizard creates the admin) |
| Resource footprint | ~150 MB RAM (app + Postgres 16-alpine), ~250 MB images total |

## What it is
Gitea is a Go-based, self-hosted Git service that provides repositories,
pull requests, issues, and a web UI in a single small binary. In oss-learn
it runs from the official `gitea/gitea:1` image backed by a dedicated
`postgres:16-alpine` instance, exposing a familiar GitHub/Gitea-style
workflow on `localhost:3001`. The same server also speaks the Git SSH
protocol on port 222, so both HTTP(S) and SSH remote workflows can be
exercised against a single local host. Because Gitea ships everything in
one process, the install footprint is tiny compared to other forge
options, which keeps the rest of the laptop free for the heavier Plane
and observability stacks.

## Why it's in oss-learn
It gives the curriculum a local target for git push/clone, webhooks, and
API calls without depending on github.com. Learners can practise Git
workflows, mirror repos, and wire CI-style automations entirely offline,
and the API is small enough to script from Python or curl in a few lines.
It also pairs naturally with the Plane and NocoBase examples — webhooks
from Gitea can drive issue updates or low-code workflows on the same host.

## How this repo wires it up
- Docker-only install: `infra/git/docker-compose.yml` brings up two containers, `oss-gitea` and `oss-gitea-db`.
- Image: `gitea/gitea:1` for the app, `postgres:16-alpine` for the database.
- Database creds are baked in (`gitea` / `gitea_secret`, DB `gitea`) and reach the app via `GITEA__database__*` env vars.
- HTTP port `3000` inside the container is published as `3001` on the host so the standard Grafana port (3000) stays free; SSH is published as `222`.
- `GITEA__server__ROOT_URL` is set to `http://localhost:3001/` so generated clone URLs match the published port.
- `GITEA__service__DISABLE_REGISTRATION` is left at `false` so additional users can self-register from the login page during the curriculum.
- `USER_UID=1000` / `USER_GID=1000` align the in-container `git` user with the typical host user so bind-mounted data has predictable ownership.
- Persistent state lives under `infra/git/data/gitea` (app data) and `infra/git/data/pgdata` (Postgres data) via host bind mounts.
- The `gitea` service `depends_on` `gitea-db` with `condition: service_healthy` and ships its own healthcheck on `GET /`; the DB uses `pg_isready -U gitea` as its check.
- `scripts/setup/git.sh` supports `--check` (status only), `--force` (down -v --remove-orphans + rebuild), and writes `setup/state/installs/git.yaml` on success.
- It waits up to 120 s on `GET /` (24 attempts × 5 s) to absorb the first-run DB migration before declaring success.
- The script also re-execs itself under `docker_reexec_if_needed` so it works the same whether invoked from a host shell or inside another script.
- The success log records `container=oss-gitea, image=gitea/gitea:1, web=http://localhost:3001, ssh_port=222, compose=infra/git/docker-compose.yml, data_dir=infra/git/data`, which is what the manifest stores for later inspection.
- `scripts/validate/git.sh` checks both containers, the web URL `/`, and the API `/api/v1/version`; it returns exit code 2 if Docker is absent so the suite can be skipped cleanly.
- The validate suite is also reachable via `bash validate.sh --suite git` from the repo root, alongside the other per-suite checks.

## Key concepts
- **First-run wizard** — On the very first visit to `http://localhost:3001` Gitea asks you to create the admin account; there are no hard-coded admin credentials in the compose file.
- **Repositories** — Standard Git repos with HTTP(S) and SSH remotes; SSH uses `ssh://git@localhost:222/<user>/<repo>.git`, HTTP uses `http://localhost:3001/<user>/<repo>.git`.
- **Organizations and teams** — Group repos and assign team-based access, mirroring the GitHub model on a single host.
- **API v1** — REST API rooted at `/api/v1/` (e.g. `/api/v1/version`, `/api/v1/repos`, `/api/v1/users`) used by the validate suite and any automation scripts.
- **Webhooks** — Per-repo HTTP callbacks on push/PR events, useful for triggering local CI or Plane/NocoBase integrations on the same host.
- **GITEA__... env vars** — Any field of `app.ini` can be overridden by an env var named `GITEA__<section>__<key>`, which is how the compose file points the app at Postgres and pins the public URL.
- **Tokens and SSH keys** — Personal access tokens (created in Settings → Applications) authenticate API calls; SSH keys uploaded to the same screen authenticate clones over port 222.
- **Bind-mounted /data** — Everything stateful (repos, attachments, LFS objects, app.ini) lives under `/data` inside the container and on the host under `infra/git/data/gitea`, so backups are a directory copy.
- **Postgres backing store** — `oss-gitea-db` is a dedicated Postgres 16 instance separate from the main `oss-postgres`, so Gitea can be wiped with `--force` without touching curriculum data.
- **Healthcheck-gated startup** — `gitea` does not start until `gitea-db` reports healthy via `pg_isready`, eliminating the "DB not ready" first-boot crash on slower laptops.
- **Mirroring** — Gitea can pull a remote git repo on a schedule, useful for caching upstream OSS projects locally as part of an offline workflow.

## Quick verification
```bash
curl -s http://localhost:3001/api/v1/version
```
Returns a small JSON like `{"version":"1.x.y"}` once Gitea has finished its first-run migration; a connection error means the container has not yet completed schema setup.

## Common pitfalls
- **First-boot wizard required** — no admin is baked into the compose file; the very first visit to `http://localhost:3001` must complete the wizard, otherwise API calls that need auth will fail with 401.
- **120 s readiness window covers DB migration** — `scripts/setup/git.sh` polls `GET /` for up to 120 s (24 × 5 s) so the first-run schema install can finish; bailing earlier and curl-ing the URL will look like a hung container.
- **SSH lives on port 222, not 22** — clone URLs must use `ssh://git@localhost:222/<user>/<repo>.git`; the host's own sshd still owns port 22 and will reject git commands.
- **Bind-mount UID/GID must match the host user** — `USER_UID=1000` / `USER_GID=1000` in the compose file align the in-container `git` user with the typical host user; if your host UID differs, files under `infra/git/data/gitea` will be owned by the wrong user and Gitea will fail to write to its data dir.
- **`--force` deletes the volume** — `down -v --remove-orphans` wipes both the app data and the dedicated Postgres, so any repos created during exploration are lost on rebuild.

## Suggested example progression
- **Beginner** — `examples/beginner/gitea_hello.py` — hit `/api/v1/version` and print the running Gitea version *(planned)*
- **Intermediate** — `examples/intermediate/gitea_repo_crud.py` — create a repo via the API, push a commit, and list issues *(planned)*
- **Advanced** — `examples/advanced/gitea_webhook_demo.py` — register a webhook and react to push events from a local listener *(planned)*

## Related specs
- [plane.md](plane.md) — wire Gitea webhooks (push, PR) into Plane issues to mirror a GitHub-Issues-style flow.
- [nocobase.md](nocobase.md) — trigger NocoBase low-code workflows from Gitea webhooks for "on push, do X" automations.

## References
- Docs: https://docs.gitea.com/
- Source: https://github.com/go-gitea/gitea
- API reference: https://docs.gitea.com/api/1.20/
- Config cheat sheet: https://docs.gitea.com/administration/config-cheat-sheet
