"""Insert a handful of fixed 4-d vectors into pgvector and run a cosine top-3 query.

Run:  python examples/beginner/02_pgvector_hello.py
Prereq: bash start.sh   (Postgres + pgvector extension installed)
"""
import os
import sys

import psycopg2

DSN = os.environ.get("DATABASE_URL", "postgresql://oss:oss@localhost:5432/oss")
DIM = 4

ITEMS = [
    ("apple",  [1.0, 0.0, 0.0, 0.0]),
    ("pear",   [0.9, 0.1, 0.0, 0.0]),
    ("car",    [0.0, 1.0, 0.0, 0.0]),
    ("truck",  [0.0, 0.9, 0.1, 0.0]),
    ("cloud",  [0.0, 0.0, 1.0, 0.0]),
]
PROBE = [1.0, 0.05, 0.0, 0.0]

try:
    conn = psycopg2.connect(DSN)
except psycopg2.OperationalError as exc:
    print(f"postgres unreachable ({exc.__class__.__name__}); skipping")
    sys.exit(0)

with conn, conn.cursor() as cur:
    cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
    cur.execute("DROP TABLE IF EXISTS pgv_hello;")
    cur.execute(
        f"CREATE TABLE pgv_hello (id SERIAL PRIMARY KEY, label TEXT, embedding VECTOR({DIM}));"
    )

    for label, emb in ITEMS:
        cur.execute(
            "INSERT INTO pgv_hello (label, embedding) VALUES (%s, %s::vector);",
            (label, str(emb)),
        )

    cur.execute(
        "SELECT label, embedding <=> %s::vector AS distance "
        "FROM pgv_hello ORDER BY distance ASC LIMIT 3;",
        (str(PROBE),),
    )
    print(f"top 3 nearest to probe {PROBE}:")
    for label, distance in cur.fetchall():
        print(f"  {label:8}  cosine_distance={distance:.4f}")

conn.close()
