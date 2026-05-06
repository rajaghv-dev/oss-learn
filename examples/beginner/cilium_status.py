"""Shell out to `cilium status --output json` and print agent count + Hubble + cluster mesh.

Run:  python examples/beginner/cilium_status.py
Prereq: bash setup.sh --step cilium
        Active kubeconfig context with Cilium installed (bash scripts/start/k8s.sh).
"""
import json
import os
import subprocess
import sys

KUBECONFIG = os.environ.get("KUBECONFIG", os.path.expanduser("~/.kube/config"))
env = os.environ.copy()
env["KUBECONFIG"] = KUBECONFIG

try:
    proc = subprocess.run(
        ["cilium", "status", "--output", "json"],
        check=True,
        capture_output=True,
        text=True,
        env=env,
        timeout=20,
    )
except FileNotFoundError:
    print("cilium CLI not on PATH; run scripts/setup/cilium.sh")
    sys.exit(0)
except subprocess.CalledProcessError as exc:
    msg = (exc.stderr or "").strip().splitlines()[-1] if exc.stderr else ""
    print(f"cilium status failed ({exc.returncode}): {msg or 'no kubeconfig context active?'}")
    sys.exit(0)
except subprocess.TimeoutExpired:
    print("cilium status timed out; cluster unreachable")
    sys.exit(0)

try:
    payload = json.loads(proc.stdout)
except json.JSONDecodeError as exc:
    print(f"cilium status returned non-JSON: {exc}")
    sys.exit(0)

pod_state = payload.get("PodState", {}) or {}
desired = pod_state.get("Desired", "?")
ready = pod_state.get("Ready", "?")
hubble = (payload.get("Hubble") or {}).get("State", "unknown")
cm = payload.get("ClusterMesh") or {}
cm_state = cm.get("State") or cm.get("Enabled") or "disabled"

print(f"agents (ready/desired): {ready}/{desired}")
print(f"hubble state:           {hubble}")
print(f"cluster mesh:           {cm_state}")

errors = payload.get("Errors") or {}
if errors:
    print(f"errors reported across {len(errors)} component(s)")
