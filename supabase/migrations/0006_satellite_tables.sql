-- IT Brain — 0006: Tablas satélite (compartidas por toda entidad)
-- Ver docs/05-base-de-datos.md §5

create table tags (
  id      uuid primary key default uuid_generate_v4(),
  org_id  uuid not null references organizations(id) on delete cascade,
  name    text not null,
  unique (org_id, name)
);

create table entity_tags (
  org_id     uuid not null references organizations(id) on delete cascade,  -- desnormalizado: simplifica RLS (docs 05 §12.3)
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
