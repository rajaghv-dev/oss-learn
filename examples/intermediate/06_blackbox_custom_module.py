"""Fetch the Blackbox Exporter's loaded config and list module names + probers.

Run:  python examples/intermediate/06_blackbox_custom_module.py
Prereq: bash start.sh   (Blackbox Exporter on localhost:9115)
"""
import os
import sys
import urllib.error
import urllib.request

BLACKBOX = os.environ.get("BLACKBOX_URL", "http://localhost:9115")
url = f"{BLACKBOX}/config"

try:
    with urllib.request.urlopen(url, timeout=5) as resp:
        body = resp.read().decode("utf-8", errors="replace")
except (urllib.error.URLError, ConnectionRefusedError) as err:
    print(f"blackbox-exporter unreachable at {BLACKBOX}: {err}")
    sys.exit(0)

try:
    import yaml  # type: ignore
except ImportError:
    print("(pyyaml not installed — printing raw config)")
    print(body)
    sys.exit(0)

cfg = yaml.safe_load(body) or {}
modules = cfg.get("modules", {}) or {}
if not modules:
    print("no modules defined")
    sys.exit(0)

print(f"{'module':25}  prober")
print(f"{'-' * 25}  {'-' * 10}")
for name, spec in modules.items():
    prober = (spec or {}).get("prober", "?")
    print(f"{name:25}  {prober}")
