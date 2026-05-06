"""Start llama-server, wait for /health, stream a /completion, terminate.

Run:  python examples/intermediate/04_llama_server_http.py
Prereq: bash scripts/setup/llama_cpp.sh
        Env: LLAMA_SERVER=llama-server  LLAMA_GGUF=/path/to/model.gguf
"""
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

LLAMA_SERVER = os.environ.get("LLAMA_SERVER", "llama-server")
LLAMA_GGUF = os.environ.get("LLAMA_GGUF", "")

binary = shutil.which(LLAMA_SERVER) or (LLAMA_SERVER if Path(LLAMA_SERVER).is_file() else "")
if not binary:
    print(f"[skip] {LLAMA_SERVER} not found on PATH; run scripts/setup/llama_cpp.sh")
    sys.exit(0)
if not LLAMA_GGUF or not Path(LLAMA_GGUF).is_file():
    print("[skip] LLAMA_GGUF not set or file missing; export LLAMA_GGUF=/path/to/model.gguf")
    sys.exit(0)


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


port = free_port()
url = f"http://127.0.0.1:{port}"
cmd = [binary, "-m", LLAMA_GGUF, "--host", "127.0.0.1", "--port", str(port), "-c", "512"]
print(f"$ {' '.join(cmd)}")
proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

try:
    deadline = time.time() + 60
    while time.time() < deadline:
        if proc.poll() is not None:
            print(f"[skip] llama-server exited early ({proc.returncode})")
            sys.exit(0)
        try:
            with urllib.request.urlopen(f"{url}/health", timeout=1) as resp:
                if resp.status == 200:
                    break
        except (urllib.error.URLError, ConnectionError):
            time.sleep(0.5)
    else:
        print("[skip] llama-server did not become healthy in 60s")
        sys.exit(0)

    payload = {"prompt": "Q: What is 2+2? A:", "n_predict": 24, "stream": True, "temperature": 0}
    req = urllib.request.Request(
        f"{url}/completion",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    print("---- stream ----")
    with urllib.request.urlopen(req, timeout=120) as resp:
        for raw in resp:
            line = raw.decode().strip()
            if not line.startswith("data:"):
                continue
            chunk = json.loads(line[5:].strip())
            print(chunk.get("content", ""), end="", flush=True)
            if chunk.get("stop"):
                print()
                break
finally:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
