"""Run llama-bench across a comma-separated GGUF list and print tokens/sec.

Run:  LLAMA_GGUFS=a.gguf,b.gguf python examples/advanced/02_llama_bench_quant_compare.py
Prereq: bash scripts/setup/llama_cpp.sh
        Env: LLAMA_GGUFS=path1.gguf,path2.gguf  (optional CPU_THREADS, LLAMA_BENCH)
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

LLAMA_BENCH = os.environ.get("LLAMA_BENCH", "llama-bench")
GGUFS_RAW = os.environ.get("LLAMA_GGUFS", "").strip()
THREADS = os.environ.get("CPU_THREADS", str(os.cpu_count() or 4))

if not GGUFS_RAW:
    print("[skip] LLAMA_GGUFS not set; export LLAMA_GGUFS=a.gguf,b.gguf to compare quants")
    sys.exit(0)

binary = shutil.which(LLAMA_BENCH) or (LLAMA_BENCH if Path(LLAMA_BENCH).is_file() else "")
if not binary:
    print(f"[skip] {LLAMA_BENCH} not found on PATH; run scripts/setup/llama_cpp.sh")
    sys.exit(0)

ggufs = [p.strip() for p in GGUFS_RAW.split(",") if p.strip()]
rows: list[tuple[str, str, float]] = []

for gguf in ggufs:
    if not Path(gguf).is_file():
        print(f"[skip] missing GGUF: {gguf}")
        continue
    cmd = [binary, "-m", gguf, "-p", "32", "-n", "64", "-t", THREADS, "-o", "json"]
    print(f"$ {' '.join(cmd)}")
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        print(f"[skip] llama-bench timed out for {gguf}")
        continue
    if proc.returncode != 0:
        print(f"[skip] llama-bench exited {proc.returncode} for {gguf}")
        print(proc.stderr[-300:])
        continue
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        print(f"[skip] could not parse JSON for {gguf}")
        continue
    for entry in data:
        label = entry.get("n_prompt") and f"pp{entry['n_prompt']}" or f"tg{entry.get('n_gen','?')}"
        tps = float(entry.get("avg_ts") or entry.get("ts") or 0.0)
        rows.append((Path(gguf).name, label, tps))

if not rows:
    print("[skip] no successful benchmarks")
    sys.exit(0)

print()
print(f"{'gguf':<40}  {'phase':<8}  {'tok/s':>10}")
for name, label, tps in rows:
    print(f"{name:<40}  {label:<8}  {tps:>10.2f}")
