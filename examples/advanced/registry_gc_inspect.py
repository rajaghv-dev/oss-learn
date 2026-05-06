"""Walk registry repos/tags/manifests and report layer reuse across tags.

Run:  python examples/advanced/registry_gc_inspect.py
Prereq: bash scripts/setup/registry.sh   (registry reachable at :5000, with images)
"""
import json
import os
import sys
import urllib.error
import urllib.request
from collections import defaultdict

REGISTRY = os.environ.get("REGISTRY", "http://localhost:5000")
MANIFEST_ACCEPT = "application/vnd.docker.distribution.manifest.v2+json"


def get_json(path, accept="application/json"):
    req = urllib.request.Request(f"{REGISTRY}{path}", headers={"Accept": accept})
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode())


try:
    repos = get_json("/v2/_catalog").get("repositories", [])
except urllib.error.URLError as exc:
    print(f"registry not reachable: {exc.reason}")
    sys.exit(0)
except ConnectionRefusedError:
    print("registry not reachable: connection refused")
    sys.exit(0)

layer_refs = defaultdict(list)
layer_size = {}
total_tags = 0

for repo in repos:
    try:
        tags = get_json(f"/v2/{repo}/tags/list").get("tags") or []
    except urllib.error.URLError:
        continue
    for tag in tags:
        try:
            manifest = get_json(f"/v2/{repo}/manifests/{tag}", accept=MANIFEST_ACCEPT)
        except urllib.error.URLError:
            continue
        total_tags += 1
        for layer in manifest.get("layers", []):
            digest = layer.get("digest")
            if not digest:
                continue
            layer_refs[digest].append(f"{repo}:{tag}")
            layer_size[digest] = layer.get("size", 0)

if not layer_refs:
    print("(no layers found)")
    sys.exit(0)

total_bytes = sum(layer_size.values())
referenced_bytes = sum(layer_size[d] * len(refs) for d, refs in layer_refs.items())
ratio = referenced_bytes / total_bytes if total_bytes else 1.0

print(f"repos={len(repos)} tags={total_tags} unique_layers={len(layer_refs)}")
print(f"unique_bytes={total_bytes} referenced_bytes={referenced_bytes} dedup_ratio={ratio:.2f}x")
print("top shared layers:")
shared = sorted(layer_refs.items(), key=lambda kv: len(kv[1]), reverse=True)[:5]
for digest, refs in shared:
    print(f"  {digest[:19]}  shared_by={len(refs):3}  size={layer_size[digest]:>10} B")
