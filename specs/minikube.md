# minikube

> Cross-platform local Kubernetes cluster running inside a Docker container.

| Field | Value |
|-------|-------|
| Category | kubernetes / runtime |
| Repo role | optional |
| Install script | scripts/setup/minikube.sh |
| Validate suite | scripts/validate/k8s.sh |
| Compose / config | — (kubeconfig at `~/.kube/config`, profile dir at `~/.minikube/`) |
| Default port(s) | 8443 (kube-apiserver inside the minikube container) |
| Default credentials | — (kubeconfig client cert generated per profile) |

## What it is
minikube is the upstream Kubernetes project's reference tool for running a
local single- or multi-node cluster. It supports several drivers (docker,
hyperkit, kvm2, virtualbox, …); oss-learn standardises on the `docker`
driver, which launches a single privileged container that hosts the entire
control plane and kubelet.

## Why it's in oss-learn
k3s only runs on Linux and WSL2, so macOS users — and anyone who wants the
exact upstream Kubernetes binaries instead of a distro — need a portable
alternative. minikube + the Docker driver runs identically on Linux, macOS
and WSL2 as long as Docker is available, and matches the Kubernetes versions
shipped by the project upstream.

## How this repo wires it up
- `scripts/setup/minikube.sh` is setup-only: it installs three binaries and
  exits without touching the cluster. Starting the cluster is the job of
  `scripts/start/minikube.sh` (invoked by `bash start.sh --minikube`).
- Hard-requires Docker — refuses to run if `docker info` fails and points the
  user at `scripts/setup/docker.sh`. The `docker` driver is the only driver
  this repo configures.
- Downloads the latest `minikube-linux-amd64` binary from
  `storage.googleapis.com/minikube/releases/latest` and installs it to
  `/usr/local/bin/minikube` via `sudo install`.
- Installs a matching standalone `kubectl` from `dl.k8s.io` using the version
  in `https://dl.k8s.io/release/stable.txt`, owned `root:root` mode `0755`.
- Installs Helm via the official `get-helm-3` script; this is the same Helm
  used by the k3s path so charts (KEDA, NATS, etc.) are reusable.
- `--check` reports installed versions for all three tools and exits without
  modifying anything; `--force` reinstalls every tool.
- Validation runs through `scripts/validate/k8s.sh`, which is shared with
  k3s — it accepts either `kubectl` (preferred) or `k3s kubectl`, walks the
  kubeconfig, and confirms at least one Ready node.

## Key concepts
- **Driver** — the isolation layer minikube uses to host the cluster; the
  `docker` driver runs the kubelet inside a single Docker container, so no
  hypervisor is required.
- **Profile** — a named cluster + kubeconfig context stored under
  `~/.minikube/profiles/<name>/`; the default profile is just `minikube`.
- **kubectl context** — `minikube start` writes a `minikube` context into
  `~/.kube/config` and switches to it, so `kubectl get nodes` works
  immediately after the cluster comes up.
- **Addons** — opt-in components (`ingress`, `metrics-server`, `registry`, …)
  toggled with `minikube addons enable <name>`; this repo installs Helm so
  charts can be used in place of most addons.
- **Setup vs start split** — `scripts/setup/minikube.sh` only places
  binaries; `scripts/start/minikube.sh` is what actually calls
  `minikube start --driver=docker` and brings the cluster up.
- **Shared Helm + kubectl** — the same `kubectl` and `helm` binaries are
  used regardless of whether the active cluster is k3s or minikube.

## Quick verification
```bash
minikube version && kubectl version --client
```
Prints both client versions; a non-zero exit means the install script did
not complete successfully.

## Suggested example progression
- **Beginner** — `examples/beginner/minikube_status.py` — call `minikube status` via subprocess and parse the JSON output *(planned)*
- **Intermediate** — `examples/intermediate/minikube_deploy_app.py` — apply a Deployment and expose it with `minikube service` *(planned)*
- **Advanced** — `examples/advanced/minikube_multinode_helm.py` — start a multi-node profile and install a Helm chart across it *(planned)*

## References
- Docs: https://minikube.sigs.k8s.io/docs/
- Source: https://github.com/kubernetes/minikube
