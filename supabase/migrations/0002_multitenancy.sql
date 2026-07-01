-- IT Brain — 0002: Núcleo multi-tenant
-- Ver docs/05-base-de-datos.md §1, docs/04-multitenancy-permisos.md §2

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

-- Funciones de autorización (docs 04 §2.3) — resuelven org activa y rango de rol.
-- Nunca confían solo en el claim del JWT: siempre se contrastan contra memberships.
--
-- SECURITY DEFINER es OBLIGATORIO, no cosmético: estas funciones consultan
-- `memberships`, y las políticas RLS de memberships (0009) están definidas EN
-- TÉRMINOS de public.org_id(). Sin definer, leer memberships dentro de la función
-- re-dispara la RLS de memberships -> "infinite recursion detected in policy for
-- relation memberships", y NINGUNA consulta autenticada funcionaría (el gate de
-- aislamiento entero abortaría). Como definer, la lectura interna evita RLS y corta
-- la recursión SIN relajar seguridad: se sigue exigiendo user_id = auth.uid() +
-- status='active' + org del claim. search_path fijado a '' (buena práctica en
-- definer: evita secuestro por resolución de nombres; todo va cualificado por esquema).
--
-- NOTA: viven en `public`, NO en `auth`. Supabase hosted revoca CREATE sobre el
-- schema `auth` al rol postgres, así que `create function auth.*` falla con
-- "42501: permission denied for schema auth". Llamar auth.uid()/auth.jwt() sí
-- está permitido; crear objetos en `auth` no. Junto a public.custom_access_token_hook (0011).
create or replace function public.org_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select m.org_id from public.memberships m
  where m.user_id = auth.uid()
    and m.status = 'active'
    and m.org_id = (auth.jwt() ->> 'active_org_id')::uuid
  limit 1;
$$;

create or replace function public.role_rank() returns int
language sql stable security definer set search_path = '' as $$
  select case m.role
    when 'admin' then 4 when 'supervisor' then 3
    when 'tecnico' then 2 when 'consulta' then 1 else 0 end
  from public.memberships m
  where m.user_id = auth.uid() and m.org_id = public.org_id() and m.status = 'active';
$$;
