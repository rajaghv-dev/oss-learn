"""Connect to the local Postgres and print server version.

Run:  python examples/beginner/01_postgres_hello.py
Prereq: bash start.sh   (Postgres on localhost:5432)
"""
import os
import psycopg2

DSN = os.environ.get(
    "DATABASE_URL",
    "postgresql://oss:oss@localhost:5432/oss",
)

with psycopg2.connect(DSN) as conn, conn.cursor() as cur:
    cur.execute("SELECT version(), current_database(), current_user;")
    version, db, user = cur.fetchone()
    print(f"connected as {user}@{db}")
    print(version)
