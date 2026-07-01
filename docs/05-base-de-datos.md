# 05 · Base de datos — Esquema físico (PostgreSQL / Supabase)

> DDL completo que materializa el modelo lógico (03) y el modelo de permisos (04).
> Escrito para PostgreSQL 15+ / Supabase. Es el contrato que consumirán la API (09) y Flutter.

---

## 0. Extensiones requeridas

```sql
create extension if not exists "uuid-ossp";
create extension if not exists pg_trgm;      -- tolerancia a errores de escritura (búsqueda)
create extension if not exists vector;        -- pgvector: búsqueda semántica / IA
create extension if not exists pgcrypto;      -- cifrado de secretos
```

---

## 1. Núcleo multi-tenant

```sql
create table organizations (
  id          uuid primary key default uuid_generate_v4(),
  name        text not null,
  slug        text not null unique,
  plan        text not null default 'trial',
  status      text not null default 'active' check (status in ('active','suspended')),
  settings    jsonb not null default '{}',
  created_at  timestamptz not null default now()
);

create table memberships (
  id          uuid primary key default uuid_generate_v4(),
  org_id      uuid not null references organizations(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        text not null check (role in ('admin','supervisor','tecnico','consulta')),
  status      text not null default 'invited' check (status in ('active','invited','suspended')),
  invited_by  uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  unique (org_id, user_id)
);
create index idx_memberships_user on memberships(user_id) where status = 'active';
```

### Funciones de autorización (§2.3 del entregable 04)

```sql
create or replace function public.org_id() returns uuid
language sql stable as $$
  select m.org_id from memberships m
  where m.user_id = auth.uid()
    and m.status = 'active'
    and m.org_id = (auth.jwt() ->> 'active_org_id')::uuid
  limit 1;
$$;

create or replace function public.role_rank() returns int
language sql stable as $$
  select case m.role
    when 'admin' then 4 when 'supervisor' then 3
    when 'tecnico' then 2 when 'consulta' then 1 else 0 end
  from memberships m
  where m.user_id = auth.uid() and m.org_id = public.org_id() and m.status = 'active';
$$;
```

---

## 2. Meta-modelo (tipos y campos como datos)

```sql
create type archetype as enum (
  'device','network','software','license','credential',
  'identity','location','party','knowledge','case'
);

create table entity_types (
  id            uuid primary key default uuid_generate_v4(),
  org_id        uuid references organizations(id) on delete cascade,  -- null = tipo de sistema
  key           text not null,
  name          text not null,
  icon          text,
  color         text,
  archetype     archetype not null,
  parent_type_id uuid references entity_types(id),
  is_system     boolean not null default false,
  created_at    timestamptz not null default now(),
  unique (org_id, key)
);
create index idx_entity_types_org on entity_types(org_id);

create type field_data_type as enum (
  'text','number','bool','date','datetime','enum',
  'reference','ip','mac','url','email','secret','json','geo'
);
create type field_sensitivity as enum ('normal','sensitive','secret');

create table field_definitions (
  id              uuid primary key default uuid_generate_v4(),
  entity_type_id  uuid not null references entity_types(id) on delete cascade,
  key             text not null,
  label           text not null,
  help_text       text,
  data_type       field_data_type not null,
  is_required     boolean not null default false,
  is_unique       boolean not null default false,
  is_searchable   boolean not null default false,
  sensitivity     field_sensitivity not null default 'normal',
  min_role_read   text default 'consulta',
  min_role_write  text default 'tecnico',
  options         jsonb,                              -- para enum
  reference_type  uuid references entity_types(id),    -- para reference
  field_group     text,
  sort_order      int not null default 0,
  unique (entity_type_id, key)
);
```

---

## 3. Entidades (universal)

