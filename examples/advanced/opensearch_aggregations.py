"""Run terms+avg and histogram aggregations over the products index.

Run:  python examples/advanced/opensearch_aggregations.py
Prereq: bash start.sh --opensearch   (OpenSearch on localhost:9200)
"""
import json
import os
import pathlib
import sys
import urllib.request
from urllib.error import URLError

OS_URL = os.environ.get("OPENSEARCH_URL", "http://localhost:9200")
INDEX = "products"
SAMPLE = pathlib.Path(__file__).resolve().parents[2] / "samples" / "products.json"


def req(method, path, body=None, ctype="application/json"):
    data = body.encode() if isinstance(body, str) else (json.dumps(body).encode() if body else None)
    r = urllib.request.Request(f"{OS_URL}{path}", data=data, method=method,
                               headers={"Content-Type": ctype})
    with urllib.request.urlopen(r, timeout=10) as resp:
        return json.load(resp)


def ensure_index():
    try:
        head = urllib.request.Request(f"{OS_URL}/{INDEX}", method="HEAD")
        with urllib.request.urlopen(head, timeout=5) as resp:
            if resp.status == 200:
                return
    except URLError:
        pass
    docs = json.loads(SAMPLE.read_text())
    lines = []
    for d in docs:
        lines.append(json.dumps({"index": {"_index": INDEX, "_id": d["sku"]}}))
        lines.append(json.dumps(d))
    req("POST", "/_bulk", body="\n".join(lines) + "\n", ctype="application/x-ndjson")
    req("POST", f"/{INDEX}/_refresh")


try:
    ensure_index()

    body_terms = {"size": 0, "aggs": {"by_cat": {"terms": {"field": "category.keyword"},
                  "aggs": {"avg_price": {"avg": {"field": "price"}}}}}}
    a = req("POST", f"/{INDEX}/_search", body=body_terms)
    print("category         count   avg_price")
    print("---------------  -----  ----------")
    for b in a["aggregations"]["by_cat"]["buckets"]:
        print(f"{b['key']:<15}  {b['doc_count']:>5}  ${b['avg_price']['value']:>8.2f}")

    body_hist = {"size": 0, "aggs": {"price_buckets":
                 {"histogram": {"field": "price", "interval": 50}}}}
    h = req("POST", f"/{INDEX}/_search", body=body_hist)
    print()
    print("price_bucket   count")
    print("------------  ------")
    for b in h["aggregations"]["price_buckets"]["buckets"]:
        lo = int(b["key"])
        print(f"${lo:>4}-${lo+49:<4}  {b['doc_count']:>5}")
except (URLError, ConnectionRefusedError) as exc:
    print(f"opensearch unreachable at {OS_URL}: {exc}")
    sys.exit(0)
