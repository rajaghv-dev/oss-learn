"""Run the `hello-world` image via the Docker SDK and print its output.

Run:  python examples/beginner/docker_hello.py
Prereq: bash scripts/setup/docker.sh   (Docker daemon reachable; `pip install docker`)
"""
import os
import sys

try:
    import docker
    from docker.errors import DockerException
except ImportError:
    print("docker SDK not installed; run: pip install docker")
    sys.exit(0)

IMAGE = os.environ.get("DOCKER_HELLO_IMAGE", "hello-world")

try:
    client = docker.from_env()
    client.ping()
except DockerException as exc:
    print(f"Docker not reachable: {exc.__class__.__name__}")
    sys.exit(0)

try:
    output = client.containers.run(IMAGE, remove=True)
except DockerException as exc:
    print(f"Docker run failed: {exc.__class__.__name__}: {exc}")
    sys.exit(0)

text = output.decode() if isinstance(output, bytes) else str(output)
for line in text.splitlines():
    print(line)
