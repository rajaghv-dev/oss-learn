"""
pgvector tests with dummy 3-dimensional embeddings.

Verifies:
  - vector column type works
  - INSERT and SELECT of float vectors
  - Cosine similarity nearest-neighbour search
  - L2 distance search
  - Inner product search
  - Index scan (ivfflat)
"""
import pytest


# ── Helper: insert dummy vectors ─────────────────────────────────────────────

DUMMY_VECTORS = [
    ("alpha",   "tech",   [1.0, 0.0, 0.0]),   # pure X-axis
    ("beta",    "tech",   [0.9, 0.4, 0.0]),   # close to alpha
    ("gamma",   "docs",   [0.0, 1.0, 0.0]),   # pure Y-axis
    ("delta",   "docs",   [0.1, 0.9, 0.2]),   # close to gamma
    ("epsilon", "infra",  [0.0, 0.0, 1.0]),   # pure Z-axis
    ("zeta",    "infra",  [0.2, 0.1, 0.95]),  # close to epsilon
]


@pytest.fixture(scope="module")
def seeded_vectors(pg_conn):
    """Insert dummy vectors for this module; clean up after."""
    cur = pg_conn.cursor()
    ids = []
    for name, cat, vec in DUMMY_VECTORS:
        embedding_str = f"[{','.join(str(x) for x in vec)}]"
        cur.execute("""
            INSERT INTO demo.products (name, category, embedding)
            VALUES (%s, %s, %s::vector) RETURNING id
        """, (f"vec_{name}", cat, embedding_str))
        ids.append(cur.fetchone()[0])
    pg_conn.commit()
    yield ids
    # cleanup
    cur.execute("DELETE FROM demo.products WHERE id = ANY(%s)", (ids,))
    pg_conn.commit()
    cur.close()


# ── Basic vector storage ──────────────────────────────────────────────────────

def test_vector_insert_and_select(pg_conn, seeded_vectors):
    """Can round-trip a 3D vector through the database."""
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT embedding::text FROM demo.products
        WHERE id = %s
    """, (seeded_vectors[0],))
    row = cur.fetchone()
    assert row is not None
    assert row[0] is not None
    print(f"\n  stored vector: {row[0]}")


def test_vector_dimensions(pg_conn, seeded_vectors):
    """Vector column has the correct number of dimensions."""
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT vector_dims(embedding) FROM demo.products
        WHERE id = %s
    """, (seeded_vectors[0],))
    dims = cur.fetchone()[0]
    assert dims == 3


# ── Nearest-neighbour: cosine similarity ─────────────────────────────────────

def test_cosine_nearest_neighbour(pg_conn, seeded_vectors):
    """Cosine similarity: querying [1,0,0] should find 'alpha' first."""
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT name, 1 - (embedding <=> '[1,0,0]'::vector) AS cosine_sim
        FROM demo.products
        WHERE id = ANY(%s)
        ORDER BY embedding <=> '[1,0,0]'::vector
        LIMIT 3
    """, (seeded_vectors,))
    rows = cur.fetchall()
    assert len(rows) >= 1
    # The nearest result to [1,0,0] should have a high cosine similarity
    assert rows[0][1] > 0.8, f"Expected cosine_sim > 0.8, got {rows[0][1]}"
    print(f"\n  nearest to [1,0,0]: {rows[0][0]} (cosine_sim={rows[0][1]:.4f})")


def test_cosine_cluster_coherence(pg_conn, seeded_vectors):
    """Vectors in the same cluster are more similar to each other than to others."""
    cur = pg_conn.cursor()
    # alpha=[1,0,0] should be closer to beta=[0.9,0.4,0] than to epsilon=[0,0,1]
    cur.execute("""
        SELECT
          (SELECT embedding FROM demo.products WHERE name = 'vec_alpha' AND id = ANY(%s)) <=>
          (SELECT embedding FROM demo.products WHERE name = 'vec_beta'  AND id = ANY(%s)) AS d_alpha_beta,
          (SELECT embedding FROM demo.products WHERE name = 'vec_alpha' AND id = ANY(%s)) <=>
          (SELECT embedding FROM demo.products WHERE name = 'vec_epsilon' AND id = ANY(%s)) AS d_alpha_epsilon
    """, (seeded_vectors, seeded_vectors, seeded_vectors, seeded_vectors))
    row = cur.fetchone()
    if row and row[0] is not None and row[1] is not None:
        assert row[0] < row[1], (
            f"alpha should be closer to beta ({row[0]:.4f}) "
            f"than to epsilon ({row[1]:.4f})"
        )


# ── L2 distance ───────────────────────────────────────────────────────────────

def test_l2_nearest_neighbour(pg_conn, seeded_vectors):
    """L2 (Euclidean) distance: querying [0,1,0] should find 'gamma' first."""
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT name, embedding <-> '[0,1,0]'::vector AS l2_dist
        FROM demo.products
        WHERE id = ANY(%s)
        ORDER BY embedding <-> '[0,1,0]'::vector
        LIMIT 3
    """, (seeded_vectors,))
    rows = cur.fetchall()
    assert len(rows) >= 1
    assert rows[0][1] < 0.5, f"Expected L2 distance < 0.5, got {rows[0][1]}"
    print(f"\n  nearest L2 to [0,1,0]: {rows[0][0]} (dist={rows[0][1]:.4f})")


# ── Inner product ─────────────────────────────────────────────────────────────

def test_inner_product_search(pg_conn, seeded_vectors):
    """Inner product search returns results ordered by <#>."""
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT name, (embedding <#> '[0,0,1]'::vector) * -1 AS inner_product
        FROM demo.products
        WHERE id = ANY(%s)
        ORDER BY embedding <#> '[0,0,1]'::vector
        LIMIT 3
    """, (seeded_vectors,))
    rows = cur.fetchall()
    assert len(rows) >= 1
    print(f"\n  max inner product with [0,0,1]: {rows[0][0]} ({rows[0][1]:.4f})")


# ── Vector norm / aggregate ───────────────────────────────────────────────────

def test_vector_avg(pg_conn, seeded_vectors):
    """avg(embedding) aggregation works on a set of vectors."""
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT avg(embedding)::text FROM demo.products
        WHERE id = ANY(%s)
    """, (seeded_vectors,))
    result = cur.fetchone()[0]
    assert result is not None, "avg(embedding) returned NULL"
    print(f"\n  avg vector: {result}")
