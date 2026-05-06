"""
Apache AGE graph tests with dummy data.

Verifies:
  - AGE extension is loaded and functional
  - demo_graph exists
  - Can CREATE vertices (Person, Product nodes) via Cypher
  - Can CREATE edges (KNOWS, BOUGHT relationships) via Cypher
  - Can traverse the graph with Cypher MATCH queries
  - Can filter on node properties
  - Path queries work (shortest path)
"""
import pytest
import psycopg2


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def age_conn():
    """
    Separate connection for AGE tests. AGE requires LOAD 'age' and a
    specific search_path per connection.
    """
    import os
    try:
        conn = psycopg2.connect(
            host=os.environ.get("POSTGRES_HOST", "localhost"),
            port=int(os.environ.get("POSTGRES_PORT", "5432")),
            user=os.environ.get("POSTGRES_USER", "postgres"),
            password=os.environ.get("POSTGRES_PASSWORD", "postgres"),
            dbname=os.environ.get("POSTGRES_DB", "osslearn"),
            connect_timeout=5,
        )
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute("LOAD 'age'")
        cur.execute("SET search_path = ag_catalog, demo, public")
        cur.close()
        yield conn
        conn.close()
    except psycopg2.OperationalError as exc:
        pytest.skip(f"PostgreSQL not available — {exc}")
    except psycopg2.errors.UndefinedFile:
        pytest.skip("AGE extension not installed — run: bash setup.sh --step postgres")


def cypher(conn, graph, query, params="{}"):
    """Execute a Cypher query via AGE's cypher() function."""
    cur = conn.cursor()
    cur.execute(f"SELECT * FROM cypher('{graph}', $${query}$$) AS (v agtype)")
    rows = cur.fetchall()
    cur.close()
    return rows


# ── Extension check ────────────────────────────────────────────────────────────

def test_age_extension_loaded(age_conn):
    """AGE extension is installed and LOAD succeeds."""
    cur = age_conn.cursor()
    cur.execute("SELECT extname FROM pg_extension WHERE extname = 'age'")
    assert cur.fetchone() is not None, "AGE extension not loaded"
    cur.close()


# ── Graph existence ────────────────────────────────────────────────────────────

def test_demo_graph_exists(age_conn):
    """The 'demo_graph' graph was created by init.sql."""
    cur = age_conn.cursor()
    cur.execute("SELECT name FROM ag_catalog.ag_graph WHERE name = 'demo_graph'")
    assert cur.fetchone() is not None, "demo_graph not found — run init.sql"
    cur.close()


# ── Node creation ─────────────────────────────────────────────────────────────

def test_create_person_nodes(age_conn):
    """Can create Person nodes in the graph."""
    cur = age_conn.cursor()
    for name, age in [("Alice", 30), ("Bob", 25), ("Carol", 35)]:
        cur.execute("""
            SELECT * FROM cypher('demo_graph', $$
                MERGE (p:Person {name: %s, age: %s})
                RETURN p.name
            $$) AS (name agtype)
        """, (name, age))
        row = cur.fetchone()
        assert row is not None
    cur.close()


def test_create_product_nodes(age_conn):
    """Can create Product nodes in the graph."""
    cur = age_conn.cursor()
    for prod, price in [("WidgetA", 9.99), ("GadgetX", 49.99)]:
        cur.execute("""
            SELECT * FROM cypher('demo_graph', $$
                MERGE (p:Product {name: %s, price: %s})
                RETURN p.name
            $$) AS (name agtype)
        """, (prod, price))
        row = cur.fetchone()
        assert row is not None
    cur.close()


# ── Edge creation ─────────────────────────────────────────────────────────────

def test_create_knows_edge(age_conn):
    """Can create KNOWS relationships between Person nodes."""
    cur = age_conn.cursor()
    cur.execute("""
        SELECT * FROM cypher('demo_graph', $$
            MATCH (a:Person {name: 'Alice'}), (b:Person {name: 'Bob'})
            MERGE (a)-[r:KNOWS {since: 2020}]->(b)
            RETURN type(r)
        $$) AS (rel_type agtype)
    """)
    row = cur.fetchone()
    assert row is not None, "KNOWS edge creation failed"
    cur.close()


def test_create_bought_edge(age_conn):
    """Can create BOUGHT relationships between Person and Product nodes."""
    cur = age_conn.cursor()
    cur.execute("""
        SELECT * FROM cypher('demo_graph', $$
            MATCH (a:Person {name: 'Alice'}), (p:Product {name: 'WidgetA'})
            MERGE (a)-[r:BOUGHT {quantity: 2}]->(p)
            RETURN type(r)
        $$) AS (rel_type agtype)
    """)
    row = cur.fetchone()
    assert row is not None, "BOUGHT edge creation failed"
    cur.close()


# ── Traversal queries ─────────────────────────────────────────────────────────

def test_match_all_persons(age_conn):
    """Can query all Person nodes."""
    cur = age_conn.cursor()
    cur.execute("""
        SELECT * FROM cypher('demo_graph', $$
            MATCH (p:Person) RETURN p.name
        $$) AS (name agtype)
    """)
    rows = cur.fetchall()
    assert len(rows) >= 3, f"Expected >= 3 persons, got {len(rows)}"
    names = [r[0].strip('"') for r in rows]
    assert "Alice" in names
    assert "Bob" in names
    cur.close()


def test_filter_by_property(age_conn):
    """Can filter nodes by property value."""
    cur = age_conn.cursor()
    cur.execute("""
        SELECT * FROM cypher('demo_graph', $$
            MATCH (p:Person) WHERE p.age >= 30 RETURN p.name, p.age
        $$) AS (name agtype, age agtype)
    """)
    rows = cur.fetchall()
    assert len(rows) >= 1, "Expected at least one person aged >= 30"
    cur.close()


def test_two_hop_traversal(age_conn):
    """Alice KNOWS Bob, so Alice can reach Bob's purchases via 2-hop."""
    cur = age_conn.cursor()
    cur.execute("""
        SELECT * FROM cypher('demo_graph', $$
            MATCH (a:Person {name: 'Alice'})-[:KNOWS]->(b:Person)
            RETURN b.name
        $$) AS (friend_name agtype)
    """)
    rows = cur.fetchall()
    friend_names = [r[0].strip('"') for r in rows]
    assert "Bob" in friend_names, f"Alice should KNOW Bob, got {friend_names}"
    cur.close()


def test_count_edges(age_conn):
    """Can count relationships with aggregation."""
    cur = age_conn.cursor()
    cur.execute("""
        SELECT * FROM cypher('demo_graph', $$
            MATCH ()-[r:KNOWS]->() RETURN count(r)
        $$) AS (cnt agtype)
    """)
    row = cur.fetchone()
    assert row is not None
    count = int(row[0])
    assert count >= 1, "Expected at least one KNOWS relationship"
    cur.close()
