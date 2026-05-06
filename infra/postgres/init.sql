-- oss-learn PostgreSQL Initialisation Script
-- Creates the osslearn database, enables extensions, and sets up a demo schema.
--
-- Usage:
--   docker exec -i oss-postgres psql -U postgres < infra/postgres/init.sql
-- Re-running is safe (IF NOT EXISTS / ON CONFLICT guards everywhere).

\set ON_ERROR_STOP off

-- ── 1. Create database ───────────────────────────────────────────────────────
SELECT 'Step 1: Creating database osslearn...' AS status;
SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'osslearn')
  THEN 'CREATE DATABASE osslearn WITH OWNER postgres ENCODING ''UTF8'' TEMPLATE template0;'
  ELSE NULL END AS ddl
\gexec

\set ON_ERROR_STOP on
\c osslearn

-- ── 2. Extensions ────────────────────────────────────────────────────────────
SELECT 'Step 2: Enabling extensions...' AS status;

CREATE EXTENSION IF NOT EXISTS vector;        -- pgvector: similarity search
CREATE EXTENSION IF NOT EXISTS age;           -- Apache AGE: graph queries
CREATE EXTENSION IF NOT EXISTS pg_trgm;       -- fuzzy text search
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";   -- UUID generation

-- ── 3. Demo schema ───────────────────────────────────────────────────────────
SELECT 'Step 3: Creating demo schema...' AS status;

CREATE SCHEMA IF NOT EXISTS demo;

-- ── 4. Demo tables ───────────────────────────────────────────────────────────
SELECT 'Step 4: Creating demo tables...' AS status;

SET search_path = demo, public;

-- Products table: plain relational + vector embedding column
CREATE TABLE IF NOT EXISTS demo.products (
    id          UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT         NOT NULL,
    category    TEXT         NOT NULL,
    description TEXT,
    price       NUMERIC(10,2),
    embedding   vector(3),   -- 3-dim for easy testing; real use: 1536 for OpenAI
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_products_category ON demo.products (category);
CREATE INDEX IF NOT EXISTS idx_products_embedding ON demo.products USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 10);

-- Documents table: full-text + trigram search demo
CREATE TABLE IF NOT EXISTS demo.documents (
    id         UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
    title      TEXT  NOT NULL,
    body       TEXT,
    tags       TEXT[],
    embedding  vector(3),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_documents_trgm ON demo.documents USING gin (title gin_trgm_ops);

-- Events table: time-series demo
CREATE TABLE IF NOT EXISTS demo.events (
    id         BIGSERIAL    PRIMARY KEY,
    source     TEXT         NOT NULL,
    event_type TEXT         NOT NULL,
    payload    JSONB,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_events_source    ON demo.events (source);
CREATE INDEX IF NOT EXISTS idx_events_occurred  ON demo.events (occurred_at DESC);

-- ── 5. AGE graph setup ───────────────────────────────────────────────────────
SELECT 'Step 5: Setting up AGE demo graph...' AS status;

LOAD 'age';
SET search_path = ag_catalog, demo, public;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_graph WHERE name = 'demo_graph') THEN
    PERFORM ag_catalog.create_graph('demo_graph');
  END IF;
END
$$;

-- ── 6. Demo user ─────────────────────────────────────────────────────────────
SELECT 'Step 6: Creating demo user...' AS status;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'demo') THEN
    CREATE USER demo WITH PASSWORD 'demo_dev' CONNECTION LIMIT 20;
  END IF;
END
$$;

GRANT CONNECT ON DATABASE osslearn TO demo;
GRANT USAGE ON SCHEMA demo TO demo;
GRANT ALL PRIVILEGES ON SCHEMA demo TO demo;
ALTER DEFAULT PRIVILEGES IN SCHEMA demo GRANT ALL ON TABLES TO demo;

SET search_path = public;

-- ── 7. Seed dummy data ───────────────────────────────────────────────────────
SELECT 'Step 7: Seeding dummy data...' AS status;

INSERT INTO demo.products (name, category, description, price, embedding) VALUES
  ('Widget A',    'hardware',  'A basic widget for demos',        9.99,   '[1.0, 0.1, 0.0]'),
  ('Widget B',    'hardware',  'An advanced widget',             19.99,   '[0.9, 0.2, 0.1]'),
  ('Gadget X',    'software',  'A demo gadget with extra features', 49.99, '[0.0, 1.0, 0.2]'),
  ('Gadget Y',    'software',  'Budget gadget',                   14.99,  '[0.1, 0.9, 0.1]'),
  ('SuperTool',   'hardware',  'Heavy-duty supertool',           199.00,  '[0.5, 0.5, 0.7]')
ON CONFLICT DO NOTHING;

INSERT INTO demo.documents (title, body, tags, embedding) VALUES
  ('Introduction to pgvector',  'pgvector adds vector similarity search to PostgreSQL.', ARRAY['postgres','vector','ml'], '[1.0, 0.0, 0.0]'),
  ('Apache AGE Graph Extension','AGE enables graph queries (Cypher) inside PostgreSQL.',  ARRAY['postgres','graph','cypher'], '[0.0, 1.0, 0.0]'),
  ('Prometheus Monitoring',     'Prometheus scrapes metrics and stores time-series data.', ARRAY['observability','metrics'], '[0.0, 0.0, 1.0]'),
  ('Grafana Dashboards',        'Grafana visualises metrics from Prometheus and Loki.',    ARRAY['observability','dashboards'], '[0.1, 0.1, 0.9]'),
  ('Ollama Local LLMs',         'Ollama runs large language models locally on CPU.',       ARRAY['ai','llm','ollama'], '[0.8, 0.2, 0.0]')
ON CONFLICT DO NOTHING;

INSERT INTO demo.events (source, event_type, payload) VALUES
  ('api',      'request',   '{"method":"GET","path":"/healthz","status":200}'),
  ('api',      'request',   '{"method":"POST","path":"/data","status":201}'),
  ('db',       'query',     '{"table":"products","duration_ms":12}'),
  ('ollama',   'inference', '{"model":"llama3.2:1b","tokens":42,"duration_ms":850}'),
  ('openvino', 'inference', '{"model":"mobilenet","latency_ms":5}')
ON CONFLICT DO NOTHING;

SELECT 'Initialisation complete.' AS status;

SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'demo'
ORDER BY table_name;
