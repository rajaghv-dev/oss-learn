"""Variable-length Cypher path query in Apache AGE (no built-in shortestPath needed).

Run:  python examples/advanced/02_age_pathfinding.py
Prereq: bash start.sh   (Postgres + Apache AGE extension installed)
"""
import os
import sys

import psycopg2

DSN = os.environ.get("DATABASE_URL", "postgresql://oss:oss@localhost:5432/oss")
GRAPH = "path_graph"

NODES = ["Ada", "Grace", "Linus", "Hedy", "Alan", "Edsger", "Donald"]
EDGES = [
    ("Ada", "Grace"),
    ("Grace", "Linus"),
    ("Linus", "Hedy"),
    ("Hedy", "Alan"),
    ("Grace", "Edsger"),
    ("Edsger", "Donald"),
    ("Ada", "Alan"),
]
START, END = "Ada", "Donald"

try:
    conn = psycopg2.connect(DSN)
except psycopg2.OperationalError as exc:
    print(f"postgres unreachable ({exc.__class__.__name__}); skipping")
    sys.exit(0)

with conn, conn.cursor() as cur:
    cur.execute("CREATE EXTENSION IF NOT EXISTS age;")
    cur.execute("LOAD 'age';")
    cur.execute('SET search_path = ag_catalog, "$user", public;')

    cur.execute("SELECT count(*) FROM ag_graph WHERE name = %s;", (GRAPH,))
    if cur.fetchone()[0] == 0:
        cur.execute("SELECT create_graph(%s);", (GRAPH,))

    for n in NODES:
        cur.execute(f"""
            SELECT * FROM cypher('{GRAPH}', $$
                MERGE (:Person {{name:'{n}'}})
            $$) AS (v agtype);
        """)
    for a, b in EDGES:
        cur.execute(f"""
            SELECT * FROM cypher('{GRAPH}', $$
                MATCH (a:Person {{name:'{a}'}}), (b:Person {{name:'{b}'}})
                MERGE (a)-[:KNOWS]->(b)
            $$) AS (v agtype);
        """)

    cur.execute(f"""
        SELECT length(p), p FROM cypher('{GRAPH}', $$
            MATCH p = (a:Person {{name:'{START}'}})-[:KNOWS*1..5]->(b:Person {{name:'{END}'}})
            RETURN length(p) AS len, p
            ORDER BY len ASC
            LIMIT 1
        $$) AS (len agtype, p agtype);
    """)
    row = cur.fetchone()
    if row is None:
        print(f"no path {START} -> {END} within 5 hops")
    else:
        length, path = row
        print(f"shortest KNOWS path {START} -> {END}: length={length}")
        print(f"  path agtype: {path}")
