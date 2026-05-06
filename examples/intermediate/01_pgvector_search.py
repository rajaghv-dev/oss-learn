"""Insert toy embeddings into pgvector and run a cosine-similarity search.

Run:  python examples/intermediate/01_pgvector_search.py
Prereq: bash start.sh   (Postgres + pgvector extension installed)
"""
import os
import random

import psycopg2
from psycopg2.extras import execute_values

DSN = os.environ.get("DATABASE_URL", "postgresql://oss:oss@localhost:5432/oss")
DIM = 8
random.seed(0)


def vec(seed):
    random.seed(seed)
    return [round(random.uniform(-1, 1), 4) for _ in range(DIM)]


with psycopg2.connect(DSN) as conn, conn.cursor() as cur:
    cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
    cur.execute("DROP TABLE IF EXISTS demo_items;")
    cur.execute(f"CREATE TABLE demo_items (id SERIAL PRIMARY KEY, label TEXT, embedding VECTOR({DIM}));")

    rows = [(f"item-{i}", vec(i)) for i in range(20)]
    execute_values(
        cur,
        "INSERT INTO demo_items (label, embedding) VALUES %s",
        [(label, str(emb)) for label, emb in rows],
    )

    query = vec(3)
    cur.execute(
        "SELECT label, embedding <=> %s::vector AS distance "
        "FROM demo_items ORDER BY distance ASC LIMIT 5;",
        (str(query),),
    )
    print(f"top 5 nearest to {rows[3][0]}:")
    for label, distance in cur.fetchall():
        print(f"  {label:10}  cosine_distance={distance:.4f}")
