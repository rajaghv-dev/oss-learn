"""Generate a fixture pcap with tshark, then open it with pyshark.FileCapture and print 10 packets.

Run:  python examples/beginner/pyshark_read_pcap.py
Prereq: bash setup.sh --step wireshark
        bash setup.sh --step pyshark
"""
import os
import subprocess
import sys
import threading
import time

import pyshark

INTERFACE = os.environ.get("CAPTURE_INTERFACE", "lo")
DURATION = int(os.environ.get("CAPTURE_DURATION", "5"))
PCAP = "/tmp/oss-learn.pcap"


def chatter():
    time.sleep(0.3)
    for _ in range(8):
        try:
            subprocess.run(
                ["ping", "-c", "1", "-W", "1", "127.0.0.1"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        except FileNotFoundError:
            pass
        time.sleep(0.2)


threading.Thread(target=chatter, daemon=True).start()

try:
    subprocess.run(
        ["tshark", "-i", INTERFACE, "-a", f"duration:{DURATION}", "-w", PCAP],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        timeout=DURATION + 5,
    )
except FileNotFoundError:
    print("tshark not on PATH; run scripts/setup/wireshark.sh")
    sys.exit(0)
except subprocess.CalledProcessError as exc:
    print(f"tshark failed ({exc.returncode}): {(exc.stderr or b'').decode(errors='replace').strip().splitlines()[-1] if exc.stderr else ''}")
    sys.exit(0)

cap = pyshark.FileCapture(PCAP, keep_packets=False)
print(f"pcap: {PCAP}")
shown = 0
for pkt in cap:
    if shown >= 10:
        break
    src = getattr(getattr(pkt, "ip", None), "src", None) or getattr(getattr(pkt, "ipv6", None), "src", "?")
    dst = getattr(getattr(pkt, "ip", None), "dst", None) or getattr(getattr(pkt, "ipv6", None), "dst", "?")
    print(f"  t={pkt.sniff_time.isoformat()}  {src} -> {dst}  {pkt.highest_layer}")
    shown += 1
cap.close()
print(f"shown: {shown}")