```sql
create table entities (
  id              uuid primary key default uuid_generate_v4(),
  org_id          uuid not null references organizations(id) on delete cascade,
  entity_type_id  uuid not null references entity_types(id),
  name            text not null,
  description     text,
  status          text,
  category        text,
  owner_id        uuid references auth.users(id),
  data            jsonb not null default '{}',
  search_vector   tsvector,
  embedding       vector(1536),                        -- dimensión del modelo de embeddings elegido
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid references auth.users(id),
  updated_by      uuid references auth.users(id),
  archived_at     timestamptz
);

-- Búsqueda
create index idx_entities_search on entities using gin (search_vector);
create index idx_entities_name_trgm on entities using gin (name gin_trgm_ops);
create index idx_entities_embedding on entities using ivfflat (embedding vector_cosine_ops) with (lists = 100);
create index idx_entities_data on entities using gin (data jsonb_path_ops);
create index idx_entities_org_type on entities(org_id, entity_type_id) where archived_at is null;

-- Trigger: actualizar search_vector (columnas base + campos JSONB marcados is_searchable)
create or replace function entities_update_search_vector() returns trigger as $$
declare
  searchable_text text;
begin
  select coalesce(string_agg(new.data ->> fd.key, ' '), '')
  into searchable_text
  from field_definitions fd
  where fd.entity_type_id = new.entity_type_id and fd.is_searchable;

  new.search_vector :=
    setweight(to_tsvector('simple', coalesce(new.name, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(new.description, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(searchable_text, '')), 'C');
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

create trigger trg_entities_search
  before insert or update on entities
  for each row execute function entities_update_search_vector();
```

---

## 4. Relaciones (el grafo)

```sql
create table relationship_types (
  id             uuid primary key default uuid_generate_v4(),
  org_id         uuid references organizations(id) on delete cascade,
  key            text not null,
  name           text not null,
  inverse_name   text not null,
  is_directional boolean not null default true,
  unique (org_id, key)
);

create table relationships (
  id                uuid primary key default uuid_generate_v4(),
  org_id            uuid not null references organizations(id) on delete cascade,
  source_entity_id  uuid not null references entities(id) on delete cascade,
  target_entity_id  uuid not null references entities(id) on delete cascade,
  type_id           uuid not null references relationship_types(id),
  metadata          jsonb not null default '{}',
  valid_from        timestamptz,
  valid_to          timestamptz,
  created_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id),
  check (source_entity_id <> target_entity_id)
);
create index idx_rel_source on relationships(source_entity_id);
create index idx_rel_target on relationships(target_entity_id);
create index idx_rel_org on relationships(org_id);
```

---

## 5. Tablas satélite (compartidas por toda entidad)

```sql
create table tags (
  id      uuid primary key default uuid_generate_v4(),
  org_id  uuid not null references organizations(id) on delete cascade,
  name    text not null,
  unique (org_id, name)
);

create table entity_tags (
  entity_id  uuid not null references entities(id) on delete cascade,
  tag_id     uuid not null references tags(id) on delete cascade,
  primary key (entity_id, tag_id)
);

create type attachment_kind as enum ('image','screenshot','video','pdf','office','zip','audio','link');

create table attachments (
  id             uuid primary key default uuid_generate_v4(),
  org_id         uuid not null references organizations(id) on delete cascade,
  entity_id      uuid not null references entities(id) on delete cascade,
  kind           attachment_kind not null,
  storage_path   text,          -- Supabase Storage
  external_url   text,          -- si kind = link
  caption        text,
  mime_type      text,
  size_bytes     bigint,
  uploaded_by    uuid references auth.users(id),
  uploaded_at    timestamptz not null default now()
);
create index idx_attachments_entity on attachments(entity_id);

create table comments (
  id          uuid primary key default uuid_generate_v4(),
  org_id      uuid not null references organizations(id) on delete cascade,
  entity_id   uuid not null references entities(id) on delete cascade,
  author_id   uuid references auth.users(id),
  body        text not null,
  created_at  timestamptz not null default now()
);
create index idx_comments_entity on comments(entity_id);

create table favorites (
  user_id     uuid not null references auth.users(id) on delete cascade,
  entity_id   uuid not null references entities(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, entity_id)
);

create table recent_views (
  user_id     uuid not null references auth.users(id) on delete cascade,
  entity_id   uuid not null references entities(id) on delete cascade,
  viewed_at   timestamptz not null default now(),
  primary key (user_id, entity_id)
);
create index idx_recent_views_user on recent_views(user_id, viewed_at desc);
```

---

## 6. Historial (append-only)

