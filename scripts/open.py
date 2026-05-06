"""Probe every known oss-learn service port and open the running ones in a browser.

Usage:
    bash open.sh                # probe and open in browser
    bash open.sh --list          # probe only, don't open tabs
"""
import shutil
import socket
import subprocess
import sys
import webbrowser
from urllib.parse import urlparse

SERVICES = [
    ("Grafana",               "http://localhost:3000",             "admin / oss-admin"),
    ("Prometheus",            "http://localhost:9090",             "—"),
    ("Blackbox Exporter",     "http://localhost:9115",             "—"),
    ("OTel Collector health", "http://localhost:13133",            "—"),
    ("Local Docker Registry", "http://localhost:5000/v2/_catalog", "—"),
    ("Gitea",                 "http://localhost:3001",             "set on first visit"),
    ("Plane",                 "http://localhost:4000",             "admin@oss-learn.local / admin1234"),
    ("NocoBase",              "http://localhost:13000",            "admin@nocobase.com / admin1234"),
    ("OpenSearch",            "http://localhost:9200",             "—"),
    ("OpenSearch Dashboards", "http://localhost:5601",             "—"),
    ("Ollama",                "http://localhost:11434",            "—"),
    ("llama-server",          "http://localhost:8084",             "—"),
    ("pgAdmin (optional)",    "http://localhost:5050",             "admin@oss.local / admin"),
]


def is_listening(host: str, port: int, timeout: float = 0.5) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def open_url(url: str) -> bool:
    try:
        if webbrowser.open_new_tab(url):
            return True
    except webbrowser.Error:
        pass
    for cmd in (["wslview", url], ["cmd.exe", "/c", "start", url], ["xdg-open", url], ["open", url]):
        if shutil.which(cmd[0]):
            try:
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return True
            except OSError:
                continue
    return False


def main() -> int:
    list_only = any(a in sys.argv for a in ("--list", "--print", "-l"))

    name_w = max(len(s[0]) for s in SERVICES)
    url_w = max(len(s[1]) for s in SERVICES)
    header = f"  {'service':{name_w}}  {'url':{url_w}}  status  credentials"
    print(header)
    print("  " + "-" * (len(header) - 2))

    opened = down = failed = 0
    for name, url, creds in SERVICES:
        parsed = urlparse(url)
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        host = parsed.hostname or "localhost"

        if is_listening(host, port):
            if list_only:
                status = "open"
                opened += 1
            elif open_url(url):
                status = "opened"
                opened += 1
            else:
                status = "open*"
                failed += 1
        else:
            status = "down"
            down += 1
        print(f"  {name:{name_w}}  {url:{url_w}}  {status:6}  {creds}")

    print()
    summary = f"  {opened} opened, {down} not running"
    if failed:
        summary += f", {failed} could not launch a browser (open URL manually)"
    if list_only:
        summary += "  [--list: no tabs opened]"
    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
