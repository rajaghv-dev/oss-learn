#!/usr/bin/env python3
"""
setup-state-exporter — exposes oss-learn setup/state/*.done stamps as Prometheus metrics.

Metrics:
  oss_setup_step_done{step="postgres"}          1 if done, 0 if not
  oss_setup_step_timestamp_seconds{step="..."}  Unix time the step completed (0 if not done)
  oss_setup_steps_total                         total steps defined
  oss_setup_steps_done_total                    count of completed steps
  oss_setup_complete                            1 if all setup steps have completed
  oss_validation_suite_status{suite="..."}      1=pass 0=fail 2=running -1=pending

Run:  python3 infra/observability/setup-state-exporter.py
Port: 9901
"""
from __future__ import annotations
import os
import pathlib
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

_default_state = pathlib.Path(__file__).parent.parent.parent / "setup" / "state"
STATE_DIR = pathlib.Path(os.environ.get("OSS_STATE_DIR", str(_default_state)))
PORT = int(os.environ.get("PORT", 9901))

# oss-learn setup steps (matches scripts/setup/main.sh STEPS)
SETUP_STEPS = [
    "preflight",
    "docker",
    "python",
    "postgres",
    "openvino",
    "onnxruntime",
    "ollama",
    "llama_cpp",
    "registry",
    "observability",
    "opensearch",
    "git",
    "plane",
    "nocobase",
    "wireshark",
    "k8s",
]


def _stamp_mtime(stem: str) -> float:
    p = STATE_DIR / f"{stem}.done"
    try:
        return p.stat().st_mtime if p.exists() else 0.0
    except OSError:
        return 0.0


def _is_done(stem: str) -> int:
    return 1 if (STATE_DIR / f"{stem}.done").exists() else 0


def generate_metrics() -> str:
    lines: list[str] = []
    now = time.time()

    # ── Setup steps ──────────────────────────────────────────────────────────
    lines += [
        "# HELP oss_setup_step_done 1 if the setup step completed successfully",
        "# TYPE oss_setup_step_done gauge",
    ]
    done_count = 0
    for step in SETUP_STEPS:
        v = _is_done(f"step_{step}")
        done_count += v
        lines.append(f'oss_setup_step_done{{step="{step}"}} {v}')

    lines += [
        "# HELP oss_setup_step_timestamp_seconds Unix timestamp when step completed (0=not done)",
        "# TYPE oss_setup_step_timestamp_seconds gauge",
    ]
    for step in SETUP_STEPS:
        ts = _stamp_mtime(f"step_{step}")
        lines.append(f'oss_setup_step_timestamp_seconds{{step="{step}"}} {ts:.0f}')

    lines += [
        "# HELP oss_setup_steps_total Total number of setup steps",
        "# TYPE oss_setup_steps_total gauge",
        f"oss_setup_steps_total {len(SETUP_STEPS)}",
        "# HELP oss_setup_steps_done_total Number of completed setup steps",
        "# TYPE oss_setup_steps_done_total gauge",
        f"oss_setup_steps_done_total {done_count}",
        "# HELP oss_setup_complete 1 if all setup steps have completed",
        "# TYPE oss_setup_complete gauge",
        f"oss_setup_complete {1 if done_count == len(SETUP_STEPS) else 0}",
    ]

    # ── Live validation results (written by validate.sh) ────────────────────
    val_file = STATE_DIR / "validation-live.json"
    if val_file.exists():
        try:
            import json as _json
            with open(val_file) as f:
                val = _json.load(f)
            suites = val.get("suites", {})
            _STATUS = {"pass": 1, "fail": 0, "running": 2, "pending": -1}
            lines += [
                "# HELP oss_validation_running 1 while validate.sh is executing",
                "# TYPE oss_validation_running gauge",
                f"oss_validation_running {val.get('running', 0)}",
                "# HELP oss_validation_started_timestamp Unix time validate.sh began",
                "# TYPE oss_validation_started_timestamp gauge",
                f"oss_validation_started_timestamp {val.get('started', 0)}",
                "# HELP oss_validation_completed_timestamp Unix time validate.sh finished (0=not done)",
                "# TYPE oss_validation_completed_timestamp gauge",
                f"oss_validation_completed_timestamp {val.get('completed', 0)}",
                "# HELP oss_validation_suite_status Suite status: 1=pass 0=fail 2=running -1=pending",
                "# TYPE oss_validation_suite_status gauge",
            ]
            for suite, data in suites.items():
                status_str = data.get("status", "pending")
                status_val = _STATUS.get(status_str, -1)
                lines.append(f'oss_validation_suite_status{{suite="{suite}"}} {status_val}')
        except Exception:
            pass  # stale/corrupt JSON — silently skip

    # ── Exporter self-metrics ─────────────────────────────────────────────────
    lines += [
        "# HELP oss_state_exporter_scrape_time_seconds Time taken to generate metrics",
        "# TYPE oss_state_exporter_scrape_time_seconds gauge",
        f"oss_state_exporter_scrape_time_seconds {time.time() - now:.4f}",
        "# HELP oss_state_exporter_up 1 = exporter is running",
        "# TYPE oss_state_exporter_up gauge",
        "oss_state_exporter_up 1",
    ]

    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/metrics", "/"):
            self.send_response(404); self.end_headers(); return
        body = generate_metrics().encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # silence access log


if __name__ == "__main__":
    print(f"setup-state-exporter listening on :{PORT}  (state={STATE_DIR})")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
