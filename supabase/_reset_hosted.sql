-- IT Brain — RESET del esquema (hosted / desarrollo)
-- =====================================================================
-- ⚠️  DESTRUCTIVO: borra TODAS las tablas, tipos y funciones de IT Brain
--     y sus datos. Úsalo SOLO en una base de diseño/desarrollo sin datos
--     que te importen. NO ejecutar en producción.
--
-- Para qué: deja la base en limpio tras una ejecución parcial fallida de
-- `_setup_hosted.sql` (p.ej. si abortó a mitad y dejó `organizations` a
-- medias -> "42P07: relation already exists" al reintentar).
--
-- Uso: ejecuta este script UNA vez y luego vuelve a correr `_setup_hosted.sql`
-- completo desde el inicio.
--
-- No toca el schema `auth` ni las extensiones (0001 las recrea con
-- `create extension if not exists`, así que no hace falta borrarlas).
-- =====================================================================

-- Tablas (cascade arrastra índices, triggers, políticas RLS y FKs entre ellas).
drop table if exists
  audit_log,
  secret_access_log,
  secrets,
  entity_history,
  recent_views,
  favorites,
  comments,
  attachments,
  entity_tags,
  tags,
  relationships,
  relationship_types,
  entities,
  field_definitions,
  entity_types,
  memberships,
  organizations
cascade;

-- Funciones (las de RLS ya viven en `public`, no en `auth`).
drop function if exists public.org_id() cascade;
drop function if exists public.role_rank() cascade;
drop function if exists public.custom_access_token_hook(jsonb) cascade;
drop function if exists public.entities_update_search_vector() cascade;
drop function if exists public.entities_log_history() cascade;

-- Tipos enum del meta-modelo.
drop type if exists attachment_kind cascade;
drop type if exists field_sensitivity cascade;
drop type if exists field_data_type cascade;
drop type if exists archetype cascade;
