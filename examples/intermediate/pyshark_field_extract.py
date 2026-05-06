"""Extract TCP src/dst port pairs from a fixture pcap with pyshark and print top-10.

Run:  python examples/intermediate/pyshark_field_extract.py
Prereq: bash setup.sh --step wireshark
        bash setup.sh --step pyshark
"""
import os
import subprocess
import sys
import threading
import time
from collections import Counter

import pyshark

INTERFACE = os.environ.get("CAPTURE_INTERFACE", "lo")
CAPTURE_DURATION = int(os.environ.get("CAPTURE_DURATION", "10"))
PCAP = "/tmp/oss-learn.pcap"


def chatter():
    time.sleep(0.3)
    deadline = time.time() + CAPTURE_DURATION
    while time.time() < deadline:
        for port in (22, 80, 443, 5432, 6379, 9090):
            try:
                import socket
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(0.2)
                s.connect_ex(("127.0.0.1", port))
                s.close()
            except OSError:
                pass
        time.sleep(0.3)


threading.Thread(target=chatter, daemon=True).start()

try:
    subprocess.run(
        ["tshark", "-i", INTERFACE, "-a", f"duration:{CAPTURE_DURATION}", "-w", PCAP],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        timeout=CAPTURE_DURATION + 5,
    )
except FileNotFoundError:
    print("tshark not on PATH; run scripts/setup/wireshark.sh")
    sys.exit(0)
except subprocess.CalledProcessError as exc:
    print(f"tshark failed ({exc.returncode}): {(exc.stderr or b'').decode(errors='replace').strip().splitlines()[-1] if exc.stderr else ''}")
    sys.exit(0)

cap = pyshark.FileCapture(PCAP, keep_packets=False, display_filter="tcp")
pairs = Counter()
total = 0
for pkt in cap:
    tcp = getattr(pkt, "tcp", None)
    if tcp is None:
        continue
    try:
        src = int(tcp.srcport)
        dst = int(tcp.dstport)
    except (AttributeError, ValueError):
        continue
    pairs[(src, dst)] += 1
    total += 1
cap.close()

print(f"pcap={PCAP} tcp_packets={total} unique_pairs={len(pairs)}")
for (src, dst), n in pairs.most_common(10):
    print(f"  {src:>5} -> {dst:<5}  {n}")
