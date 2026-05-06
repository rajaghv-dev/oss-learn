"""Connect to OpenSearch and print cluster health.

Run:  python examples/beginner/opensearch_hello.py
Prereq: bash start.sh --opensearch   (OpenSearch on localhost:9200)
"""
import json
import os
import sys
import urllib.request
from urllib.error import URLError

OS_URL = os.environ.get("OPENSEARCH_URL", "http://localhost:9200")


def fetch(path):
    with urllib.request.urlopen(f"{OS_URL}{path}", timeout=5) as resp:
        return json.load(resp)


def main():
    try:
        health = fetch("/_cluster/health")
        root = fetch("/")
    except (URLError, ConnectionRefusedError) as exc:
        print(f"opensearch unreachable at {OS_URL}: {exc}")
        return 0

    print(f"cluster        : {root.get('cluster_name', '?')}")
    print(f"version        : {root.get('version', {}).get('number', '?')}")
    print(f"status         : {health['status']}")
    print(f"number_of_nodes: {health['number_of_nodes']}")
    print(f"active_shards  : {health['active_shards']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
