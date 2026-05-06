# Cilium + Hubble

> eBPF-based CNI, network policy, and flow observability for Kubernetes.

| Field | Value |
|-------|-------|
| Category | networking / observability |
| Repo role | addon |
| Install script | scripts/setup/cilium.sh |
| Validate suite | scripts/validate/k8s.sh |
| Compose / config | — (cluster-side install runs from `scripts/start/{k8s,minikube}.sh`) |
| Default port(s) | — (Hubble Relay + UI exposed on demand via `cilium hubble ui`) |
| Default credentials | — |
| Resource footprint | host CLIs ~80 MB (cilium + hubble static Go binaries); in-cluster install adds ~150 MB per node for agent/operator/Hubble pods |

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

## Common pitfalls
- **Setup script installs CLIs only, not cluster components** —
  `scripts/setup/cilium.sh` never touches a cluster, never reads kubeconfig,
  and is safe to run before any Kubernetes runtime exists. The actual
  `cilium install` (which deploys the agent, operator, and Hubble pods)
  is run later by `scripts/start/k8s.sh` or `scripts/start/minikube.sh`.
  Confusing the two leads to "I installed Cilium but pods aren't using it"
  reports.
- **Architecture limited to amd64/arm64** — `uname -m` resolution accepts
  only `x86_64` and `aarch64`; anything else (armv7, riscv64, ppc64le)
  hard-fails the install rather than guessing, because the upstream Cilium
  releases don't ship those targets.
- **`cilium install` needs an active kubeconfig context** — it reads the
  current context from `$KUBECONFIG` / `~/.kube/config` and hits the
  cluster API directly; running it before k3s/minikube is up gives a
  confusing TCP connection error instead of a clear "no cluster" message.
  Run `kubectl config current-context` first.
- **Two CNIs in one cluster is always wrong** — k3s ships flannel and
  minikube ships kindnet by default; both must be disabled at
  cluster-create time (`k3s server --flannel-backend=none` /
  `minikube start --cni=false`) or uninstalled before `cilium install`.
  Two CNIs sharing pod CIDRs causes silent misbehaviour that's brutal to
  debug.
- **Pinned CLI versions drift from cluster Cilium** —
  `CILIUM_CLI_VERSION` and `HUBBLE_CLI_VERSION` are baked into the script;
  bumping the cluster-side Cilium without re-running
  `scripts/setup/cilium.sh --force` leaves CLI/server skew that breaks
  `cilium status` and `hubble observe` in subtle ways.
- **Hubble UI port-forward is on-demand** — `cilium hubble ui` is what
  surfaces the web UI; nothing is exposed by default, so the spec lists
  no default port. The CLI handles the port-forward + browser-open dance
  and tears it down on Ctrl-C.
- **Sha256 verification is mandatory** — each tarball is checked against
  its `.sha256sum` sidecar; a mismatch hard-fails the install rather than
  proceeding with possibly-corrupted binaries. Don't bypass with
  hand-downloads of Cilium releases.

## Related specs
- [k3s](k3s.md), [minikube](minikube.md) — the two cluster runtimes where
  Cilium actually gets installed; `scripts/start/{k8s,minikube}.sh` wire it
  in as the CNI in place of flannel/kindnet, and all subsequent
  `cilium`/`hubble` commands run against whichever of those two is the
  active kubeconfig context.
- [wireshark](wireshark.md) — host-level packet alternative when you want
  raw bytes off an interface rather than Hubble's structured flow events,
  or when you need to see what's happening below the CNI overlay (e.g.
  VXLAN-encapsulated pod traffic on the underlay).
- [observability](observability.md) — Hubble flows are complementary to
  the Prometheus/Grafana stack; metrics-style dashboards live there while
  per-flow drill-down lives in Hubble UI.

## Suggested example progression
- **Beginner** — `examples/beginner/cilium_status.py` — shell out to `cilium status` and parse the agent health summary *(existing)*
- **Intermediate** — `examples/intermediate/cilium_network_policy.py` — apply a `CiliumNetworkPolicy` and assert reachability changes *(existing)*
- **Advanced** — `examples/advanced/cilium_hubble_flows.py` — stream `hubble observe --output json` and aggregate L7 verdicts *(existing)*

## References
- Docs: https://docs.cilium.io/
- Source: https://github.com/cilium/cilium
- Hubble docs: https://docs.cilium.io/en/stable/observability/hubble/
- Cilium CLI source: https://github.com/cilium/cilium-cli
