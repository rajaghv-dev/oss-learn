"""Install bitnami/redis via Helm, watch rollout, list pods, uninstall.

Run:  python examples/advanced/k3s_helm_chart.py
Prereq: bash scripts/setup/k8s.sh   (helm + kubectl on PATH, cluster reachable)
"""
import os
import subprocess
import sys

RELEASE = "oss-learn-redis"
CHART = "oci://registry-1.docker.io/bitnamicharts/redis"
NS = "default"
ENV = {**os.environ}
if os.environ.get("KUBECONFIG"):
    ENV["KUBECONFIG"] = os.environ["KUBECONFIG"]


def run(cmd, **kw):
    print(f"$ {' '.join(cmd)}")
    return subprocess.run(cmd, check=True, env=ENV, **kw)


try:
    run(["helm", "version", "--short"])
    run(["kubectl", "version", "--client=true"])
except (subprocess.CalledProcessError, FileNotFoundError) as exc:
    print(f"note: helm/kubectl unavailable ({exc})")
    sys.exit(0)

installed = False
try:
    run([
        "helm", "install", RELEASE, CHART,
        "--namespace", NS,
        "--set", "auth.enabled=false",
        "--set", "architecture=standalone",
        "--wait", "--timeout", "180s",
    ])
    installed = True

    run(["helm", "status", RELEASE, "--namespace", NS])
    run([
        "kubectl", "rollout", "status",
        f"statefulset/{RELEASE}-master",
        "-n", NS, "--timeout=120s",
    ])
    run([
        "kubectl", "get", "pods",
        "-n", NS, "-l", f"app.kubernetes.io/instance={RELEASE}",
        "-o", "wide",
    ])
except (subprocess.CalledProcessError, FileNotFoundError) as exc:
    print(f"note: helm/kubectl step failed ({exc})")
finally:
    if installed:
        try:
            subprocess.run(
                ["helm", "uninstall", RELEASE, "--namespace", NS, "--wait"],
                check=False, env=ENV,
            )
        except FileNotFoundError:
            pass
