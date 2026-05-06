# OpenTelemetry Collector

> OTLP front door that receives traces, metrics, and logs from app code and re-exports them to Prometheus.

| Field | Value |
|-------|-------|
| Category | Observability / Telemetry pipeline |
| Repo role | core |
| Install script | scripts/setup/observability.sh |
| Validate suite | scripts/validate/observability.sh |
| Compose / config | infra/observability/docker-compose.yml, infra/observability/otel-collector-config.yaml |
| Default port(s) | 4317 (OTLP gRPC), 4318 (OTLP HTTP), 8888 (self-metrics), 8889 (Prometheus exporter), 13133 (health) |
| Default credentials | — |

## What it is

The OpenTelemetry Collector is a vendor-neutral agent that ingests
telemetry over OTLP, runs it through a configurable pipeline of
processors, and fans it out to one or more exporters. The `contrib`
distribution used here ships extra receivers and exporters beyond the
core build.

## Why it's in oss-learn

It gives every example — Python, Node, Go, anything with an OTel SDK — a
single fixed endpoint to push traces and metrics at, decoupling app code
from whichever backend the repo happens to run today (Prometheus now,
possibly Jaeger or Tempo later).

## How this repo wires it up

- Container `oss-otel-collector` runs
  `otel/opentelemetry-collector-contrib:0.104.0` with
  `--config=/etc/otel/config.yaml` mounted from
  `infra/observability/otel-collector-config.yaml`.
- Receivers: `otlp` listens on gRPC `0.0.0.0:4317` and HTTP
  `0.0.0.0:4318`; both ports are published to the host.
- Processors: `batch` (5 s timeout, 1000-sample batches) and `resource`
  (injects `system=oss-learn` onto every signal).
- Exporters: traces and logs go to the `debug` exporter (stdout); metrics
  go to the `prometheus` exporter on `0.0.0.0:8889` under namespace `oss`,
  bridging push-based OTLP to pull-based Prometheus.
- Prometheus's `otel-collector` job scrapes the collector's own
  self-metrics on `:8888`; the `:8889` exporter surface is the pipeline
  output and is intended for downstream scraping.
- The `health_check` extension on `:13133` powers the compose healthcheck;
  `depends_on: prometheus { condition: service_healthy }` keeps the
  collector from starting until Prometheus is ready.
- The setup script does a YAML pre-parse on the config (PyYAML if
  available, shape check otherwise) so a typo fails fast instead of
  causing the container to crashloop.

## Key concepts

- **OTLP** — the OpenTelemetry wire protocol; same payload over gRPC
  (`:4317`) or HTTP/protobuf (`:4318`).
- **Pipeline** — a `receivers → processors → exporters` chain declared
  per signal type (`traces`, `metrics`, `logs`) under
  `service.pipelines`.
- **Batch processor** — coalesces samples to cut RPC overhead;
  `send_batch_size: 1000` and `timeout: 5s` are the knobs.
- **Resource processor** — adds or overwrites resource attributes on
  every signal; here it tags everything with `system=oss-learn` so the
  origin is obvious downstream.
- **Prometheus exporter** — turns OTLP metric points into a `/metrics`
  page on `:8889` that Prometheus scrapes — the bridge from push-based
  OTLP to pull-based Prometheus.

## Quick verification

```bash
curl -s http://localhost:13133/healthz
```

Returns `{"status":"Server available", ...}` when the collector's
pipelines are loaded and listening on `:4317` / `:4318`.

## Suggested example progression

- **Beginner** — `examples/beginner/05_otel_health.py` — hit
  `:13133/healthz` and print the receiver/exporter status *(planned)*
- **Intermediate** — `examples/intermediate/05_otel_emit_metric.py` —
  emit a single counter over OTLP/HTTP and watch it land in Prometheus
  under `oss_*` *(planned)*
- **Advanced** — `examples/advanced/02_otel_emit.py` — emit OTLP traces
  and metrics from Python over gRPC `:4317` *(existing)*

## References

- Docs: https://opentelemetry.io/docs/collector/
- Source: https://github.com/open-telemetry/opentelemetry-collector-contrib
