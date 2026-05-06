"""Capture a tiny pcap on loopback with tshark, then re-read it and summarise.

Run:  python examples/beginner/wireshark_pcap_read.py
Prereq: bash setup.sh --step wireshark
        Linux capture caps:  sudo setcap cap_net_raw,cap_net_admin+eip "$(which dumpcap)"
"""
import os
import subprocess
import sys
import threading
import time
import urllib.request

INTERFACE = os.environ.get("CAPTURE_INTERFACE", "lo")
DURATION = int(os.environ.get("CAPTURE_DURATION", "5"))
PCAP = "/tmp/oss-learn.pcap"


def chatter():
    time.sleep(0.3)
    for _ in range(8):
        try:
            urllib.request.urlopen("http://localhost:80/", timeout=0.5).read()
        except OSError:
            pass
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
    result = subprocess.run(
        ["tshark", "-r", PCAP],
        check=True,
        capture_output=True,
        text=True,
    )
except FileNotFoundError:
    print("tshark not on PATH; run scripts/setup/wireshark.sh")
    sys.exit(0)
except subprocess.CalledProcessError as exc:
    print(f"tshark failed ({exc.returncode}): {exc.stderr.decode(errors='replace').strip().splitlines()[-1] if exc.stderr else ''}")
    sys.exit(0)

lines = [ln for ln in result.stdout.splitlines() if ln.strip()]
print(f"pcap: {PCAP}")
for ln in lines[:10]:
    print(f"  {ln}")
print(f"total packets: {len(lines)}")
