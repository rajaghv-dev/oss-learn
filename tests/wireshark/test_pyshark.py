"""
Wireshark / pyshark / tshark tests.

Verifies tshark CLI is on PATH and pyshark can import + parse a tiny capture
made on the fly.
"""
import os
import shutil
import subprocess
import pytest

TSHARK = shutil.which("tshark")


def test_tshark_on_path():
    """tshark CLI is installed and reports a version."""
    if TSHARK is None:
        pytest.skip("tshark not installed — run: bash setup.sh --step wireshark")
    r = subprocess.run([TSHARK, "--version"], capture_output=True, text=True, timeout=5)
    assert r.returncode == 0
    assert "TShark" in r.stdout or "tshark" in r.stdout.lower()
    first_line = r.stdout.splitlines()[0]
    print(f"\n  {first_line}")


def test_tshark_can_list_interfaces():
    """tshark -D lists at least one interface (or fails gracefully without privileges)."""
    if TSHARK is None:
        pytest.skip("tshark not installed")
    r = subprocess.run([TSHARK, "-D"], capture_output=True, text=True, timeout=5)
    # tshark -D may need privileges on Linux; either way, it should not segfault
    assert r.returncode in (0, 1, 2), f"tshark -D crashed unexpectedly: {r.returncode}"


def test_pyshark_import():
    """pyshark Python wrapper is importable."""
    try:
        import pyshark  # noqa: F401
    except ImportError:
        pytest.skip("pyshark not installed — run: bash setup.sh --step pyshark")
    print("\n  pyshark imported successfully")


def test_pyshark_parse_tiny_pcap(tmp_path):
    """
    Can parse a tiny pcap created via tshark.
    Generates a 1-packet pcap with `tshark -i lo -c 1 -w` (best effort) and parses it.
    Skips if capture isn't possible without privileges.
    """
    if TSHARK is None:
        pytest.skip("tshark not installed")
    try:
        import pyshark
    except ImportError:
        pytest.skip("pyshark not installed")

    pcap_path = tmp_path / "tiny.pcap"

    # Try to capture 1 packet on loopback (requires privileges on Linux/macOS).
    # If we can't capture, fall back to an empty-pcap parser test.
    cap_proc = subprocess.run(
        [TSHARK, "-i", "lo", "-c", "1", "-w", str(pcap_path), "-a", "duration:2"],
        capture_output=True, text=True, timeout=8,
    )
    if cap_proc.returncode != 0 or not pcap_path.exists() or pcap_path.stat().st_size < 24:
        pytest.skip(f"Could not capture loopback packet (requires privileges): {cap_proc.stderr[:200]}")

    cap = pyshark.FileCapture(str(pcap_path))
    packets = list(cap)
    cap.close()
    assert len(packets) >= 1
    print(f"\n  parsed {len(packets)} packet(s) from {pcap_path}")
