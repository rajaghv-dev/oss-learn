# Grafana

> Provisioned dashboard UI sitting on top of the oss-learn Prometheus instance.

| Field | Value |
|-------|-------|
| Category | Observability / Visualization |
| Repo role | core |
| Install script | scripts/setup/observability.sh |
| Validate suite | scripts/validate/observability.sh |
| Compose / config | infra/observability/docker-compose.yml, infra/observability/grafana/ |
| Default port(s) | 3000 (HTTP UI + API) |
| Default credentials | admin / oss-admin |

## What it is

Grafana is a web dashboard application for time-series and tabular data.
It connects to one or more data sources (Prometheus, in this repo),
renders panels via templated queries, and serves the result as an
interactive HTML UI on port 3000.

## Why it's in oss-learn

It turns the raw `up`, `probe_success`, and `probe_duration_seconds`
series flowing into Prometheus into a single at-a-glance health page, so
a learner can see whether their stack is actually working without writing
any PromQL.

## How this repo wires it up

- Container `oss-grafana` runs `grafana/grafana:11.1.0` from
  `infra/observability/docker-compose.yml`.
- Admin credentials are pinned via the env vars
  `GF_SECURITY_ADMIN_USER=admin` and `GF_SECURITY_ADMIN_PASSWORD=oss-admin`
  (also surfaced in `.env.example`); sign-up and analytics phone-home are
  disabled.
- Provisioning is fully file-driven:
  `grafana/provisioning/datasources/prometheus.yaml` registers the
  Prometheus data source at `http://prometheus:9090`, and
  `provisioning/dashboards/dashboards.yaml` auto-loads everything from
  `/var/lib/grafana/dashboards` (`updateIntervalSeconds: 30`,
  `allowUiUpdates: true`).
- The bundled dashboard `grafana/dashboards/oss-overview.json` is set as
  the default home page via
  `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH`; it shows
  Prometheus/Postgres/Ollama up-gauges, AI probe duration, and a target
  count timeseries.
- State persists at `infra/observability/data/grafana`; the setup script
  chowns it to uid 472, though Grafana's entrypoint also self-heals — the
  container runs as root to keep the bind-mount path simple.
- Setup polls `http://localhost:3000/api/health` for up to 90 s and
  `scripts/validate/observability.sh` re-checks it.

## Key concepts

- **Provisioning** — YAML files under `provisioning/` register data
  sources and dashboard providers at boot; no clickops needed.
- **Dashboard JSON** — each dashboard is a single JSON file under
  `grafana/dashboards/`; edits made in the UI sync back when
  `allowUiUpdates` is true.
- **Data source variable** — `${datasource}` in panel queries lets the
  same JSON target whichever Prometheus is selected from the templating
  dropdown, so dashboards stay portable.
- **Panel target** — a PromQL expression plus a legend template; e.g.
  `up{job="prometheus"}` rendered as a gauge with red/green thresholds.
- **`/api/health`** — the unauthenticated health endpoint used by both
  the compose healthcheck and the validate script.

## Quick verification

```bash
curl -s http://localhost:3000/api/health
```

Returns `{"database": "ok", "version": "...", "commit": "..."}` once
Grafana has booted and reached its sqlite metadata DB.

## Suggested example progression

- **Beginner** — `examples/beginner/04_grafana_health.py` — hit
  `/api/health` and print the version and DB status *(planned)*
- **Intermediate** — `examples/intermediate/04_grafana_create_dashboard.py`
  — POST a one-panel dashboard via the HTTP API using basic auth
  *(planned)*
- **Advanced** — `examples/advanced/04_grafana_render_png.py` — render
  the `oss-overview` dashboard to PNG via the `/render` endpoint and
  embed it in a generated report *(planned)*

## References

- Docs: https://grafana.com/docs/grafana/latest/
- Source: https://github.com/grafana/grafana
