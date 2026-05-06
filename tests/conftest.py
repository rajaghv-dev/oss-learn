"""
Shared pytest fixtures for oss-learn tests.
All tests use dummy data — no real credentials required for local dev.
"""
import os
import pytest
import psycopg2

# ── Connection defaults ────────────────────────────────────────────────────
DB_HOST = os.environ.get("POSTGRES_HOST", "localhost")
DB_PORT = int(os.environ.get("POSTGRES_PORT", "5432"))
DB_USER = os.environ.get("POSTGRES_USER", "postgres")
DB_PASS = os.environ.get("POSTGRES_PASSWORD", "postgres")
DB_NAME = os.environ.get("POSTGRES_DB", "osslearn")

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
PROMETHEUS_URL = os.environ.get("PROMETHEUS_URL", "http://localhost:9090")
GRAFANA_URL = os.environ.get("GRAFANA_URL", "http://localhost:3000")
BLACKBOX_URL = os.environ.get("BLACKBOX_URL", "http://localhost:9115")


@pytest.fixture(scope="session")
def pg_conn():
    """Session-scoped PostgreSQL connection. Skips if server not available."""
    try:
        conn = psycopg2.connect(
            host=DB_HOST, port=DB_PORT,
            user=DB_USER, password=DB_PASS,
            dbname=DB_NAME, connect_timeout=5
        )
        conn.autocommit = True
        yield conn
        conn.close()
    except psycopg2.OperationalError as exc:
        pytest.skip(f"PostgreSQL not available at {DB_HOST}:{DB_PORT} — {exc}")


@pytest.fixture(scope="function")
def pg_cursor(pg_conn):
    """Function-scoped cursor; rolls back after each test to keep state clean."""
    pg_conn.autocommit = False
    cur = pg_conn.cursor()
    yield cur
    pg_conn.rollback()
    cur.close()
    pg_conn.autocommit = True
