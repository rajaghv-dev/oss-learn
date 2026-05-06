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
| Resource footprint | ~1.5 GB RAM (Docker driver: extra container), ~1.2 GB image (kicbase), ~6 GB disk default |

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

## Common pitfalls
- **Docker must be up first** — the Docker driver requires a running Docker
  daemon; the setup script fails fast on a `docker info` probe and points
  the user at `scripts/setup/docker.sh`. minikube cannot bootstrap its own
  runtime, and switching driver mid-stream means deleting the profile.
- **Profile dir grows unboundedly** — `~/.minikube/` accumulates cached
  images, ISOs, profile data and retired clusters over time. Periodically
  run `minikube delete --all --purge` to reclaim several GB; `minikube
  stop` alone leaves all of it on disk.
- **CNI is locked in at create time** — minikube's default CNI is kindnet.
  Cilium (or any other CNI) must be requested at create time via
  `minikube start --cni=cilium`; swapping CNIs on a running cluster is not
  supported and almost always means `minikube delete` followed by a fresh
  `minikube start` with the right flag.
- **LoadBalancer needs `minikube tunnel`** — `Service` type `LoadBalancer`
  stays in `<pending>` until you run `minikube tunnel` in a separate
  terminal; the tunnel binds the host network so the assigned IP becomes
  reachable from outside the Docker container.
- **Host kernel quirks leak in** — the Docker driver shares the host kernel,
  so cgroups/AppArmor/SELinux quirks of the host and sysctls like
  `vm.max_map_count` (needed for Elasticsearch and similar workloads)
  surface inside the cluster. These cannot be tuned via `minikube config`
  and must be fixed on the host.

## Related specs
- `specs/k3s.md` — Linux/WSL2-native alternative with a much smaller
  footprint and no separate driver layer. Preferred when the host is Linux
  or WSL2 and the upstream-exact Kubernetes binary is not required; the
  same `kubectl`, Helm and validate suite work against either cluster, so
  the choice is mostly about resource budget and host platform.
- `specs/cilium.md` — opt-in CNI for minikube. Pass `--cni=cilium` to
  `minikube start` to install it at create time; hot-swapping the CNI on a
  running minikube cluster is not supported, so getting Cilium in place
  before any pods exist is the only reliable path. Cilium also enables
  NetworkPolicy and Hubble observability that the default kindnet does not.
- `specs/docker.md` — hard prerequisite. The `docker` driver runs the
  entire control plane inside a privileged container on the host's Docker
  daemon and pulls the multi-hundred-megabyte `kicbase` image to do so;
  without a working Docker daemon the setup script aborts before
  installing any binaries.

## Suggested example progression
- **Beginner** — `examples/beginner/minikube_status.py` — call `minikube status` via subprocess and parse the JSON output *(existing)*
- **Intermediate** — `examples/intermediate/minikube_deploy_app.py` — apply a Deployment and expose it with `minikube service` *(existing)*
- **Advanced** — `examples/advanced/minikube_multinode_helm.py` — start a multi-node profile and install a Helm chart across it *(existing)*

## References
- Docs: https://minikube.sigs.k8s.io/docs/
- Source: https://github.com/kubernetes/minikube
- Helm docs: https://helm.sh/docs/
- kubectl cheat sheet: https://kubernetes.io/docs/reference/kubectl/cheatsheet/
- Kubernetes basics tutorial: https://kubernetes.io/docs/tutorials/kubernetes-basics/
- minikube driver reference: https://minikube.sigs.k8s.io/docs/drivers/docker/
- minikube addons list: https://minikube.sigs.k8s.io/docs/handbook/addons/
- minikube networking (`minikube tunnel`): https://minikube.sigs.k8s.io/docs/handbook/accessing/
- kicbase image source: https://github.com/kubernetes/minikube/tree/master/deploy/kicbase
- minikube profiles handbook: https://minikube.sigs.k8s.io/docs/handbook/config/