```sql
create table entity_history (
  id          uuid primary key default uuid_generate_v4(),
  org_id      uuid not null references organizations(id) on delete cascade,
  entity_id   uuid not null references entities(id) on delete cascade,
  field       text not null,        -- nombre de campo, o 'relationship' para altas/bajas de arista
  old_value   jsonb,
  new_value   jsonb,
  changed_by  uuid references auth.users(id),
  changed_at  timestamptz not null default now(),
  reason      text
);
create index idx_history_entity on entity_history(entity_id, changed_at desc);

-- Trigger: registrar cambios de campos base (name, description, status, data)
create or replace function entities_log_history() returns trigger as $$
begin
  if old.name is distinct from new.name then
    insert into entity_history(org_id, entity_id, field, old_value, new_value, changed_by)
    values (new.org_id, new.id, 'name', to_jsonb(old.name), to_jsonb(new.name), new.updated_by);
  end if;
  if old.status is distinct from new.status then
    insert into entity_history(org_id, entity_id, field, old_value, new_value, changed_by)
    values (new.org_id, new.id, 'status', to_jsonb(old.status), to_jsonb(new.status), new.updated_by);
  end if;
  if old.data is distinct from new.data then
    insert into entity_history(org_id, entity_id, field, old_value, new_value, changed_by)
    values (new.org_id, new.id, 'data', old.data, new.data, new.updated_by);
  end if;
  return new;
end;
$$ language plpgsql;

create trigger trg_entities_history
  after update on entities
  for each row execute function entities_log_history();

-- Append-only real: nadie (salvo service_role) puede tocar el historial
revoke update, delete on entity_history from authenticated;
```

---

## 7. Credenciales y secretos (§7 del modelo, §7 del entregable 04)

```sql
create table secrets (
  id                    uuid primary key default uuid_generate_v4(),
  org_id                uuid not null references organizations(id) on delete cascade,
  credential_entity_id  uuid not null references entities(id) on delete cascade,
  ciphertext            bytea not null,       -- cifrado con pgcrypto / clave gestionada fuera de la fila
  rotated_at            timestamptz not null default now()
);

create table secret_access_log (
  id          uuid primary key default uuid_generate_v4(),
  org_id      uuid not null references organizations(id) on delete cascade,
  secret_id   uuid not null references secrets(id) on delete cascade,
  user_id     uuid references auth.users(id),
  action      text not null check (action in ('view','reveal','update','rotate')),
  at          timestamptz not null default now(),
  ip          inet,
  user_agent  text
);
revoke update, delete on secret_access_log from authenticated;
```

`reveal_secret` se implementa como **función RPC `security definer`** (no acceso directo a
`ciphertext` desde el cliente): valida rol/grant, descifra, inserta en `secret_access_log` y
devuelve el valor. Detalle de la función en el entregable 09 (API).

---

## 8. Auditoría administrativa

```sql
create table audit_log (
  id          uuid primary key default uuid_generate_v4(),
  org_id      uuid not null references organizations(id) on delete cascade,
  actor_id    uuid references auth.users(id),
  action      text not null,        -- 'role_changed','user_invited','schema_changed', etc.
  target      jsonb not null,
  at          timestamptz not null default now()
);
revoke update, delete on audit_log from authenticated;
```

---

## 9. Row-Level Security — políticas por tabla

Patrón repetido: **lectura** = miembro activo de la org; **escritura** = `role_rank() >= 2`
(técnico+), salvo lo marcado. Se habilita RLS en **todas** las tablas de negocio.

