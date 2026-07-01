# IT Brain — Migraciones Supabase

Migraciones SQL que materializan [docs/05-base-de-datos.md](../docs/05-base-de-datos.md) y
[docs/04-multitenancy-permisos.md](../docs/04-multitenancy-permisos.md). Se aplican en orden
numérico — cada archivo depende del anterior.

| Archivo | Contenido |
|---|---|
| `0001_extensions.sql` | uuid-ossp, pg_trgm, vector, pgcrypto |
| `0002_multitenancy.sql` | organizations, memberships, `public.org_id()`, `public.role_rank()` |
| `0003_meta_model.sql` | entity_types, field_definitions (el meta-modelo dirigido por datos) |
| `0004_entities.sql` | entities + índices de búsqueda (FTS/trigram/pgvector) + trigger |
| `0005_relationships.sql` | relationship_types, relationships (el grafo) |
| `0006_satellite_tables.sql` | tags, attachments, comments, favorites, recent_views |
| `0007_history.sql` | entity_history (append-only) + trigger |
| `0008_secrets_audit.sql` | secrets, secret_access_log, audit_log |
| `0009_rls_policies.sql` | **Todas** las políticas RLS — la frontera dura multi-tenant |
| `0010_seed_system_types.sql` | Arquetipos y tipos de sistema (POS, Servidor, Incidente…) |

## Cómo aplicar

Con el CLI de Supabase (`npm i -g supabase` o `scoop install supabase`):

```bash
supabase link --project-ref TU_PROJECT_REF
supabase db push
```

O pegando cada archivo en orden en el SQL Editor del dashboard de Supabase.

## Antes de ir a producción — no negociable

Según [docs/10-seguridad.md §5](../docs/10-seguridad.md) (D-21): **ningún despliegue** debe
ocurrir sin que la batería de tests de aislamiento de tenant (2 orgs, verificar que A nunca lee/
escribe datos de B por ninguna vía) pase en CI. Es la siguiente tarea del tablero (T-015).

## Pendiente de completar (fuera de esta migración)

- RPCs de la API (`v1_search_entities`, `v1_entity_neighborhood`, `v1_create_incident`,
  `v1_close_incident`, `v1_match_entities`, `v1_sync_pull` — docs 09/13) y las Edge Functions
  (`reveal-secret`, `search-semantic`) se implementan en tareas posteriores de la secuencia de
  construcción (docs/14-alcance-mvp.md §5).
- Envelope encryption real (KEK/DEK, docs 10 §2) requiere configurar Supabase Vault en el proyecto.
