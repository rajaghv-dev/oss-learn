"""Load Apache AGE, create a tiny KNOWS graph, and read it back via Cypher.

Run:  python examples/beginner/03_age_hello.py
Prereq: bash start.sh   (Postgres + Apache AGE extension installed)
"""
import os
import sys

import psycopg2

DSN = os.environ.get("DATABASE_URL", "postgresql://oss:oss@localhost:5432/oss")
GRAPH = "hello_graph"

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

    cur.execute(f"""
        SELECT * FROM cypher('{GRAPH}', $$
            MERGE (a:Person {{name:'Ada'}})
            MERGE (b:Person {{name:'Grace'}})
            MERGE (a)-[:KNOWS]->(b)
        $$) AS (v agtype);
    """)

    cur.execute(f"""
        SELECT * FROM cypher('{GRAPH}', $$
            MATCH (a:Person)-[:KNOWS]->(b:Person)
            RETURN a.name, b.name
        $$) AS (a agtype, b agtype);
    """)
    print(f"KNOWS edges in {GRAPH}:")
    for a, b in cur.fetchall():
        print(f"  {a} -> {b}")

conn.close()
