"""Apply httpd Deployment+Service via minikube kubectl, hit it, clean up.

Run:  python examples/intermediate/minikube_deploy_app.py
Prereq: bash scripts/setup/minikube.sh && minikube start   (cluster must be running)
"""
import os
import subprocess
import sys
import urllib.request

PROFILE = os.environ.get("MINIKUBE_PROFILE", "minikube")
NAME = "oss-learn-httpd"
MANIFEST = f"""\
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {NAME}
spec:
  replicas: 1
  selector: {{matchLabels: {{app: {NAME}}}}}
  template:
    metadata: {{labels: {{app: {NAME}}}}}
    spec:
      containers:
      - name: httpd
        image: httpd:alpine
        ports: [{{containerPort: 80}}]
---
apiVersion: v1
kind: Service
metadata:
  name: {NAME}
spec:
  type: NodePort
  selector: {{app: {NAME}}}
  ports: [{{port: 80, targetPort: 80}}]
"""

KCTL = ["minikube", "kubectl", "-p", PROFILE, "--"]


def run(cmd, **kw):
    print(f"$ {' '.join(cmd)}")
    return subprocess.run(cmd, check=True, **kw)


applied = False
try:
    run(KCTL + ["apply", "-f", "-"], input=MANIFEST, text=True)
    applied = True
    run(KCTL + ["rollout", "status", f"deployment/{NAME}", "--timeout=120s"])
    url = subprocess.check_output(
        ["minikube", "service", NAME, "--url", "-p", PROFILE], text=True,
    ).strip().splitlines()[0]
    print(f"service url: {url}")
    with urllib.request.urlopen(url, timeout=10) as r:
        body = r.read(120).decode(errors="replace")
        print(f"GET {url} -> {r.status} {r.reason}; body[:120]={body!r}")
except (subprocess.CalledProcessError, FileNotFoundError) as exc:
    print(f"note: minikube/kubectl step failed ({exc})")
finally:
    if applied:
        subprocess.run(
            KCTL + ["delete", "-f", "-", "--ignore-not-found"],
            input=MANIFEST, text=True, check=False,
        )
