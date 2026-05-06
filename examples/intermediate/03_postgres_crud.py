"""Exercise INSERT / SELECT / UPDATE / DELETE against demo.products with parameterised SQL.

Run:  python examples/intermediate/03_postgres_crud.py
Prereq: bash start.sh   (Postgres reachable; demo.products auto-created if absent)
"""
import os
import sys

import psycopg2

DSN = os.environ.get("DATABASE_URL", "postgresql://oss:oss@localhost:5432/oss")
TABLE = "demo.products"

ROWS = [
    ("crud-widget-a", 9.99),
    ("crud-widget-b", 14.50),
    ("crud-widget-c", 4.25),
]


def dump(cur, header):
    cur.execute(
        f"SELECT name, price FROM {TABLE} WHERE name LIKE 'crud-%%' ORDER BY name;"
    )
    print(f"\n-- {header} --")
    for name, price in cur.fetchall():
        print(f"  {name:18}  price={price}")


try:
    conn = psycopg2.connect(DSN)
except psycopg2.OperationalError as exc:
    print(f"postgres unreachable ({exc.__class__.__name__}); skipping")
    sys.exit(0)

with conn, conn.cursor() as cur:
    cur.execute("CREATE SCHEMA IF NOT EXISTS demo;")
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {TABLE} (
            id SERIAL PRIMARY KEY,
            name TEXT UNIQUE NOT NULL,
            price NUMERIC(10,2) NOT NULL
        );
    """)
    cur.execute(f"DELETE FROM {TABLE} WHERE name LIKE 'crud-%%';")

    for name, price in ROWS:
        cur.execute(
            f"INSERT INTO {TABLE} (name, price) VALUES (%s, %s);",
            (name, price),
        )
    dump(cur, "after INSERT")

    cur.execute(
        f"UPDATE {TABLE} SET price = %s WHERE name = %s;",
        (19.99, "crud-widget-a"),
    )
    dump(cur, "after UPDATE crud-widget-a -> 19.99")

    cur.execute(f"DELETE FROM {TABLE} WHERE name = %s;", ("crud-widget-c",))
    dump(cur, "after DELETE crud-widget-c")

conn.close()
