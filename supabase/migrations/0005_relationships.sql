-- IT Brain — 0005: Relaciones (el grafo)
-- Ver docs/05-base-de-datos.md §4, docs/03-modelo-entidades-relaciones.md §5

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
