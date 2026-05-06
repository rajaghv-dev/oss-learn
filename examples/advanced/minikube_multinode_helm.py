"""Start a 3-node minikube profile, install bitnami/nginx with spread, show placement.

Run:  python examples/advanced/minikube_multinode_helm.py
Prereq: bash scripts/setup/minikube.sh   (minikube + helm + kubectl on PATH, Docker running)
"""
import json
import os
import subprocess
import sys
import time

PROFILE = "oss-learn-multi"
RELEASE = "oss-learn-nginx"
CHART = "oci://registry-1.docker.io/bitnamicharts/nginx"
NS = "default"
KCTL = ["minikube", "kubectl", "-p", PROFILE, "--"]


def run(cmd, **kw):
    print(f"$ {' '.join(cmd)}")
    return subprocess.run(cmd, check=True, **kw)


def profile_exists():
    try:
        out = subprocess.check_output(["minikube", "profile", "list", "-o", "json"], text=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return False
    valid = (data.get("valid") or []) + (data.get("invalid") or [])
    return any(p.get("Name") == PROFILE for p in valid)


started = False
installed = False
try:
    if profile_exists():
        print(f"note: profile {PROFILE} already exists; reusing")
    else:
        run(["minikube", "start", "-p", PROFILE, "--driver=docker", "--nodes=3", "--wait=all"])
    started = True

    deadline = time.time() + 120
    while time.time() < deadline:
        out = subprocess.check_output(
            KCTL + ["get", "nodes", "-o",
                    "jsonpath={range .items[*]}{.status.conditions[?(@.type=='Ready')].status}{'\\n'}{end}"],
            text=True,
        )
        ready = [l for l in out.splitlines() if l.strip() == "True"]
        if len(ready) >= 3:
            print(f"3 nodes Ready ({len(ready)}/3)")
            break
        time.sleep(3)
    else:
        print("note: did not see 3 Ready nodes within 120s")
        sys.exit(0)

    run([
        "helm", "install", RELEASE, CHART,
        "--namespace", NS,
        "--set", "replicaCount=3",
        "--set-json", 'topologySpreadConstraints=[{"maxSkew":1,"topologyKey":"kubernetes.io/hostname",'
                       '"whenUnsatisfiable":"DoNotSchedule",'
                       '"labelSelector":{"matchLabels":{"app.kubernetes.io/instance":"' + RELEASE + '"}}}]',
        "--wait", "--timeout", "180s",
        "--kube-context", PROFILE,
    ])
    installed = True

    run(KCTL + [
        "get", "pods", "-n", NS, "-l", f"app.kubernetes.io/instance={RELEASE}",
        "-o", "custom-columns=POD:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase",
    ])
except (subprocess.CalledProcessError, FileNotFoundError) as exc:
    print(f"note: step failed ({exc})")
finally:
    if installed:
        subprocess.run(
            ["helm", "uninstall", RELEASE, "--namespace", NS, "--kube-context", PROFILE],
            check=False,
        )
    if started:
        subprocess.run(["minikube", "delete", "-p", PROFILE], check=False)
