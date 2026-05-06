"""Live capture on loopback with a BPF filter for tcp port 5432, while a chatter thread connects.

Run:  python examples/intermediate/wireshark_live_filter.py
Prereq: bash setup.sh --step wireshark
        Linux capture caps:  sudo setcap cap_net_raw,cap_net_admin+eip "$(which dumpcap)"
"""
import os
import socket
import subprocess
import sys
import threading
import time

INTERFACE = os.environ.get("CAPTURE_INTERFACE", "lo")
CAPTURE_DURATION = int(os.environ.get("CAPTURE_DURATION", "10"))
TARGET_HOST = "127.0.0.1"
TARGET_PORT = 5432


def chatter():
    time.sleep(0.5)
    deadline = time.time() + CAPTURE_DURATION
    while time.time() < deadline:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(0.5)
            s.connect((TARGET_HOST, TARGET_PORT))
            s.sendall(b"\x00\x00\x00\x08\x04\xd2\x16/")
            try:
                s.recv(64)
            except OSError:
                pass
            s.close()
        except OSError:
            pass
        time.sleep(0.4)


threading.Thread(target=chatter, daemon=True).start()

try:
    proc = subprocess.run(
        [
            "tshark",
            "-i", INTERFACE,
            "-a", f"duration:{CAPTURE_DURATION}",
            "-f", f"tcp port {TARGET_PORT}",
            "-l",
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=CAPTURE_DURATION + 5,
    )
except FileNotFoundError:
    print("tshark not on PATH; run scripts/setup/wireshark.sh")
    sys.exit(0)
except subprocess.CalledProcessError as exc:
    print(f"tshark failed ({exc.returncode}): {(exc.stderr or '').strip().splitlines()[-1] if exc.stderr else ''}")
    sys.exit(0)

lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
print(f"interface={INTERFACE} filter='tcp port {TARGET_PORT}' duration={CAPTURE_DURATION}s")
for ln in lines[:25]:
    print(f"  {ln}")
print(f"total packets matched: {len(lines)}")
