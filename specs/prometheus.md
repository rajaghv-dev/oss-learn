# Prometheus

> Pull-based metrics scraper and time-series database for the whole oss-learn stack.

| Field | Value |
|-------|-------|
| Category | observability / metrics |
| Repo role | core |
| Install script | scripts/setup/observability.sh |
| Validate suite | scripts/validate/observability.sh |
| Compose / config | infra/observability/docker-compose.yml, infra/observability/prometheus.yml |
| Default port(s) | 9090 (HTTP UI + API) |
| Default credentials | — |
| Resource footprint | ~150 MB RAM idle, ~250 MB image, TSDB grows ~1 KB/series/day |

## What it is

Prometheus is a metrics-collection daemon that scrapes HTTP endpoints on a
fixed interval and stores the samples in a local time-series database
(TSDB). It exposes PromQL — a functional query language — over HTTP for
ad-hoc queries, alerting, and as a Grafana data source.

## Why it's in oss-learn

It is the single source of truth for stack health. Every other observability
component in the repo (Grafana panels, Blackbox probes, the OTel collector's
Prometheus exporter, the setup-state exporter) ultimately writes into or
reads out of this one Prometheus instance.

## How this repo wires it up

- Container `oss-prometheus` runs `prom/prometheus:v2.53.0` from
  `infra/observability/docker-compose.yml`.
- Config is bind-mounted from `infra/observability/prometheus.yml`; the
  TSDB persists at `infra/observability/data/prometheus`, which the setup
  script chowns to uid 65534 to dodge the `/prometheus/queries.active`
  permission panic on first boot.
- Retention is 30 days via `--storage.tsdb.retention.time=30d`; lifecycle
  API is enabled (`--web.enable-lifecycle`) so configs can be reloaded
  with `curl -XPOST http://localhost:9090/-/reload`.
- Scrape jobs cover: Prometheus self, OTel collector self-metrics on
  `:8888`, `setup-state-exporter:9901`, and four blackbox-driven jobs
  (`oss-ai-healthz`, `oss-db-tcp`, `oss-opensearch`) plus Ollama's native
  `/metrics`.
- The setup script polls `http://localhost:9090/-/ready` every 5 s for up
  to 90 s before declaring success; `scripts/validate/observability.sh`
  re-checks `/-/healthy` afterwards.
- Grafana's auto-provisioned data source points at `http://prometheus:9090`
  inside the compose network — no manual click-through.

## Key concepts

- **Scrape job** — a named set of targets Prometheus pulls metrics from on
  `scrape_interval` (15 s globally here, 8 s for the state exporter).
- **PromQL** — query language used everywhere from Grafana panels to alert
  rules; `up == 1` is the canonical "target healthy" check.
- **Relabeling** — rewrites labels before/after scraping; the blackbox
  jobs in `prometheus.yml` use it heavily to point Prometheus at the
  blackbox exporter while keeping the real target as `instance`.
- **TSDB** — append-only on-disk format under `/prometheus`; survives
  container restarts via the bind mount and is what the 30-day retention
  flag controls.
- **Lifecycle API** — `/-/reload`, `/-/ready`, `/-/healthy` endpoints used
  by setup scripts and validators rather than `docker exec`.

## Quick verification

```bash
curl -s 'http://localhost:9090/api/v1/query?query=up' | head -c 400
```

Returns a JSON list of every scrape target with a `1` (up) or `0` (down)
value, confirming Prometheus is scraping and serving PromQL.

## Common pitfalls

- The bind-mounted `infra/observability/data/prometheus` directory is
  created by the docker daemon as `root:root` on first `docker compose
  up`; Prometheus runs as uid 65534 (nobody) and panics on
  `/prometheus/queries.active` unless the setup script (or a manual
  `sudo chown -R 65534:65534 infra/observability/data/prometheus`) fixes
  the ownership before the container starts.
- The setup script's YAML pre-parse step (PyYAML when available, a
  grep-based shape check otherwise) trips on tab characters in
  `prometheus.yml` — keep the file consistently 2-space-indented or the
  container will crashloop with no clear error visible in compose's logs.
- `--storage.tsdb.retention.time=30d` is enforced by wall clock, not by
  disk size; a runaway label cardinality from a misconfigured exporter
  can fill the bind mount well before the 30-day window elapses, and
  Prometheus will start failing scrapes silently.
- The lifecycle API (`/-/reload`, `/-/ready`, `/-/healthy`) is only
  available because the compose command line passes
  `--web.enable-lifecycle`; remove that flag and `curl -XPOST
  http://localhost:9090/-/reload` silently 404s instead of reloading.
- Scrape jobs that point at `host.docker.internal` rely on the
  blackbox-exporter's `extra_hosts: ["host.docker.internal:host-gateway"]`
  on Linux — Prometheus itself never resolves that name directly, so
  moving the same job to a non-blackbox target requires explicit
  `extra_hosts` on the Prometheus service too.

## Suggested example progression

- **Beginner** — `examples/beginner/03_prometheus_query.py` — query the
  `up` metric over the HTTP API and print healthy targets *(existing)*
- **Intermediate** — `examples/intermediate/03_prometheus_range_query.py`
  — pull a 1-hour range of `probe_duration_seconds` and chart it with
  matplotlib *(planned)*
- **Advanced** — `examples/advanced/03_prometheus_recording_rule.py` —
  POST a recording rule via the lifecycle API and verify the new series
  appears *(planned)*

## Related specs

- [grafana.md](grafana.md) — the visualizer; its provisioning YAML
  hard-codes `http://prometheus:9090` as the only data source, so every
  panel in `oss-overview.json` reads from this Prometheus instance.
- [otel-collector.md](otel-collector.md) — the sender; the collector's
  `prometheus` exporter on `:8889` and self-metrics on `:8888` are both
  scraped by jobs in `prometheus.yml`, which is how OTLP-emitted samples
  end up in this TSDB.
- [blackbox-exporter.md](blackbox-exporter.md) — the probe runner;
  Prometheus drives it via the relabel-sandwich pattern in jobs
  `oss-ai-healthz`, `oss-db-tcp`, and `oss-opensearch`, and stores the
  resulting `probe_success` and `probe_duration_seconds` series.

## References

- Docs: https://prometheus.io/docs/introduction/overview/
- Source: https://github.com/prometheus/prometheus
- Configuration cheat sheet: https://prometheus.io/docs/prometheus/latest/configuration/configuration/
