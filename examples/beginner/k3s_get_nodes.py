"""List k3s/k8s nodes via the kubernetes Python client.

Run:  python examples/beginner/k3s_get_nodes.py
Prereq: bash scripts/setup/k8s.sh   (k3s up, ~/.kube/config readable, `pip install kubernetes`)
"""
import os
import sys

try:
    from kubernetes import client, config
    from kubernetes.client.exceptions import ApiException
except ImportError:
    print("note: kubernetes python client missing; pip install kubernetes")
    sys.exit(0)

KUBECONFIG = os.environ.get("KUBECONFIG")

try:
    config.load_kube_config(config_file=KUBECONFIG)
except (config.ConfigException, FileNotFoundError) as exc:
    print(f"note: kubeconfig unavailable ({exc})")
    sys.exit(0)

v1 = client.CoreV1Api()
try:
    nodes = v1.list_node().items
except ApiException as exc:
    print(f"note: apiserver unreachable ({exc.reason})")
    sys.exit(0)
except Exception as exc:
    print(f"note: cluster unreachable ({exc})")
    sys.exit(0)

print(f"{'NAME':<28} {'STATUS':<10} {'VERSION':<14} OS-IMAGE")
for node in nodes:
    name = node.metadata.name
    ready = "NotReady"
    for cond in node.status.conditions or []:
        if cond.type == "Ready":
            ready = "Ready" if cond.status == "True" else "NotReady"
            break
    info = node.status.node_info
    version = info.kubelet_version if info else "?"
    os_image = info.os_image if info else "?"
    print(f"{name:<28} {ready:<10} {version:<14} {os_image}")
