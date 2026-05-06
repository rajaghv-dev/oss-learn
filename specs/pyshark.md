# pyshark

> Python wrapper around tshark for programmatic capture and dissection.

| Field | Value |
|-------|-------|
| Category | networking / capture |
| Repo role | optional |
| Install script | scripts/setup/pyshark.sh |
| Validate suite | scripts/validate.sh --suite wireshark |
| Compose / config | — (pip package in shared venv; no config) |
| Default port(s) | — (in-process library, no listener) |
| Default credentials | — (inherits tshark's `wireshark` group / dumpcap caps) |
| Resource footprint | pip wheel ~200 KB; runtime spawns a `tshark` subprocess so peak RAM tracks tshark, not Python |

## What it is
`pyshark` is a Python library that shells out to `tshark` and yields parsed
packet objects with attribute access into every dissected layer. It does not
re-implement protocol parsing — it streams `tshark`'s PDML/JSON output and
wraps it, so it sees exactly what Wireshark sees.

## Why it's in oss-learn
It lets tests and example scripts assert on packet-level behaviour from
Python without writing custom dissectors, and gives learners an idiomatic way
to script captures alongside the rest of the stack's Python code.

## How this repo wires it up
- `scripts/setup/pyshark.sh` runs only after `python.sh` (which creates the
  shared venv at `$REPO_ROOT/venv/`) and `wireshark.sh` (which puts `tshark`
  on `PATH`); it bails with explicit pointers to those scripts if either is
  missing rather than silently installing into system Python.
- Installs `pyshark>=0.6` via the venv's `pip` (lower bound covers the
  asyncio refactor); the upper bound is left open so security fixes can land,
  and runtime deps `lxml` + `termcolor` + `packaging` are pulled in
  transitively.
- Two-stage verification: first an `import pyshark` under the venv Python to
  prove the wheel and the lxml binary wheel are both sound; then a
  `pyshark.FileCapture` instantiation against a throwaway empty pcap to prove
  the `tshark` subprocess spawn path works. Benign empty-pcap exceptions are
  tolerated — only a "tshark not found" / "no such" error message fails the
  step, since that is the one thing this install is responsible for.
- `--force` adds `--force-reinstall` to the pip invocation; `--check` reports
  presence without touching pip; re-runs always rerun verification + manifest
  write so the step converges on green.
- Writes `setup/state/installs/pyshark.yaml` recording pyshark version,
  venv path, Python version, and the resolved tshark binary + version.
- `tests/wireshark/` (referenced from `README.md`) and the existing
  `examples/advanced/03_pyshark_capture.py` both consume this install.

## Key concepts
- **FileCapture** — iterates packets from an on-disk `.pcap` / `.pcapng`;
  the workhorse for replaying fixtures in tests.
- **LiveCapture** — captures from a live interface; needs the same
  privileges as `tshark` itself (group membership or caps).
- **Lazy layer access** — packets expose layers as attributes
  (`pkt.tcp.srcport`, `pkt.ip.dst`); field names mirror Wireshark's display
  filters, so a working filter expression usually maps 1:1 to attribute
  access.
- **keep_packets** — when `False`, packets are discarded after iteration to
  bound memory on long captures.
- **tshark backend** — every capture spawns a `tshark` subprocess, so this
  package is unusable without the binary on `PATH`; setup verifies the spawn
  path explicitly rather than just the import.
- **Asyncio event loop** — `LiveCapture` runs on an asyncio loop under the
  hood; `>=0.6` is pinned because earlier releases predate that refactor and
  leak file descriptors on `apply_on_packets`.

## Quick verification
```bash
./venv/bin/python -c 'import pyshark; print(pyshark.__version__)'
```
Imports `pyshark` from the shared venv and prints its version, confirming
both the wheel install and the lxml runtime dep are healthy.

## Common pitfalls
- **tshark must be on PATH** — pyshark is a thin wrapper, not a parser; if
  `tshark` is missing or shadowed by a non-functional binary you'll get a
  cryptic `FileNotFoundError` deep inside an asyncio task, not a useful
  import-time error. The setup script's second-stage check (instantiating
  a `FileCapture` against an empty pcap) exists precisely because a clean
  import is not enough proof the subprocess spawn path works.
- **asyncio loop clash in event-loop-using apps** — pyshark's `LiveCapture`
  runs its own asyncio loop; embedding it inside an app that already owns
  a loop (FastAPI, Jupyter, pytest-asyncio, anything under uvicorn) needs
  explicit loop handoff (`use_json=True` + manual loop wiring) or you get
  "RuntimeError: This event loop is already running".
- **Loopback live capture needs the same caps as wireshark** —
  `LiveCapture(interface='lo')` shells out to the same `dumpcap` as the CLI,
  so it needs the `wireshark` group + `CAP_NET_RAW` / `CAP_NET_ADMIN` on
  `dumpcap`; the import succeeding tells you nothing about whether capture
  will actually work. Run `tshark -D` first to confirm.
- **lxml binary wheel availability** — pyshark pulls in `lxml`; on uncommon
  Python/glibc combos pip may try to source-build it, so the venv must
  satisfy lxml's build deps (libxml2-dev, libxslt-dev) if no wheel is
  published for that interpreter.
- **keep_packets=True default** — long live captures will OOM unless you
  set `keep_packets=False` or process+discard each packet inside the
  iterator; the default keeps every packet in memory for later replay.
- **Layer attribute names mirror display filters, not Python idioms** —
  `pkt.tcp.srcport` works because Wireshark's display-filter language uses
  `tcp.srcport`; fields with dots in the original (`http.request.uri`)
  become nested attribute access. When in doubt, open the same packet in
  the Wireshark GUI and copy the field name from the Packet Details pane.
- **`use_json=True` vs PDML** — JSON output is faster and more compact but
  loses some dissector richness PDML carries; tests that assert on exotic
  L7 fields may need to flip back to PDML.

## Related specs
- [wireshark](wireshark.md) — the `tshark` CLI this library wraps; install
  it first or pyshark setup hard-fails with an explicit pointer back to
  `scripts/setup/wireshark.sh`. Group / dumpcap caps live there too,
  shared across both tools.
- [python](python.md) — the shared venv at `$REPO_ROOT/venv/` is the only
  supported install target; pyshark setup refuses to install into system
  Python and hard-fails with a pointer to `scripts/setup/python.sh`. All
  pyshark example scripts assume `./venv/bin/python` as the interpreter.
- [postgres](postgres.md) — the canonical "loopback `tcp port 5432`"
  capture target used in the intermediate progression; running pyshark
  against a known-protocol service is the easiest way to sanity-check a
  live-capture script before pointing it at production-shaped traffic.

## Suggested example progression
- **Beginner** — `examples/beginner/pyshark_read_pcap.py` — open a fixture pcap and print summary lines *(existing)*
- **Intermediate** — `examples/intermediate/pyshark_field_extract.py` — extract TCP `srcport`/`dstport` pairs from a capture *(existing)*
- **Advanced** — `examples/advanced/03_pyshark_capture.py` — loopback capture + protocol histogram *(existing)*

## References
- Docs: https://kiminewt.github.io/pyshark/
- Source: https://github.com/KimiNewt/pyshark
- PyPI: https://pypi.org/project/pyshark/
- tshark man page (the underlying CLI): https://www.wireshark.org/docs/man-pages/tshark.html
