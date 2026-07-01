-- IT Brain — 0004: Entidades (universal)
-- Ver docs/05-base-de-datos.md §3
--
-- NOTA sobre embedding vector(1024): dimensión fijada para Voyage (voyage-3),
-- decidido en docs/12-ia-rag.md §11 (reemplaza el placeholder vector(1536) del
-- entregable 05 original). Confirmar dimensión exacta del modelo al integrar
-- la Edge Function de embeddings antes de generar datos reales.

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
  embedding       vector(1024),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid references auth.users(id),
  updated_by      uuid references auth.users(id),
  archived_at     timestamptz
);

-- Búsqueda (docs 11): FTS + trigram + semántico + filtro directo sobre JSONB
create index idx_entities_search on entities using gin (search_vector);
create index idx_entities_name_trgm on entities using gin (name gin_trgm_ops);
create index idx_entities_embedding on entities using ivfflat (embedding vector_cosine_ops) with (lists = 100);
create index idx_entities_data on entities using gin (data jsonb_path_ops);
create index idx_entities_org_type on entities(org_id, entity_type_id) where archived_at is null;

-- Trigger: actualizar search_vector (columnas base + campos JSONB is_searchable)
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
