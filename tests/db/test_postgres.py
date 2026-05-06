"""
PostgreSQL validation tests with dummy data.

Verifies:
  - Connectivity
  - Required extensions (pgvector, age, pg_trgm, uuid-ossp)
  - Demo schema and tables exist
  - Basic CRUD operations
  - JSON column storage/retrieval
  - Full-text trigram search
"""
import pytest
import psycopg2
from tests.conftest import DB_HOST, DB_PORT, DB_USER, DB_PASS, DB_NAME


# ── Connectivity ──────────────────────────────────────────────────────────────

def test_postgres_connects(pg_conn):
    """PostgreSQL server is reachable and accepting connections."""
    cur = pg_conn.cursor()
    cur.execute("SELECT version()")
    version = cur.fetchone()[0]
    assert "PostgreSQL" in version
    print(f"\n  version: {version.split(',')[0]}")


def test_postgres_version(pg_conn):
    """PostgreSQL version is 16 or above (required for AGE)."""
    cur = pg_conn.cursor()
    cur.execute("SHOW server_version")
    version = cur.fetchone()[0]
    major = int(version.split(".")[0])
    assert major >= 16, f"Expected PG >= 16, got {version}"


# ── Extensions ────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("ext", ["vector", "age", "pg_trgm", "uuid-ossp"])
def test_extension_loaded(pg_conn, ext):
    """Required PostgreSQL extension is present."""
    cur = pg_conn.cursor()
    cur.execute("SELECT extname FROM pg_extension WHERE extname = %s", (ext,))
    row = cur.fetchone()
    assert row is not None, f"Extension '{ext}' is not loaded — run init.sql"


# ── Schema + tables ───────────────────────────────────────────────────────────

def test_demo_schema_exists(pg_conn):
    """The 'demo' schema is present."""
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT schema_name FROM information_schema.schemata
        WHERE schema_name = 'demo'
    """)
    assert cur.fetchone() is not None, "Schema 'demo' not found — run init.sql"


@pytest.mark.parametrize("table", ["products", "documents", "events"])
def test_demo_table_exists(pg_conn, table):
    """Demo table exists in the 'demo' schema."""
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'demo' AND table_name = %s
    """, (table,))
    assert cur.fetchone() is not None, f"Table demo.{table} not found — run init.sql"


# ── Seeded data ───────────────────────────────────────────────────────────────

def test_dummy_products_seeded(pg_conn):
    """Dummy product rows are present from init.sql seed."""
    cur = pg_conn.cursor()
    cur.execute("SELECT COUNT(*) FROM demo.products")
    count = cur.fetchone()[0]
    assert count >= 5, f"Expected >= 5 products, got {count} — run init.sql"


def test_dummy_documents_seeded(pg_conn):
    """Dummy document rows are present from init.sql seed."""
    cur = pg_conn.cursor()
    cur.execute("SELECT COUNT(*) FROM demo.documents")
    count = cur.fetchone()[0]
    assert count >= 5, f"Expected >= 5 documents, got {count}"


def test_dummy_events_seeded(pg_conn):
    """Dummy event rows are present from init.sql seed."""
    cur = pg_conn.cursor()
    cur.execute("SELECT COUNT(*) FROM demo.events")
    count = cur.fetchone()[0]
    assert count >= 5, f"Expected >= 5 events, got {count}"


# ── CRUD operations with dummy data ───────────────────────────────────────────

def test_insert_and_select(pg_cursor):
    """Can insert and select a dummy row."""
    pg_cursor.execute("""
        INSERT INTO demo.products (name, category, description, price)
        VALUES ('Test Widget', 'test', 'Dummy product for pytest', 0.01)
        RETURNING id, name
    """)
    row = pg_cursor.fetchone()
    assert row is not None
    assert row[1] == 'Test Widget'


def test_update_dummy_row(pg_cursor):
    """Can update a dummy row."""
    pg_cursor.execute("""
        INSERT INTO demo.products (name, category, price)
        VALUES ('Old Name', 'test', 1.00)
        RETURNING id
    """)
    product_id = pg_cursor.fetchone()[0]

    pg_cursor.execute("""
        UPDATE demo.products SET name = 'New Name' WHERE id = %s RETURNING name
    """, (product_id,))
    updated = pg_cursor.fetchone()[0]
    assert updated == 'New Name'


def test_delete_dummy_row(pg_cursor):
    """Can delete a dummy row."""
    pg_cursor.execute("""
        INSERT INTO demo.products (name, category, price)
        VALUES ('To Delete', 'test', 1.00)
        RETURNING id
    """)
    product_id = pg_cursor.fetchone()[0]
    pg_cursor.execute("DELETE FROM demo.products WHERE id = %s", (product_id,))
    pg_cursor.execute("SELECT 1 FROM demo.products WHERE id = %s", (product_id,))
    assert pg_cursor.fetchone() is None


# ── JSONB ─────────────────────────────────────────────────────────────────────

def test_jsonb_payload_stored(pg_conn):
    """JSONB payloads in demo.events are queryable."""
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT payload->>'method' FROM demo.events
        WHERE source = 'api' AND event_type = 'request'
        LIMIT 1
    """)
    row = cur.fetchone()
    assert row is not None
    assert row[0] in ('GET', 'POST')


# ── Trigram search ────────────────────────────────────────────────────────────

def test_trigram_similarity_search(pg_conn):
    """Trigram similarity (pg_trgm) works on demo.documents."""
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT title, similarity(title, 'pgvector')
        FROM demo.documents
        WHERE title % 'pgvector'
        ORDER BY similarity(title, 'pgvector') DESC
        LIMIT 3
    """)
    rows = cur.fetchall()
    assert len(rows) >= 1, "Trigram search returned no results"
    assert rows[0][1] > 0.1, "Expected similarity > 0.1"


# ── UUID generation ───────────────────────────────────────────────────────────

def test_uuid_generation(pg_conn):
    """uuid_generate_v4() is available."""
    cur = pg_conn.cursor()
    cur.execute("SELECT uuid_generate_v4()")
    result = cur.fetchone()[0]
    assert result is not None
    assert len(str(result)) == 36  # standard UUID format
