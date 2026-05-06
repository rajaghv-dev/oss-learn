"""Generate a recording-rules YAML in a tempdir and print the reload command.

Run:  python examples/advanced/03_prometheus_recording_rule.py
Prereq: bash start.sh   (Prometheus on localhost:9090, lifecycle API enabled)
"""
import os
import sys
import tempfile
import urllib.error
import urllib.request

PROM = os.environ.get("PROMETHEUS_URL", "http://localhost:9090")

RULES_YAML = """groups:
  - name: oss-learn-recording
    interval: 15s
    rules:
      - record: job:up:ratio
        expr: avg by (job) (up)
"""

tmpdir = tempfile.mkdtemp(prefix="oss-learn-rules-")
rule_path = os.path.join(tmpdir, "oss-learn-recording.yml")
with open(rule_path, "w", encoding="utf-8") as fh:
    fh.write(RULES_YAML)

print(f"wrote rule file: {rule_path}")
print()
print("to install (option a, default):")
print(f"  cp {rule_path} infra/observability/prometheus-rules/")
print("  # then add the file to rule_files: in prometheus.yml")
print(f"  curl -XPOST {PROM}/-/reload")
print()
print("to verify after reload:")
print(f"  curl -s '{PROM}/api/v1/rules' | head -c 400")

try:
    with urllib.request.urlopen(f"{PROM}/api/v1/status/config", timeout=5) as resp:
        ok = resp.status == 200
except (urllib.error.URLError, ConnectionRefusedError) as err:
    print(f"\n(prometheus unreachable at {PROM}: {err}; rule file still written)")
    sys.exit(0)

print(f"\nprometheus reachable: {ok}")
