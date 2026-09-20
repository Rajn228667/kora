-- =============================================================================
-- KORA — Postgres bootstrap (executed once on first container init)
-- Mounted at /docker-entrypoint-initdb.d/00-init.sql by docker-compose.
-- =============================================================================

-- Trigram similarity for fuzzy product/store search (ILIKE + pg_trgm indexes)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Accent-insensitive search (Cyrillic/Latin normalization helpers)
CREATE EXTENSION IF NOT EXISTS unaccent;

-- gen_random_uuid() for UUID primary keys, crypto helpers for token hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;
