-- oss-learn Extension Reference
-- Run on an existing database to add a specific extension.
-- Usage: psql -U postgres -d car_parking < setup/postgres/extensions.sql

-- pgvector — 512-dimensional vector similarity search
-- Required for: Car.plate_embedding column, fuzzy plate matching
CREATE EXTENSION IF NOT EXISTS vector;

-- Apache AGE — property graph (Cypher queries)
-- Required for: Employee -[:OWNS]-> Car -[:PARKED_AT]-> Floor relationships
CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- pg_trgm — trigram fuzzy text matching
-- Required for: partial plate searches, GIN index on lp_text
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- uuid-ossp — UUID generation functions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Verify
SELECT extname, extversion, extrelocatable
FROM pg_extension
ORDER BY extname;
