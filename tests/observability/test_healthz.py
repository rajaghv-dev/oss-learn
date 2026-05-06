"""
Observability health tests — Prometheus, Grafana, Blackbox, OTel.

Verifies:
  - Prometheus /-/ready and /-/healthy return 200
  - Grafana /api/health returns 200 with status=ok
  - Blackbox /-/healthy returns 200
  - Prometheus has at least one active target
  - Prometheus metrics endpoint returns valid text
  - Grafana datasources are configured
  - OTel health endpoint responds

Tests are skipped gracefully if the stack is not running.
"""
import pytest
import requests

PROMETHEUS_URL = "http://localhost:9090"
GRAFANA_URL = "http://localhost:3000"
BLACKBOX_URL = "http://localhost:9115"
OTEL_URL = "http://localhost:13133"
GRAFANA_USER = "admin"
GRAFANA_PASS = "oss-admin"


def _reachable(url, timeout=3):
    try:
        return requests.get(url, timeout=timeout).status_code < 500
    except Exception:
        return False


# ── Prometheus ────────────────────────────────────────────────────────────────

@pytest.mark.skipif(not _reachable(f"{PROMETHEUS_URL}/-/ready"),
                    reason=f"Prometheus not reachable at {PROMETHEUS_URL} — run: bash start.sh")
class TestPrometheus:

    def test_prometheus_ready(self):
        """Prometheus /-/ready returns 200."""
        r = requests.get(f"{PROMETHEUS_URL}/-/ready", timeout=5)
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"

    def test_prometheus_healthy(self):
        """Prometheus /-/healthy returns 200."""
        r = requests.get(f"{PROMETHEUS_URL}/-/healthy", timeout=5)
        assert r.status_code == 200

    def test_prometheus_metrics_endpoint(self):
        """Prometheus /metrics exposes its own metrics in text format."""
        r = requests.get(f"{PROMETHEUS_URL}/metrics", timeout=5)
        assert r.status_code == 200
        assert "prometheus_build_info" in r.text, "prometheus_build_info metric not found"

    def test_prometheus_has_targets(self):
        """/api/v1/targets returns at least one active target."""
        r = requests.get(f"{PROMETHEUS_URL}/api/v1/targets", timeout=5)
        assert r.status_code == 200
        data = r.json()
        active = data.get("data", {}).get("activeTargets", [])
        assert len(active) >= 1, f"Expected >= 1 active targets, got {len(active)}"
        print(f"\n  active targets: {len(active)}")
        for t in active[:5]:
            print(f"    job={t.get('labels', {}).get('job')}  state={t.get('health')}")

    def test_prometheus_config_endpoint(self):
        """/api/v1/status/config returns the loaded scrape config YAML."""
        r = requests.get(f"{PROMETHEUS_URL}/api/v1/status/config", timeout=5)
        assert r.status_code == 200
        data = r.json()
        assert "yaml" in data.get("data", {}), "Expected 'yaml' key in config response"
        yaml_content = data["data"]["yaml"]
        assert "scrape_configs" in yaml_content, "scrape_configs missing from config"

    def test_prometheus_query_up(self):
        """Can run a PromQL query and get a valid result."""
        r = requests.get(f"{PROMETHEUS_URL}/api/v1/query",
                         params={"query": "up"}, timeout=5)
        assert r.status_code == 200
        data = r.json()
        assert data.get("status") == "success", f"PromQL query failed: {data}"
        results = data.get("data", {}).get("result", [])
        assert len(results) >= 1, "Expected at least one 'up' result"
        print(f"\n  'up' metrics count: {len(results)}")

    def test_prometheus_range_query(self):
        """Range query over last 60s works."""
        import time
        now = time.time()
        r = requests.get(f"{PROMETHEUS_URL}/api/v1/query_range",
                         params={
                             "query": "up",
                             "start": now - 60,
                             "end": now,
                             "step": "15",
                         }, timeout=5)
        assert r.status_code == 200
        data = r.json()
        assert data.get("status") == "success"


# ── Grafana ────────────────────────────────────────────────────────────────────

