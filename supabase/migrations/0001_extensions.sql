-- IT Brain — 0001: Extensiones requeridas
-- Ver docs/05-base-de-datos.md §0

create extension if not exists "uuid-ossp";
create extension if not exists pg_trgm;      -- tolerancia a errores de escritura (búsqueda, docs 11)
create extension if not exists vector;        -- pgvector: búsqueda semántica / IA (docs 12)
create extension if not exists pgcrypto;      -- cifrado de secretos (docs 10)
