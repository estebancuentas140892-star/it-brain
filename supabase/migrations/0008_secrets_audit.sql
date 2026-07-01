-- IT Brain — 0008: Credenciales/secretos y auditoría
-- Ver docs/05-base-de-datos.md §7/§8, docs/10-seguridad.md §2 (envelope encryption)
--
-- El descifrado real (envelope: KEK en Vault -> DEK por org -> ciphertext) ocurre
-- SOLO en la Edge Function `reveal-secret` (docs 09 §6.1). Esta tabla nunca es
-- legible en texto plano vía RLS/PostgREST directo.

create table secrets (
  id                    uuid primary key default uuid_generate_v4(),
  org_id                uuid not null references organizations(id) on delete cascade,
  credential_entity_id  uuid not null references entities(id) on delete cascade,
  ciphertext            bytea not null,
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

create table audit_log (
  id          uuid primary key default uuid_generate_v4(),
  org_id      uuid not null references organizations(id) on delete cascade,
  actor_id    uuid references auth.users(id),
  action      text not null,        -- 'role_changed','user_invited','schema_changed', etc.
  target      jsonb not null,
  at          timestamptz not null default now()
);
revoke update, delete on audit_log from authenticated;
