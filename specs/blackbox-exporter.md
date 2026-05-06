# Blackbox Exporter

> External-probe Prometheus exporter that turns HTTP/TCP/ICMP checks into scrapeable metrics.

| Field | Value |
|-------|-------|
| Category | observability / synthetic monitoring |
| Repo role | core |
| Install script | scripts/setup/observability.sh |
| Validate suite | scripts/validate/observability.sh |
| Compose / config | infra/observability/docker-compose.yml, infra/observability/blackbox.yml |
| Default port(s) | 9115 (HTTP — `/probe`, `/metrics`, `/-/healthy`) |
| Default credentials | — |
| Resource footprint | ~20 MB RAM, ~25 MB image |

## What it is

Blackbox Exporter is a small Prometheus exporter that performs synthetic
probes against external endpoints — HTTP/HTTPS, raw TCP, ICMP, DNS — on
demand and returns the result as Prometheus metrics. Probes are
triggered by a Prometheus scrape, not run on a schedule of their own.

## Why it's in oss-learn

It is how the stack answers "is service X alive from the outside?"
without needing an exporter inside every container. PostgreSQL, Ollama,
OpenVINO OVMS, ONNX Runtime server, llama.cpp, OpenSearch, and OpenSearch
Dashboards are all covered through it from a single config file.

## How this repo wires it up

- Container `oss-blackbox` runs `prom/blackbox-exporter:v0.25.0` with
  `--config.file=/etc/blackbox/blackbox.yml` from
  `infra/observability/blackbox.yml`.
- `extra_hosts: ["host.docker.internal:host-gateway"]` lets the container
  reach services running on the Docker host (e.g. Ollama on `:11434`) on
  Linux too, not just on Docker Desktop.
- Three probe modules are defined: `http_2xx` (any HTTP/1.1 or HTTP/2
  200), `http_healthz` (200 plus a body regex `"status":"ok"`), and
  `tcp_connect` (raw TCP handshake).
- Prometheus drives it via four jobs in `prometheus.yml` —
  `oss-ai-healthz`, `oss-db-tcp`, and `oss-opensearch` — all using the
  relabel pattern `__address__ → __param_target → blackbox-exporter:9115`
  so the real target ends up in `instance` and the scrape goes through
  the exporter.
- A `service` label is set per relabel rule (`postgres`, `ollama`,
  `openvino-ovms`, `ort-server`, `llama-cpp`, `opensearch`,
  `opensearch-dashboards`); the Grafana dashboard's
  `probe_success{service="postgres"}` panels key off these.
- Setup polls `http://localhost:9115/-/healthy` for up to 90 s before
  declaring the stack ready;
  `scripts/validate/observability.sh` re-checks `/health`.

## Key concepts

- **Probe module** — a named entry in `blackbox.yml` selecting a prober
  (`http`, `tcp`, `icmp`, `dns`) and its options; chosen per scrape via
  `params: { module: [http_2xx] }`.
- **`/probe` endpoint** — `GET /probe?target=<url>&module=<name>` runs
  the probe synchronously and returns metrics; called by Prometheus on
  each scrape, not by the user directly.
- **`probe_success`** — the headline 0/1 gauge every module emits; the
  dashboard's UP/DOWN tiles read this directly.
- **Relabel sandwich** — the standard pattern that swaps the scrape
  address to the exporter while preserving the real URL as
  `__param_target` and `instance`.
- **Body regex assertion** — `fail_if_body_not_matches_regexp` in
  `http_healthz` lets a probe distinguish a 200 page from an
  actually-healthy 200 page.

## Quick verification

```bash
curl -s 'http://localhost:9115/probe?target=http://localhost:9090/-/ready&module=http_2xx' | grep '^probe_success'
```

Prints `probe_success 1` if the target responded 200 within the module's
timeout — confirming both the exporter and the relabel chain work.

## Common pitfalls

- Probe *targets* are configured in `prometheus.yml` via the relabel
  sandwich (`__address__ → __param_target → blackbox-exporter:9115`),
  **not** in `blackbox.yml` itself. `blackbox.yml` only defines the
  *modules* (how to probe); editing it to add a hostname does nothing
  unless a matching `static_configs` entry is also added on the
  Prometheus side.
- ICMP probes need the container to hold the `NET_RAW` Linux capability;
  the bundled compose file does not grant it, so adding an `icmp` module
  to `blackbox.yml` will fail at probe time until `cap_add: [NET_RAW]`
  (or an equivalent sysctl tweak) is added to the `blackbox-exporter`
  service.
- On Linux, `host.docker.internal` only resolves inside the container
  because of `extra_hosts: ["host.docker.internal:host-gateway"]` in the
  compose file; remove that line and every probe targeting the host
  immediately starts reporting `probe_success 0`, even though the host
  service itself is healthy.
- The `http_healthz` module's body regex (`"status"\s*:\s*"ok"`) is
  JSON-shaped; pointing it at a service whose health endpoint returns
  plain text or a different JSON schema reports `probe_success 0` even
  though the service is fine — fall back to the `http_2xx` module for
  those.
- The exporter does not cache probe results; every Prometheus scrape
  triggers a fresh probe, so a global 15 s `scrape_interval` against a
  slow target adds real network load — tune `scrape_interval` per job
  rather than only globally.

## Suggested example progression

- **Beginner** — `examples/beginner/06_blackbox_probe.py` — hit `/probe`
  for a known-good URL and parse `probe_success` and
  `probe_duration_seconds` *(planned)*
- **Intermediate** — `examples/intermediate/06_blackbox_custom_module.py`
  — add a TLS-cert-expiry probe module to `blackbox.yml`, reload, and
  surface days-until-expiry *(planned)*
- **Advanced** — `examples/advanced/06_blackbox_slo.py` — compute a
  1-hour availability SLO from `probe_success` via the Prometheus query
  API and alert if it dips below 99% *(planned)*

## Related specs

- [prometheus.md](prometheus.md) — scrapes the `/probe` endpoint via the
  `oss-ai-healthz`, `oss-db-tcp`, and `oss-opensearch` jobs in
  `prometheus.yml`; without Prometheus driving it, no probe ever runs
  and the `probe_success` / `probe_duration_seconds` series simply do
  not exist. The relabel sandwich there is what wires real targets to
  this exporter.

## References

- Docs: https://github.com/prometheus/blackbox_exporter/blob/master/README.md
- Source: https://github.com/prometheus/blackbox_exporter
- Configuration cheat sheet: https://github.com/prometheus/blackbox_exporter/blob/master/CONFIGURATION.md
