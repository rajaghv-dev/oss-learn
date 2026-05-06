# Cilium + Hubble

> eBPF-based CNI, network policy, and flow observability for Kubernetes.

| Field | Value |
|-------|-------|
| Category | networking / observability |
| Repo role | addon |
| Install script | scripts/setup/cilium.sh |
| Validate suite | scripts/validate.sh --suite k8s |
| Compose / config | — (cluster-side install runs from `scripts/start/{k8s,minikube}.sh`) |
| Default port(s) | — (Hubble Relay + UI exposed on demand via `cilium hubble ui`) |
| Default credentials | — |

## What it is
Cilium is a Kubernetes CNI plugin that uses eBPF in the kernel to implement
pod networking, L3–L7 network policy, and load balancing without iptables.
Hubble is its observability layer — it streams structured flow events
(connect, drop, DNS, HTTP) out of the same eBPF programs.

## Why it's in oss-learn
It replaces the default flannel/kindnet CNI in the bundled k3s and minikube
clusters with something learners can actually inspect, giving a reproducible
target for exercises on network policy, service mesh basics, and L7 flow
observability without standing up a separate APM stack.

## How this repo wires it up
- `scripts/setup/cilium.sh` only installs the **host-side CLIs**, not the
  cluster components — `cilium` (drives `cilium install`, `status`,
  `connectivity test`) and `hubble` (queries the observability layer for
  flows, drops, DNS verdicts, TLS info).
- Versions are pinned (`CILIUM_CLI_VERSION=v0.16.18`,
  `HUBBLE_CLI_VERSION=v1.16.5`) and overridable via env vars before invoking
  the script; architecture is resolved from `uname -m`
  (`x86_64` → `amd64`, `aarch64` → `arm64`; anything else hard-fails).
- Each tarball is fetched from GitHub releases over HTTPS with `curl -fsSL
  --retry 3`, verified against its `.sha256sum` sidecar, and extracted to
  `/usr/local/bin` with `sudo tar`. The downloaded artefacts are cleaned up
  after extraction to keep `/tmp` tidy on re-runs.
- Cluster-side install (`cilium install` against the live kubeconfig context)
  is deferred to `scripts/start/k8s.sh` and `scripts/start/minikube.sh` —
  this setup script never touches a cluster, never reads kubeconfig, and is
  safe to run before any Kubernetes runtime exists.
- WSL2 is detected via `is_wsl2` from `scripts/common.sh` and logged, but the
  install path is identical to native Linux because both CLIs are static Go
  binaries with no platform-specific deps.
- `--check` reports CLI presence + versions without installing; `--force`
  re-downloads and overwrites both binaries (useful when bumping the pinned
  versions); a missing CLI on a non-`--force` run still triggers an install.

## Key concepts
- **eBPF datapath** — packet processing runs as kernel-verified bytecode
  attached to tc/XDP hooks, replacing iptables for pod-to-pod traffic.
- **CiliumNetworkPolicy (CNP)** — a CRD that extends standard Kubernetes
  `NetworkPolicy` with L7 (HTTP path/method, gRPC, Kafka) rules.
- **Identity-based security** — endpoints are labelled and policy is
  evaluated against identities, not IPs, so churn doesn't reopen holes.
- **Hubble Relay** — cluster-wide aggregator that merges per-node Hubble
  feeds; the `hubble` CLI and `hubble ui` both talk to it.
- **CLI vs cluster components** — `scripts/setup/cilium.sh` installs only
  the two host CLIs; the agent + operator + Hubble pods are deployed later
  by `cilium install` against the active kubeconfig context.
- **Replacing the default CNI** — k3s ships flannel and minikube ships
  kindnet by default; both are uninstalled (or disabled at cluster-create
  time) before `cilium install` runs, since two CNIs in one cluster is
  always a bad time.

## Quick verification
```bash
cilium version --client && hubble version
```
Prints the client versions of both CLIs, confirming the binaries are on
`PATH` and executable — no cluster connection required.

## Suggested example progression
- **Beginner** — `examples/beginner/cilium_status.py` — shell out to `cilium status` and parse the agent health summary *(planned)*
- **Intermediate** — `examples/intermediate/cilium_network_policy.py` — apply a `CiliumNetworkPolicy` and assert reachability changes *(planned)*
- **Advanced** — `examples/advanced/cilium_hubble_flows.py` — stream `hubble observe --output json` and aggregate L7 verdicts *(planned)*

## References
- Docs: https://docs.cilium.io/
- Source: https://github.com/cilium/cilium
