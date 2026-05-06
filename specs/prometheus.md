# Prometheus

> Pull-based metrics scraper and time-series database for the whole oss-learn stack.

| Field | Value |
|-------|-------|
| Category | Observability / Metrics |
| Repo role | core |
| Install script | scripts/setup/observability.sh |
| Validate suite | scripts/validate/observability.sh |
| Compose / config | infra/observability/docker-compose.yml, infra/observability/prometheus.yml |
| Default port(s) | 9090 (HTTP UI + API) |
| Default credentials | — |

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

## Suggested example progression

- **Beginner** — `examples/beginner/03_prometheus_query.py` — query the
  `up` metric over the HTTP API and print healthy targets *(existing)*
- **Intermediate** — `examples/intermediate/03_prometheus_range_query.py`
  — pull a 1-hour range of `probe_duration_seconds` and chart it with
  matplotlib *(planned)*
- **Advanced** — `examples/advanced/03_prometheus_recording_rule.py` —
  POST a recording rule via the lifecycle API and verify the new series
  appears *(planned)*

## References

- Docs: https://prometheus.io/docs/introduction/overview/
- Source: https://github.com/prometheus/prometheus
