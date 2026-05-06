"""Deploy nginx, port-forward via kubectl subprocess, curl it, clean up.

Run:  python examples/intermediate/k3s_deploy_nginx.py
Prereq: bash scripts/setup/k8s.sh   (kubectl on PATH, `pip install kubernetes`)
"""
import os
import subprocess
import sys
import time
import urllib.request

try:
    from kubernetes import client, config
    from kubernetes.client.exceptions import ApiException
except ImportError:
    print("note: kubernetes python client missing; pip install kubernetes")
    sys.exit(0)

NS = "default"
NAME = "oss-learn-nginx"
LOCAL_PORT = "18080"
KUBECONFIG = os.environ.get("KUBECONFIG")

try:
    config.load_kube_config(config_file=KUBECONFIG)
except (config.ConfigException, FileNotFoundError) as exc:
    print(f"note: kubeconfig unavailable ({exc})")
    sys.exit(0)

apps, core = client.AppsV1Api(), client.CoreV1Api()
labels = {"app": NAME}
dep = client.V1Deployment(
    metadata=client.V1ObjectMeta(name=NAME),
    spec=client.V1DeploymentSpec(
        replicas=2,
        selector=client.V1LabelSelector(match_labels=labels),
        template=client.V1PodTemplateSpec(
            metadata=client.V1ObjectMeta(labels=labels),
            spec=client.V1PodSpec(containers=[client.V1Container(
                name="nginx", image="nginx:alpine",
                ports=[client.V1ContainerPort(container_port=80)])]),
        ),
    ),
)
svc = client.V1Service(
    metadata=client.V1ObjectMeta(name=NAME),
    spec=client.V1ServiceSpec(selector=labels, type="ClusterIP",
                              ports=[client.V1ServicePort(port=80, target_port=80)]),
)

pf = None
try:
    apps.create_namespaced_deployment(NS, dep)
    core.create_namespaced_service(NS, svc)
    deadline = time.time() + 120
    while time.time() < deadline:
        d = apps.read_namespaced_deployment_status(NAME, NS)
        if (d.status.available_replicas or 0) == 2:
            break
        time.sleep(2)
    else:
        print("note: deployment never reached 2 available replicas")
        sys.exit(0)

    pf = subprocess.Popen(
        ["kubectl", "port-forward", f"svc/{NAME}", f"{LOCAL_PORT}:80", "-n", NS],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(3)
    with urllib.request.urlopen(f"http://localhost:{LOCAL_PORT}", timeout=5) as r:
        print(f"GET / -> {r.status} {r.reason}")
except (ApiException, subprocess.CalledProcessError, FileNotFoundError) as exc:
    print(f"note: {exc}")
    sys.exit(0)
finally:
    if pf:
        pf.terminate()
        try: pf.wait(timeout=5)
        except subprocess.TimeoutExpired: pf.kill()
    for delete in (lambda: core.delete_namespaced_service(NAME, NS),
                   lambda: apps.delete_namespaced_deployment(NAME, NS)):
        try: delete()
        except ApiException: pass
