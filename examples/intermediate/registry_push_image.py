"""Pull alpine, retag, push to local registry, confirm via catalog, pull back.

Run:  python examples/intermediate/registry_push_image.py
Prereq: bash scripts/setup/registry.sh   (Docker + registry on :5000)
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

REGISTRY = os.environ.get("REGISTRY", "localhost:5000")
SOURCE = os.environ.get("SOURCE_IMAGE", "alpine:3")
TARGET = os.environ.get("TARGET_IMAGE", f"{REGISTRY}/demo/alpine:1")


def run(*args):
    subprocess.run(args, check=True, text=True)


try:
    run("docker", "pull", SOURCE)
    run("docker", "tag", SOURCE, TARGET)
    run("docker", "push", TARGET)
except FileNotFoundError:
    print("docker CLI not on PATH")
    sys.exit(0)
except subprocess.CalledProcessError as exc:
    print(f"docker pipeline failed: rc={exc.returncode} cmd={exc.cmd}")
    sys.exit(0)

try:
    with urllib.request.urlopen(f"http://{REGISTRY}/v2/_catalog", timeout=5) as resp:
        repos = json.loads(resp.read().decode()).get("repositories", [])
except (urllib.error.URLError, ConnectionRefusedError) as exc:
    reason = getattr(exc, "reason", exc)
    print(f"catalog query failed: {reason}")
    sys.exit(0)

print("catalog:")
for repo in repos:
    marker = " <- pushed" if TARGET.split("/", 1)[1].split(":")[0] == repo else ""
    print(f"  {repo}{marker}")

try:
    run("docker", "image", "rm", TARGET)
    run("docker", "pull", TARGET)
except subprocess.CalledProcessError as exc:
    print(f"verify-pull failed: rc={exc.returncode}")
    sys.exit(0)

print(f"verified round-trip for {TARGET}")
