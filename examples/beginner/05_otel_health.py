"""Hit the OTel Collector health_check extension and print the response.

Run:  python examples/beginner/05_otel_health.py
Prereq: bash start.sh   (OTel Collector health_check on localhost:13133)
"""
import os
import sys
import urllib.error
import urllib.request

PORT = os.environ.get("OTEL_HEALTH_PORT", "13133")
url = f"http://localhost:{PORT}/"

try:
    with urllib.request.urlopen(url, timeout=5) as resp:
        body = resp.read().decode("utf-8", errors="replace")
        status = resp.status
        ctype = resp.headers.get("Content-Type", "?")
except urllib.error.HTTPError as err:
    print(f"otel-collector returned HTTP {err.code}: {err.reason}")
    sys.exit(0)
except (urllib.error.URLError, ConnectionRefusedError) as err:
    print(f"otel-collector health unreachable at {url}: {err}")
    sys.exit(0)

print(f"endpoint:     {url}")
print(f"http:         {status}")
print(f"content-type: {ctype}")
print("body:")
print(body.strip() or "(empty body)")

if status == 200:
    print("otel-collector health_check OK")
else:
    print(f"otel-collector reported HTTP {status}")
