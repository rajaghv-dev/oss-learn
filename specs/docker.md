# Docker Engine + Compose v2

> Container runtime that powers every service in oss-learn.

| Field | Value |
|-------|-------|
| Category | container runtime |
| Repo role | core |
| Install script | scripts/setup/docker.sh |
| Validate suite | scripts/validate.sh --suite docker |
| Compose / config | — (provides `docker compose`; per-service compose files live under `infra/` and `setup/registry/`) |
| Default port(s) | — (daemon socket at `/var/run/docker.sock`) |
| Default credentials | — |
| Resource footprint | Docker Engine + Compose: ~80 MB host RAM idle, ~250 MB binaries (containerd + buildx + compose-plugin); per-container RAM/disk dominated by the workloads run on top |

## What it is
Docker Engine is the OCI-compatible container runtime; Compose v2 is the
official `docker compose` CLI plugin that runs multi-container apps from a
single YAML file. Together they are the lowest layer of the oss-learn stack:
every other component (Postgres, Grafana, Ollama, Gitea, k3s, the local
registry, …) ships as a container or compose project on top.

## Why it's in oss-learn
Containers give learners a uniform, throwaway way to spin up real services
without polluting their host. Compose v2 lets each component live in its own
declarative YAML so learners can read, edit, and re-launch a service without
shell scripts.

## How this repo wires it up
- `scripts/setup/docker.sh` installs Docker Engine + the Compose v2 plugin
  via the official `download.docker.com` apt or dnf repository, picked from
  `/etc/os-release` (`ID` then `ID_LIKE`, with `UBUNTU_CODENAME` /
  `DEBIAN_CODENAME` preferred over a derivative's `VERSION_CODENAME`).
- Packages installed: `docker-ce`, `docker-ce-cli`, `containerd.io`,
  `docker-buildx-plugin`, `docker-compose-plugin`.
- Adds `$USER` to the `docker` group; daemon is started via `systemd` if
  available, otherwise `service docker start` (or a foreground `dockerd`
  fallback for WSL2 without systemd).
- WSL2 with Docker Desktop integration active is detected and the native
  install is skipped.
- Daemon reachability is probed with three fallbacks: direct `docker info`,
  `sg docker -c 'docker info'` (works before re-login), and `sudo -n docker
  info`. A re-login warning is surfaced when only the fallback succeeds.
- Every other setup step depends on this one — `registry.sh`, `postgres.sh`,
  the observability stack, Gitea, Plane, NocoBase, OpenSearch and k3s all
  call `docker` or `docker compose` directly.

## Key concepts
- **Engine vs CLI** — the daemon (`dockerd`) does the work; the `docker` CLI
  talks to it over `/var/run/docker.sock`.
- **Compose v2 plugin** — `docker compose` (space, not hyphen) replaces the
  legacy `docker-compose` Python tool and is invoked the same way from each
  `infra/*/docker-compose.yml`.
- **docker group** — membership lets a user reach the socket without `sudo`,
  but the current shell only picks it up after `newgrp docker` or re-login.
- **containerd + buildx** — installed alongside the engine so image builds
  (used by `setup/registry/build-and-push.sh`) work out of the box.
- **Distro family resolution** — Docker only publishes packages for
  `ubuntu`, `debian`, `rhel`, `fedora`; derivatives are mapped via `ID_LIKE`
  and the upstream codename, never the derivative's own `VERSION_CODENAME`.
- **WSL2 path** — Docker Desktop's WSL integration exposes the same
  socket inside the distro; the script detects this and skips installing a
  second engine.

## Operational notes
- Logs from the install run go to `logs/docker_setup.log`.
- A successful run emits a structured `log_pass` evidence block listing
  binary path, socket path, daemon verdict, group membership of `$USER`,
  and the compose version (`docker compose version --short`).
- Re-running with `--check` is non-destructive and produces the same
  evidence block without touching apt/dnf.

## Quick verification
```bash
docker run --rm hello-world
```
Pulls the `hello-world` image and prints the "Hello from Docker!" banner if
the daemon is reachable from the current shell.

## Common pitfalls
- **Daemon not reachable from current shell after fresh install** — your
  terminal's effective groups were captured at login and don't yet include
  `docker`; the script's `_docker_info_ok` falls back via `sg docker -c
  'docker info'` but you still need `newgrp docker`, `exec su - $USER`,
  or a new terminal for plain `docker` to work.
- **Distro not in upstream repo (e.g. Ubuntu 26.04 "resolute" or a
  derivative like SuryaOS / Pop!_OS)** — `download.docker.com` only ships
  `ubuntu`/`debian`/`rhel`/`fedora` codenames; set `UBUNTU_CODENAME=noble`
  (or `DEBIAN_CODENAME=bookworm`) in `/etc/os-release`, or override at run
  time with `CODENAME=noble bash scripts/setup/docker.sh`.
- **Derivative's `VERSION_CODENAME` chosen instead of the upstream one** —
  the script deliberately prefers `UBUNTU_CODENAME`/`DEBIAN_CODENAME` over
  `VERSION_CODENAME` because the latter is usually the derivative's own
  marketing name (e.g. `prithvi`, `vanessa`) and is not a valid Docker repo
  path.
- **WSL2 without Docker Desktop and without systemd** — the install path
  falls back to a foreground `dockerd --host=unix:///var/run/docker.sock &`;
  persist it across reboots by enabling systemd in `/etc/wsl.conf`
  (`[boot]\nsystemd=true`) then `wsl --shutdown` from Windows.
- **Daemon installed but not started** — the script tries `systemctl start
  docker` then `service docker start` then a foreground `dockerd`; if all
  three fail, check `journalctl -u docker` (systemd hosts) or
  `/var/log/docker.log`, then re-run `bash scripts/setup/docker.sh --check`.

## Suggested example progression
- **Beginner** — `examples/beginner/docker_hello.py` — run `hello-world` from Python via the Docker SDK *(planned)*
- **Intermediate** — `examples/intermediate/docker_compose_up.py` — bring an `infra/*/docker-compose.yml` up/down programmatically *(planned)*
- **Advanced** — `examples/advanced/docker_buildx_multistage.py` — build and tag a multi-stage image and push it to the local registry *(planned)*

## Related specs
- [postgres.md](postgres.md) — Postgres container is started via
  `docker compose`, depends on this engine being installed first.
- [grafana.md](grafana.md) — Grafana + the observability stack run as
  compose projects on top of this engine.
- [ollama.md](ollama.md) — Ollama runs as a container managed via
  `docker compose`, sharing the same daemon and socket.
- [registry.md](registry.md) — The local registry IS a container started
  via this engine; the registry script even short-circuits if `docker` is
  missing.
- [k3s.md](k3s.md) — k3s talks to its own containerd by default but reuses
  Docker for image-build workflows in oss-learn.
- [minikube.md](minikube.md) — Minikube's `docker` driver hosts the cluster
  nodes inside containers managed by this engine.

## References
- Engine docs: https://docs.docker.com/engine/
- Compose v2 docs: https://docs.docker.com/compose/
- Source (moby): https://github.com/moby/moby
- Official install guide: https://docs.docker.com/engine/install/
- Docker Engine API reference: https://docs.docker.com/reference/api/engine/
