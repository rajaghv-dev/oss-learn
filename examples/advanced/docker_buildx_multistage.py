"""Build a tiny multi-stage image with buildx, push to local registry, pull back.

Run:  python examples/advanced/docker_buildx_multistage.py
Prereq: bash scripts/setup/registry.sh   (Docker + buildx + registry on :5000)
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REGISTRY = os.environ.get("REGISTRY", "localhost:5000")
TAG = os.environ.get("BUILDX_TAG", f"{REGISTRY}/demo/app:1")

DOCKERFILE = """\
FROM alpine:3 AS builder
RUN echo "build-$(date +%s)" > /out/hash 2>/dev/null || (mkdir -p /out && echo build-stamp > /out/hash)

FROM alpine:3
COPY --from=builder /out/hash /hash
CMD ["cat", "/hash"]
"""


def run(*args):
    subprocess.run(args, check=True, text=True)


with tempfile.TemporaryDirectory() as td:
    ctx = Path(td)
    (ctx / "Dockerfile").write_text(DOCKERFILE)
    try:
        run("docker", "buildx", "build", "--load", "-t", TAG, str(ctx))
        run("docker", "push", TAG)
        run("docker", "image", "rm", TAG)
        run("docker", "pull", TAG)
    except FileNotFoundError:
        print("docker CLI not on PATH")
        sys.exit(0)
    except subprocess.CalledProcessError as exc:
        print(f"buildx pipeline failed: rc={exc.returncode} cmd={exc.cmd}")
        sys.exit(0)

print(f"verified round-trip for {TAG}")
