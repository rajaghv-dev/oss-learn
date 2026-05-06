# k3s

> Single-binary lightweight Kubernetes for Linux and WSL2.

| Field | Value |
|-------|-------|
| Category | kubernetes / runtime |
| Repo role | optional |
| Install script | scripts/setup/k8s.sh |
| Validate suite | scripts/validate/k8s.sh |
| Compose / config | — (kubeconfig at `~/.kube/config`, server config at `/etc/rancher/k3s/k3s.yaml`) |
| Default port(s) | 6443 (kube-apiserver) |
| Default credentials | — (kubeconfig token written by installer) |

## What it is
k3s is a CNCF-certified Kubernetes distribution packaged as a single ~50 MB
binary. It bundles the API server, scheduler, controller-manager, kubelet,
containerd and a SQLite datastore into one process, which makes it a fast,
low-memory way to get a real Kubernetes cluster on a laptop or VM.

## Why it's in oss-learn
Learners get a working k8s control plane without nested virtualisation,
heavyweight installers, or a separate VM. On Linux it runs as a systemd
service; on WSL2 it runs as a background process with a native snapshotter so
the cluster behaves the same as on bare metal.

## How this repo wires it up
- `scripts/setup/k8s.sh` detects WSL2 vs plain Linux via `is_wsl2` /
  `has_systemd` from `scripts/common.sh` and refuses to run on non-Linux
  hosts (macOS users go through `minikube.sh` instead).
- Installs k3s via the official `curl -sfL https://get.k3s.io | sh -`
  pipeline with `INSTALL_K3S_EXEC` set to a curated flag set:
  `--flannel-backend=none --disable-network-policy --disable=traefik
  --write-kubeconfig-mode=644`, plus `--snapshotter=native` on WSL2 because
  the WSL2 kernel does not expose overlayfs.
- Flannel and the built-in NetworkPolicy controller are disabled so Cilium
  can later be installed as the CNI; Traefik is disabled to leave ingress
  choice open (the repo standardises on ingress-nginx).
- On hosts with systemd the service is enabled and started; on WSL2 without
  systemd the script launches `sudo k3s server --snapshotter=native
  --write-kubeconfig-mode=644 &` and logs to `/tmp/k3s-server.log`.
- Copies `/etc/rancher/k3s/k3s.yaml` to `~/.kube/config`, chowns it to the
  invoking user, then waits up to 60 s for at least one node to report
  `Ready` before exiting.
- Installs Helm via `get-helm-3` and creates a `/usr/local/bin/kubectl`
  symlink (or shim) to `k3s kubectl` if no standalone `kubectl` is on PATH.
- `scripts/validate/k8s.sh` re-checks the binary, picks `kubectl` or
  `k3s kubectl`, verifies the kubeconfig is present and at least one node is
  Ready, and (if the namespace exists) reports `Running/Total` pod counts in
  the `oss-learn` namespace.
- `--force` reinstalls k3s end-to-end; `--check` reports the installed
  version and exits without touching the system.

## Key concepts
- **Single-binary control plane** — apiserver, scheduler, controller-manager,
  kubelet and containerd all run inside the `k3s` process.
- **Embedded datastore** — SQLite by default (etcd or external SQL are opt-in)
  keeps the install footprint small for a single-node learning cluster.
- **Snapshotter** — containerd's storage backend; `overlayfs` is the default
  on Linux but unavailable in the WSL2 kernel, so `native` is forced there.
- **Disabled defaults** — flannel, the built-in NetworkPolicy controller and
  Traefik are switched off to keep CNI and ingress choices open.
- **kubeconfig modes** — `--write-kubeconfig-mode=644` lets non-root users
  read `/etc/rancher/k3s/k3s.yaml` so the install script can copy it into
  `~/.kube/config` without a second sudo.

## Quick verification
```bash
kubectl get nodes
```
Should list one node in `Ready` status running the k3s-bundled kubelet.

## Suggested example progression
- **Beginner** — `examples/beginner/k3s_get_nodes.py` — list cluster nodes via the Python kubernetes client *(planned)*
- **Intermediate** — `examples/intermediate/k3s_deploy_nginx.py` — apply a Deployment + Service and port-forward to it *(planned)*
- **Advanced** — `examples/advanced/k3s_helm_chart.py` — install a Helm chart programmatically and watch rollout status *(planned)*

## References
- Docs: https://docs.k3s.io/
- Source: https://github.com/k3s-io/k3s
