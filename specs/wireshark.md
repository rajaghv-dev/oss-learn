# Wireshark + tshark

> CLI packet capture and dissection for inspecting traffic on the wire.

| Field | Value |
|-------|-------|
| Category | networking / capture |
| Repo role | optional |
| Install script | scripts/setup/wireshark.sh |
| Validate suite | scripts/validate.sh --suite wireshark |
| Compose / config | — (host install; no containers, no config files) |
| Default port(s) | — (operates on local interfaces, not a network service) |
| Default credentials | — (capture privilege via `wireshark` group / dumpcap caps) |

## What it is
Wireshark is the canonical open-source network protocol analyser; `tshark` is
its CLI companion that reads from a live interface or a `.pcap` file and emits
dissected packets as text, JSON, or fields. oss-learn installs the CLI by
default and the GUI only when a desktop session is detected.

## Why it's in oss-learn
Packet-level visibility is the most direct way to teach what a protocol
actually puts on the wire, and `tshark` doubles as the binary backend for the
`pyshark` Python wrapper used by the test suite and example scripts.

## How this repo wires it up
- `scripts/setup/wireshark.sh` resolves the distro family from `/etc/os-release`
  (`ID` then `ID_LIKE`, mapping Ubuntu/Debian/RHEL derivatives like SuryaOS,
  Linux Mint, Pop!_OS, Kali, Rocky, AlmaLinux) and installs `tshark` +
  `wireshark-common` via apt or dnf.
- The `wireshark` GUI package is added only when `$DISPLAY` or
  `$WAYLAND_DISPLAY` is set; it is skipped entirely with `--cli-only` and on
  headless hosts to avoid pulling Qt and a few hundred MB of GUI deps.
- Pre-seeds the `wireshark-common/install-setuid` debconf question to `true`
  so the apt install is non-interactive and `dumpcap` ends up with the
  `CAP_NET_RAW` / `CAP_NET_ADMIN` file capabilities needed for non-root
  capture (owner `root:wireshark`, mode `0750`).
- Adds `$USER` to the `wireshark` group (same membership model as the `docker`
  group); the change takes effect on next login or via `newgrp wireshark`.
- On `--force` re-runs, runs `dpkg-reconfigure -f noninteractive
  wireshark-common` to re-apply the dumpcap caps in case the debconf seed
  missed the original package configure.
- Verifies `tshark --version` parses and `tshark -D` enumerates interfaces;
  a failing `-D` is downgraded to a warning because it usually just means the
  group membership has not been picked up yet (logout/login required).
- Writes a manifest at `setup/state/installs/wireshark.yaml` recording
  binary path, version, family, and package set; the next-step pointer in
  the pass log nudges the user toward `scripts/setup/pyshark.sh`.

## Key concepts
- **tshark vs wireshark** — `tshark` is the headless CLI used by oss-learn;
  `wireshark` is the Qt GUI, installed only on desktop hosts.
- **dumpcap** — the small privileged helper that actually opens raw sockets;
  `tshark` execs it so the main analyser can run unprivileged.
- **wireshark group** — owns `dumpcap` (mode `0750`) so non-root members can
  capture without `sudo`.
- **Display filter vs capture filter** — capture filters (BPF) decide what
  hits disk; display filters (Wireshark syntax) decide what you see after.
- **pcap / pcapng** — the on-disk capture formats `tshark -w` writes and
  `pyshark.FileCapture` reads; pcapng is the modern default and carries
  per-interface metadata that flat pcap cannot.
- **Distro family resolution** — only `ubuntu`, `debian`, `rhel`, `fedora`
  ship signed packages; derivatives (Pop!_OS, Mint, Rocky, AlmaLinux, …) are
  mapped to a parent family via `ID_LIKE` so the same install path works.

## Quick verification
```bash
tshark --version | head -1 && tshark -D
```
Prints the installed `tshark` version and lists the capture interfaces visible
to the current user.

## Suggested example progression
- **Beginner** — `examples/beginner/wireshark_pcap_read.py` — read a sample pcap with `tshark -r` and count packets *(planned)*
- **Intermediate** — `examples/intermediate/wireshark_live_filter.py` — capture on `lo` with a BPF filter for `tcp port 5432` *(planned)*
- **Advanced** — `examples/advanced/03_pyshark_capture.py` — loopback capture + protocol histogram *(existing)*

## References
- Docs: https://www.wireshark.org/docs/
- Source: https://gitlab.com/wireshark/wireshark
