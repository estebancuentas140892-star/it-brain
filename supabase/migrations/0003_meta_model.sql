-- IT Brain — 0003: Meta-modelo (tipos y campos como datos)
-- Ver docs/05-base-de-datos.md §2, docs/03-modelo-entidades-relaciones.md §2/§4
-- Esta es la capa que permite crear tipos/campos nuevos sin desplegar código (regla 7).

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
