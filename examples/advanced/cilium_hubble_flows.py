"""Stream `hubble observe --output json` and print a histogram by verdict + protocol.

Run:  python examples/advanced/cilium_hubble_flows.py
Prereq: bash setup.sh --step cilium
        Hubble Relay reachable (cilium hubble enable; cilium hubble port-forward).
"""
import json
import os
import subprocess
import sys
from collections import Counter

KUBECONFIG = os.environ.get("KUBECONFIG", os.path.expanduser("~/.kube/config"))
env = os.environ.copy()
env["KUBECONFIG"] = KUBECONFIG

try:
    proc = subprocess.run(
        ["hubble", "observe", "--output", "json", "--last", "100", "--follow=false"],
        check=True,
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
except FileNotFoundError:
    print("hubble CLI not on PATH; run scripts/setup/cilium.sh")
    sys.exit(0)
except subprocess.CalledProcessError as exc:
    msg = (exc.stderr or "").strip().splitlines()[-1] if exc.stderr else ""
    print(f"hubble observe failed ({exc.returncode}): {msg or 'relay unreachable?'}")
    sys.exit(0)
except subprocess.TimeoutExpired:
    print("hubble observe timed out; relay unreachable")
    sys.exit(0)

verdicts = Counter()
total = 0
parse_errs = 0
for line in proc.stdout.splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        evt = json.loads(line)
    except json.JSONDecodeError:
        parse_errs += 1
        continue
    flow = evt.get("flow") or evt
    verdict = flow.get("verdict") or "UNKNOWN"
    l4 = flow.get("l4") or {}
    proto = next(iter(l4.keys()), None) if isinstance(l4, dict) else None
    l7 = flow.get("l7") or {}
    l7_type = l7.get("type") if isinstance(l7, dict) else None
    proto_label = l7_type or proto or "L3"
    verdicts[(verdict, proto_label)] += 1
    total += 1

print(f"flows parsed: {total}  (json parse errors: {parse_errs})")
print("verdict      proto       count")
print("-" * 32)
for (verdict, proto), n in verdicts.most_common():
    print(f"{verdict:<12} {proto:<10}  {n}")
