# Blackbox Exporter

> External-probe Prometheus exporter that turns HTTP/TCP/ICMP checks into scrapeable metrics.

| Field | Value |
|-------|-------|
| Category | Observability / Synthetic monitoring |
| Repo role | core |
| Install script | scripts/setup/observability.sh |
| Validate suite | scripts/validate/observability.sh |
| Compose / config | infra/observability/docker-compose.yml, infra/observability/blackbox.yml |
| Default port(s) | 9115 (HTTP — `/probe`, `/metrics`, `/-/healthy`) |
| Default credentials | — |

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

## References

- Docs: https://github.com/prometheus/blackbox_exporter/blob/master/README.md
- Source: https://github.com/prometheus/blackbox_exporter
