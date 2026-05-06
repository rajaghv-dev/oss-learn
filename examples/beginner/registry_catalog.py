"""List repositories in the local Docker registry via the v2 catalog API.

Run:  python examples/beginner/registry_catalog.py
Prereq: bash scripts/setup/registry.sh   (registry reachable at :5000)
"""
import json
import os
import sys
import urllib.error
import urllib.request

REGISTRY = os.environ.get("REGISTRY", "http://localhost:5000")

try:
    with urllib.request.urlopen(f"{REGISTRY}/v2/_catalog", timeout=5) as resp:
        payload = json.loads(resp.read().decode())
except urllib.error.URLError as exc:
    print(f"registry not reachable: {exc.reason}")
    sys.exit(0)
except ConnectionRefusedError:
    print("registry not reachable: connection refused")
    sys.exit(0)

repos = payload.get("repositories", [])
if not repos:
    print("(empty catalog)")
    sys.exit(0)

for repo in repos:
    print(repo)
