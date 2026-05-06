# Grafana

> Provisioned dashboard UI sitting on top of the oss-learn Prometheus instance.

| Field | Value |
|-------|-------|
| Category | observability / visualization |
| Repo role | core |
| Install script | scripts/setup/observability.sh |
| Validate suite | scripts/validate/observability.sh |
| Compose / config | infra/observability/docker-compose.yml, infra/observability/grafana/ |
| Default port(s) | 3000 (HTTP UI + API) |
| Default credentials | admin / oss-admin |
| Resource footprint | ~120 MB RAM, ~400 MB image, sqlite metadata persists |

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

## Common pitfalls

- The bind-mounted `infra/observability/data/grafana` directory must be
  owned by uid 472; the setup script pre-chowns it, but if the dir is
  copied around or restored from a backup with the wrong owner, the
  container's self-heal can leave admin auth in a half-broken state
  where the UI loads but `/api/health` returns `database: error`.
- Once `grafana.db` is created in the data dir, the
  `GF_SECURITY_ADMIN_PASSWORD` env var stops taking effect on subsequent
  restarts — the admin password is stuck at whatever the sqlite row says.
  Wipe `data/grafana` entirely (or run `grafana-cli admin
  reset-admin-password <new>` inside the container) to change it.
- Provisioning files are read-only under `/etc/grafana/provisioning`; UI
  edits to a provisioned data source silently fail to persist on
  restart, while dashboard JSON edits do round-trip back to the host
  because the dashboard provider sets `allowUiUpdates: true`.
- The container runs as `user: root` in `docker-compose.yml` to keep the
  bind-mount path simple, which means files Grafana writes back into
  `data/grafana` are owned by root on the host — a `sudo rm -rf` is
  required for cleanup, and a non-root container later will need a
  re-chown.
- `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH` is silently ignored if the
  JSON file is malformed or the path is unreadable; check the container
  logs for `failed to load dashboard` rather than wondering why the home
  page is empty.

## Suggested example progression

- **Beginner** — `examples/beginner/04_grafana_health.py` — hit
  `/api/health` and print the version and DB status *(existing)*
- **Intermediate** — `examples/intermediate/04_grafana_create_dashboard.py`
  — POST a one-panel dashboard via the HTTP API using basic auth
  *(existing)*
- **Advanced** — `examples/advanced/04_grafana_render_png.py` — render
  the `oss-overview` dashboard to PNG via the `/render` endpoint and
  embed it in a generated report *(existing)*

## Related specs

- [prometheus.md](prometheus.md) — the sole provisioned data source;
  every panel in `oss-overview.json` runs PromQL against
  `http://prometheus:9090`, so Grafana is effectively useless in this
  repo if Prometheus is down.
- [otel-collector.md](otel-collector.md) — sits upstream of Prometheus
  and is therefore the upstream of every OTLP-derived metric panel here;
  the collector's `:8889` exporter feeds Prometheus, which feeds Grafana.

## References

- Docs: https://grafana.com/docs/grafana/latest/
- Source: https://github.com/grafana/grafana
- Dashboard JSON model: https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/view-dashboard-json-model/
