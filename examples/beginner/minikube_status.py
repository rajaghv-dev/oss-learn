"""Print minikube cluster status (host/kubelet/apiserver/kubeconfig) per profile.

Run:  python examples/beginner/minikube_status.py
Prereq: bash scripts/setup/minikube.sh   (minikube on PATH; cluster may or may not be running)
"""
import json
import os
import subprocess
import sys

PROFILE = os.environ.get("MINIKUBE_PROFILE", "minikube")

try:
    proc = subprocess.run(
        ["minikube", "status", "-p", PROFILE, "-o", "json"],
        capture_output=True, text=True,
    )
except FileNotFoundError:
    print("note: minikube not on PATH")
    sys.exit(0)

if not proc.stdout.strip():
    print(f"note: minikube returned empty status (rc={proc.returncode}); {proc.stderr.strip()}")
    sys.exit(0)

try:
    data = json.loads(proc.stdout)
except json.JSONDecodeError as exc:
    print(f"note: could not parse minikube status json ({exc})")
    sys.exit(0)

profiles = data if isinstance(data, list) else [data]
print(f"{'PROFILE':<24} {'HOST':<10} {'KUBELET':<10} {'APISERVER':<12} KUBECONFIG")
for p in profiles:
    print(
        f"{p.get('Name', '?'):<24} "
        f"{p.get('Host', '?'):<10} "
        f"{p.get('Kubelet', '?'):<10} "
        f"{p.get('APIServer', '?'):<12} "
        f"{p.get('Kubeconfig', '?')}"
    )
