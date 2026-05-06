"""
Kubernetes cluster tests (k3s or minikube).

Verifies kubectl can talk to the cluster and basic kubectl operations work.
Skipped if kubectl/cluster unavailable.
"""
import os
import shutil
import subprocess
import pytest


KUBECTL = shutil.which("kubectl")


def _cluster_reachable():
    if not KUBECTL:
        return False
    try:
        r = subprocess.run([KUBECTL, "get", "nodes", "--no-headers"],
                           capture_output=True, timeout=5)
        return r.returncode == 0
    except Exception:
        return False


pytestmark = pytest.mark.skipif(
    not _cluster_reachable(),
    reason="kubectl not configured / no cluster — run: bash start.sh --k8s OR --minikube"
)


def test_kubectl_version():
    """kubectl version --client returns a value."""
    r = subprocess.run([KUBECTL, "version", "--client", "-o", "json"],
                       capture_output=True, text=True, timeout=5)
    assert r.returncode == 0, r.stderr
    assert "clientVersion" in r.stdout or "gitVersion" in r.stdout


def test_get_nodes():
    """At least one node is Ready."""
    r = subprocess.run([KUBECTL, "get", "nodes", "--no-headers"],
                       capture_output=True, text=True, timeout=10)
    assert r.returncode == 0, r.stderr
    lines = [l for l in r.stdout.splitlines() if l.strip()]
    assert len(lines) >= 1, "No nodes found"
    ready_count = sum(1 for l in lines if "Ready" in l and "NotReady" not in l)
    assert ready_count >= 1, f"No Ready nodes: {lines}"
    print(f"\n  ready nodes: {ready_count}/{len(lines)}")


def test_get_pods_kube_system():
    """kube-system namespace has running pods."""
    r = subprocess.run([KUBECTL, "get", "pods", "-n", "kube-system", "--no-headers"],
                       capture_output=True, text=True, timeout=10)
    assert r.returncode == 0, r.stderr
    pods = [l for l in r.stdout.splitlines() if l.strip()]
    assert len(pods) >= 1


def test_create_and_delete_dummy_namespace():
    """Can create a test namespace and clean it up."""
    ns = "oss-learn-pytest"
    # Create
    r = subprocess.run([KUBECTL, "create", "namespace", ns],
                       capture_output=True, text=True, timeout=10)
    if "AlreadyExists" not in r.stderr and r.returncode != 0:
        pytest.fail(f"Failed to create namespace: {r.stderr}")

    # Verify it exists
    r2 = subprocess.run([KUBECTL, "get", "namespace", ns],
                        capture_output=True, text=True, timeout=5)
    assert r2.returncode == 0

    # Clean up
    subprocess.run([KUBECTL, "delete", "namespace", ns, "--wait=false"],
                   capture_output=True, timeout=10)