@pytest.mark.skipif(not _reachable(f"{GRAFANA_URL}/api/health"),
                    reason=f"Grafana not reachable at {GRAFANA_URL}")
class TestGrafana:

    def test_grafana_health(self):
        """Grafana /api/health returns status=ok."""
        r = requests.get(f"{GRAFANA_URL}/api/health", timeout=5)
        assert r.status_code == 200
        data = r.json()
        assert data.get("database") in ("ok", "connected", None), \
            f"Grafana database not ok: {data}"
        print(f"\n  Grafana health: {data}")

    def test_grafana_login_works(self):
        """Grafana admin credentials are accepted."""
        r = requests.get(
            f"{GRAFANA_URL}/api/org",
            auth=(GRAFANA_USER, GRAFANA_PASS),
            timeout=5,
        )
        assert r.status_code == 200, \
            f"Grafana login failed ({r.status_code}) — check admin/oss-admin credentials"

    def test_grafana_datasources_configured(self):
        """At least one datasource (Prometheus) is configured in Grafana."""
        r = requests.get(
            f"{GRAFANA_URL}/api/datasources",
            auth=(GRAFANA_USER, GRAFANA_PASS),
            timeout=5,
        )
        assert r.status_code == 200
        datasources = r.json()
        assert len(datasources) >= 1, "No datasources configured in Grafana"
        ds_types = [ds.get("type") for ds in datasources]
        print(f"\n  datasource types: {ds_types}")
        assert "prometheus" in ds_types, f"Prometheus datasource not found; found: {ds_types}"

    def test_grafana_dashboards_provisioned(self):
        """At least one dashboard is provisioned."""
        r = requests.get(
            f"{GRAFANA_URL}/api/search?type=dash-db",
            auth=(GRAFANA_USER, GRAFANA_PASS),
            timeout=5,
        )
        assert r.status_code == 200
        dashboards = r.json()
        assert len(dashboards) >= 1, "No dashboards found — check grafana/dashboards provisioning"
        print(f"\n  dashboards: {[d.get('title') for d in dashboards]}")


# ── Blackbox Exporter ─────────────────────────────────────────────────────────

@pytest.mark.skipif(not _reachable(f"{BLACKBOX_URL}/-/healthy"),
                    reason=f"Blackbox not reachable at {BLACKBOX_URL}")
class TestBlackbox:

    def test_blackbox_healthy(self):
        """Blackbox /-/healthy returns 200."""
        r = requests.get(f"{BLACKBOX_URL}/-/healthy", timeout=5)
        assert r.status_code == 200

    def test_blackbox_probe_http(self):
        """Blackbox can probe an HTTP endpoint (Prometheus itself)."""
        r = requests.get(
            f"{BLACKBOX_URL}/probe",
            params={"target": f"{PROMETHEUS_URL}/-/healthy", "module": "http_2xx"},
            timeout=10,
        )
        assert r.status_code == 200
        assert "probe_success 1" in r.text, \
            f"probe_success metric not 1 — Blackbox failed to probe Prometheus\n{r.text[:500]}"

    def test_blackbox_probe_success_metric(self):
        """probe_success=1 when probing localhost:9090."""
        r = requests.get(
            f"{BLACKBOX_URL}/probe",
            params={"target": f"http://localhost:9090/-/ready", "module": "http_2xx"},
            timeout=10,
        )
        lines = [l for l in r.text.splitlines() if l.startswith("probe_success")]
        assert lines, "probe_success metric not found in blackbox output"
        assert "1" in lines[0], f"probe_success is not 1: {lines[0]}"


# ── OpenTelemetry Collector ───────────────────────────────────────────────────

@pytest.mark.skipif(not _reachable(f"{OTEL_URL}/healthz"),
                    reason=f"OTel collector not reachable at {OTEL_URL}")
class TestOtelCollector:

    def test_otel_health_endpoint(self):
        """OTel collector /healthz returns 200."""
        r = requests.get(f"{OTEL_URL}/healthz", timeout=5)
        assert r.status_code == 200
        print(f"\n  OTel collector health: {r.text[:100]}")
