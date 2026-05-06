"""Capture loopback traffic with pyshark, then summarise per-protocol packet counts.

Run:  sudo python examples/advanced/03_pyshark_capture.py
Prereq: bash setup.sh --step wireshark
        bash setup.sh --step pyshark
        Linux capture caps:  sudo setcap cap_net_raw,cap_net_admin+eip "$(which dumpcap)"

Generates traffic in a child thread (HTTP GET to localhost:9090), captures for 5s,
and prints a protocol histogram.
"""
import http.client
import threading
import time
from collections import Counter

import pyshark

INTERFACE = "lo"
DURATION = 5
TARGET_HOST = "localhost"
TARGET_PORT = 9090


def chatter():
    time.sleep(0.5)
    for _ in range(10):
        try:
            c = http.client.HTTPConnection(TARGET_HOST, TARGET_PORT, timeout=1)
            c.request("GET", "/-/healthy")
            c.getresponse().read()
            c.close()
        except OSError:
            pass
        time.sleep(0.2)


threading.Thread(target=chatter, daemon=True).start()

cap = pyshark.LiveCapture(interface=INTERFACE, bpf_filter=f"tcp port {TARGET_PORT}")
proto_counts = Counter()
start = time.time()
for pkt in cap.sniff_continuously():
    proto_counts[pkt.highest_layer] += 1
    if time.time() - start > DURATION:
        break
cap.close()

print(f"captured on {INTERFACE} for {DURATION}s, port {TARGET_PORT}")
for proto, n in proto_counts.most_common():
    print(f"  {proto:8}  {n}")
