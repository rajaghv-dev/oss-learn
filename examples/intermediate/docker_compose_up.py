"""Bring an `infra/*/docker-compose.yml` up, poll status, then tear it down.

Run:  python examples/intermediate/docker_compose_up.py
Prereq: bash scripts/setup/docker.sh   (Docker Engine + Compose v2 plugin)
"""
import json
import os
import subprocess
import sys
import time

COMPOSE_FILE = os.environ.get(
    "COMPOSE_FILE", "infra/observability/docker-compose.yml"
)
POLL_SECONDS = int(os.environ.get("COMPOSE_POLL_SECONDS", "10"))


def compose(*args, capture=False):
    cmd = ["docker", "compose", "-f", COMPOSE_FILE, *args]
    return subprocess.run(cmd, check=True, text=True, capture_output=capture)


if not os.path.exists(COMPOSE_FILE):
    print(f"compose file not found: {COMPOSE_FILE}")
    sys.exit(0)

try:
    compose("up", "-d")
except FileNotFoundError:
    print("docker CLI not on PATH")
    sys.exit(0)
except subprocess.CalledProcessError as exc:
    print(f"docker compose up failed: rc={exc.returncode}")
    sys.exit(0)

try:
    deadline = time.time() + POLL_SECONDS
    while time.time() < deadline:
        result = compose("ps", "--format", "json", capture=True)
        rows = []
        for line in result.stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                rows.extend(json.loads(line) if line.startswith("[") else [])
        for row in rows:
            name = row.get("Name") or row.get("Service")
            state = row.get("State") or row.get("Status")
            print(f"  {name:30}  {state}")
        if rows and all(r.get("State") == "running" for r in rows):
            break
        time.sleep(1)
finally:
    try:
        compose("down")
    except subprocess.CalledProcessError as exc:
        print(f"docker compose down failed: rc={exc.returncode}")
