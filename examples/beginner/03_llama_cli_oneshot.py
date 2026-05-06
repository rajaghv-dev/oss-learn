"""One-shot llama-cli wrapper: generate up to 32 tokens for a fixed prompt.

Run:  python examples/beginner/03_llama_cli_oneshot.py
Prereq: bash scripts/setup/llama_cpp.sh
        Env: LLAMA_CLI=llama-cli  LLAMA_GGUF=/path/to/model.gguf
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

LLAMA_CLI = os.environ.get("LLAMA_CLI", "llama-cli")
LLAMA_GGUF = os.environ.get("LLAMA_GGUF", "")
PROMPT = "Hello, world."

cli = shutil.which(LLAMA_CLI) or (LLAMA_CLI if Path(LLAMA_CLI).is_file() else "")
if not cli:
    print(f"[skip] {LLAMA_CLI} not found on PATH; run scripts/setup/llama_cpp.sh")
    sys.exit(0)

if not LLAMA_GGUF or not Path(LLAMA_GGUF).is_file():
    print("[skip] LLAMA_GGUF not set or file missing; export LLAMA_GGUF=/path/to/model.gguf")
    sys.exit(0)

cmd = [
    cli,
    "--model", LLAMA_GGUF,
    "-p", PROMPT,
    "-n", "32",
    "--no-display-prompt",
    "-no-cnv",
    "--temp", "0",
]
print(f"$ {' '.join(cmd)}")
try:
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
except subprocess.TimeoutExpired:
    print("[skip] llama-cli timed out after 120s")
    sys.exit(0)

if proc.returncode != 0:
    print(f"[skip] llama-cli exited {proc.returncode}")
    print(proc.stderr[-400:] if proc.stderr else "")
    sys.exit(0)

print("---- output ----")
print(proc.stdout.strip())
