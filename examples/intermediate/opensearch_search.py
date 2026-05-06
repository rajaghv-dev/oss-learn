"""Bulk-index products, then run match and range queries.

Run:  python examples/intermediate/opensearch_search.py
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


def bulk_index(docs):
    lines = []
    for d in docs:
        lines.append(json.dumps({"index": {"_index": INDEX, "_id": d["sku"]}}))
        lines.append(json.dumps(d))
    body = "\n".join(lines) + "\n"
    return req("POST", "/_bulk", body=body, ctype="application/x-ndjson")


def search(query):
    return req("POST", f"/{INDEX}/_search", body={"query": query})


try:
    docs = json.loads(SAMPLE.read_text())
    try:
        req("DELETE", f"/{INDEX}")
    except URLError:
        pass
    res = bulk_index(docs)
    if res.get("errors"):
        print("bulk had errors")
        sys.exit(0)
    req("POST", f"/{INDEX}/_refresh")

    m = search({"match": {"category": "books"}})
    print(f"match category=books -> {m['hits']['total']['value']} hits")
    for h in m["hits"]["hits"]:
        print(f"  {h['_source']['sku']:7} {h['_source']['name']}")

    r = search({"range": {"price": {"lt": 100}}})
    print(f"range price<100      -> {r['hits']['total']['value']} hits")
    for h in r["hits"]["hits"]:
        print(f"  {h['_source']['sku']:7} {h['_source']['name']}  ${h['_source']['price']}")
except (URLError, ConnectionRefusedError) as exc:
    print(f"opensearch unreachable at {OS_URL}: {exc}")
    sys.exit(0)
