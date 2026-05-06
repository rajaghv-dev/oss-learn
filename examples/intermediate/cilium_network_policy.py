"""Apply a CiliumNetworkPolicy (deny-all + allow-from-app=client) and show enforcement.

Run:  python examples/intermediate/cilium_network_policy.py
Prereq: bash setup.sh --step cilium
        Active kubeconfig context with Cilium installed.
"""
import os
import subprocess
import sys

KUBECONFIG = os.environ.get("KUBECONFIG", os.path.expanduser("~/.kube/config"))
NS = "oss-learn-cnp"
env = os.environ.copy()
env["KUBECONFIG"] = KUBECONFIG

POLICY = f"""apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: deny-all-allow-client
  namespace: {NS}
spec:
  endpointSelector:
    matchLabels:
      app: server
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: client
"""


def kc(*args, check=True, stdin=None):
    return subprocess.run(
        ["kubectl", *args], check=check, capture_output=True, text=True,
        input=stdin, env=env, timeout=60,
    )


def cleanup():
    kc("delete", "ns", NS, "--ignore-not-found", "--wait=false", check=False)


try:
    kc("create", "ns", NS, check=False)
    p = kc("apply", "-n", NS, "-f", "-", stdin=POLICY, check=False)
    if p.returncode != 0:
        print(f"policy apply failed: {(p.stderr or '').strip().splitlines()[-1]}")
        cleanup(); sys.exit(0)
    kc("run", "server", "-n", NS, "--image=busybox:1.36", "--labels=app=server",
       "--restart=Never", "--", "sh", "-c", "while true; do echo hi | nc -l -p 8080; done")
    kc("run", "client", "-n", NS, "--image=busybox:1.36", "--labels=app=client",
       "--restart=Never", "--", "sleep", "300")
    kc("run", "rogue", "-n", NS, "--image=busybox:1.36", "--labels=app=rogue",
       "--restart=Never", "--", "sleep", "300")
    for pod in ("server", "client", "rogue"):
        kc("wait", "-n", NS, f"pod/{pod}", "--for=condition=Ready", "--timeout=60s", check=False)
    server_ip = kc("get", "pod", "server", "-n", NS, "-o", "jsonpath={.status.podIP}").stdout.strip()
    print(f"server pod IP: {server_ip}")
    for src in ("client", "rogue"):
        r = kc("exec", "-n", NS, src, "--",
               "wget", "-q", "-T", "3", "-O-", f"http://{server_ip}:8080/", check=False)
        verdict = "ALLOWED" if r.returncode == 0 else "DENIED"
        print(f"  {src} -> server : {verdict}")
except FileNotFoundError:
    print("kubectl not on PATH")
    cleanup(); sys.exit(0)
except subprocess.CalledProcessError as exc:
    print(f"kubectl failed ({exc.returncode}): {(exc.stderr or '').strip().splitlines()[-1] if exc.stderr else ''}")
    cleanup(); sys.exit(0)
except subprocess.TimeoutExpired:
    print("kubectl timed out")
    cleanup(); sys.exit(0)
finally:
    cleanup()
