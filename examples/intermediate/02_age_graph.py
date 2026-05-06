"""Create a tiny graph in Apache AGE and query it with openCypher.

Run:  python examples/intermediate/02_age_graph.py
Prereq: bash start.sh   (Postgres + Apache AGE extension installed)
"""
import os
import psycopg2

DSN = os.environ.get("DATABASE_URL", "postgresql://oss:oss@localhost:5432/oss")
GRAPH = "demo_graph"

with psycopg2.connect(DSN) as conn, conn.cursor() as cur:
    cur.execute("CREATE EXTENSION IF NOT EXISTS age;")
    cur.execute("LOAD 'age';")
    cur.execute('SET search_path = ag_catalog, "$user", public;')

    cur.execute(
        "SELECT count(*) FROM ag_graph WHERE name = %s;", (GRAPH,)
    )
    if cur.fetchone()[0] == 0:
        cur.execute("SELECT create_graph(%s);", (GRAPH,))

    cur.execute(f"""
        SELECT * FROM cypher('{GRAPH}', $$
            MERGE (a:Person {{name:'Ada'}})
            MERGE (b:Person {{name:'Grace'}})
            MERGE (c:Person {{name:'Linus'}})
            MERGE (a)-[:KNOWS]->(b)
            MERGE (b)-[:KNOWS]->(c)
        $$) AS (v agtype);
    """)

    cur.execute(f"""
        SELECT * FROM cypher('{GRAPH}', $$
            MATCH (a:Person)-[:KNOWS*1..2]->(b:Person)
            RETURN a.name, b.name
        $$) AS (a agtype, b agtype);
    """)
    print("reachable pairs (within 2 hops):")
    for a, b in cur.fetchall():
        print(f"  {a} -> {b}")