```sql
alter table entities enable row level security;
alter table relationships enable row level security;
alter table attachments enable row level security;
alter table comments enable row level security;
alter table entity_tags enable row level security;   -- vía join a entities, ver nota
alter table tags enable row level security;
alter table favorites enable row level security;
alter table recent_views enable row level security;
alter table entity_history enable row level security;
alter table secrets enable row level security;
alter table secret_access_log enable row level security;
alter table audit_log enable row level security;
alter table entity_types enable row level security;
alter table field_definitions enable row level security;
alter table relationship_types enable row level security;
alter table memberships enable row level security;

-- entities
create policy entities_select on entities for select using (org_id = public.org_id());
create policy entities_insert on entities for insert with check (org_id = public.org_id() and public.role_rank() >= 2);
create policy entities_update on entities for update
  using (org_id = public.org_id() and public.role_rank() >= 2)
  with check (org_id = public.org_id() and public.role_rank() >= 2);
-- archive: UPDATE de archived_at ya cubierto por la policy de update (grano fino en API, §7 del 04)

-- relationships
create policy relationships_select on relationships for select using (org_id = public.org_id());
create policy relationships_write on relationships for all
  using (org_id = public.org_id() and public.role_rank() >= 2)
  with check (org_id = public.org_id() and public.role_rank() >= 2);

-- attachments / comments / tags / entity_tags
create policy attachments_select on attachments for select using (org_id = public.org_id());
create policy attachments_write on attachments for all
  using (org_id = public.org_id() and public.role_rank() >= 2)
  with check (org_id = public.org_id() and public.role_rank() >= 2);

create policy comments_select on comments for select using (org_id = public.org_id());
create policy comments_write on comments for all
  using (org_id = public.org_id() and public.role_rank() >= 2)
  with check (org_id = public.org_id() and public.role_rank() >= 2);

create policy tags_all on tags for all
  using (org_id = public.org_id())
  with check (org_id = public.org_id() and public.role_rank() >= 2);

-- favorites / recent_views: solo el propio usuario, cualquier rol
create policy favorites_own on favorites for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy recent_views_own on recent_views for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- entity_history: lectura para todos los miembros; nunca escritura directa
create policy history_select on entity_history for select using (org_id = public.org_id());

-- secrets: solo supervisor+ (revelado real vía RPC security definer, no select directo de ciphertext)
create policy secrets_select on secrets for select using (org_id = public.org_id() and public.role_rank() >= 3);
create policy secrets_write on secrets for all
  using (org_id = public.org_id() and public.role_rank() >= 3)
  with check (org_id = public.org_id() and public.role_rank() >= 3);

create policy secret_log_select on secret_access_log for select
  using (org_id = public.org_id() and public.role_rank() >= 3);

create policy audit_select on audit_log for select using (org_id = public.org_id() and public.role_rank() >= 4);

-- entity_types / field_definitions / relationship_types: lectura para todos (incluye tipos de sistema org_id is null); escritura solo admin
create policy types_select on entity_types for select using (org_id is null or org_id = public.org_id());
create policy types_write on entity_types for all
  using (org_id = public.org_id() and public.role_rank() >= 4)
  with check (org_id = public.org_id() and public.role_rank() >= 4);

create policy fields_select on field_definitions for select
  using (exists (select 1 from entity_types t where t.id = entity_type_id and (t.org_id is null or t.org_id = public.org_id())));
create policy fields_write on field_definitions for all
  using (public.role_rank() >= 4) with check (public.role_rank() >= 4);

-- memberships: cada quien ve las de su org; solo admin gestiona
create policy memberships_select on memberships for select using (org_id = public.org_id());
create policy memberships_write on memberships for all
  using (org_id = public.org_id() and public.role_rank() >= 4)
  with check (org_id = public.org_id() and public.role_rank() >= 4);
```

> **Nota `entity_tags`:** no tiene `org_id` propio; su policy se resuelve por `exists` contra
> `entities`. Se añade en la migración junto con las demás tablas de unión N:N.

---

## 10. Convenciones de migración

- Una migración por entregable/cambio semántico, numerada (`0001_core.sql`, `0002_rls.sql`…),
  gestionada con el CLI de Supabase (`supabase migration new`).
- Los **tipos y campos de sistema** (`entity_types`/`field_definitions` con `org_id is null`) se
  siembran vía *seed* versionado, no a mano en producción.
- Ninguna migración hace `DROP`/`DELETE` destructivo sobre datos de cliente sin *backup* explícito.

---

## 11. Cumplimiento de la Constitución

| Regla | Cómo se cumple |
|-------|----------------|
| 1 · Búsqueda > navegación | `search_vector` (FTS) + `pg_trgm` + `embedding` (pgvector) indexados desde el día 1 |
| 5 / 13 · Registro y trazabilidad | Triggers de `entity_history`, `secret_access_log`, `audit_log`, todos append-only (`revoke update, delete`) |
| 6 / 7 · Evolución sin rediseño | `entity_types`/`field_definitions` como datos; nuevo tipo = INSERT, no migración |
| 10 · Sensación instantánea | Índices GIN/ivfflat pensados desde el esquema, no añadidos después |

---

## 12. Cuestiones abiertas

1. **Dimensión del `embedding`** (1536 aquí, modelo OpenAI-compatible): confirmar al cerrar el
   entregable 12 (estrategia de IA) — puede cambiar el índice `ivfflat`/`hnsw`.
2. **Gestión de la clave de cifrado de `secrets.ciphertext`**: pendiente del entregable 10
   (Seguridad) — `pgsodium` vs. KMS externo.
3. **`entity_tags` y demás N:N** sin `org_id`: confirmar si conviene desnormalizar `org_id` en la
   tabla de unión para simplificar RLS (mejora rendimiento, algo de redundancia). Recomendación:
   sí, desnormalizar — coherente con el resto del esquema.

---

### Próxima tarea
**T-004 · Casos de uso principales** (buscar, ver vecindario de una entidad, registrar incidente,
consultar/revelar credencial) — entregable 06.
