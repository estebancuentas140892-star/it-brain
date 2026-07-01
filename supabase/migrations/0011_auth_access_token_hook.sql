-- IT Brain — 0011: Custom Access Token Hook (resolución de org activa)
-- Ver docs/04-multitenancy-permisos.md §2.2 · T-017
--
-- Resuelve el problema de BOOTSTRAP: en el primer login el JWT no trae
-- `active_org_id`, así que public.org_id() es null y la RLS bloquea todo. Este hook
-- de Supabase Auth (custom access token) inyecta `active_org_id` + `active_role`
-- en las claims del token a partir de la membresía activa del usuario, de modo
-- que public.org_id() resuelve desde el primer request y en cada refresh.
--
-- MVP single-tenant (D-01): elige la primera membresía activa. La UI de selección
-- entre varias orgs es v2 (docs 04 §10); el esquema ya lo soporta.
--
-- Se configura en supabase/config.toml → [auth.hook.custom_access_token].

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  claims jsonb;
  v_user uuid;
  v_org  uuid;
  v_role text;
begin
  v_user := (event ->> 'user_id')::uuid;
  claims := coalesce(event -> 'claims', '{}'::jsonb);

  -- SOLO membresías activas: un usuario suspendido/invitado no obtiene org en su
  -- token (la revocación surte efecto ya en la emisión del JWT, no solo en RLS).
  -- Coincide con la semántica de public.org_id() (0002): status='active'.
  select m.org_id, m.role
    into v_org, v_role
  from public.memberships m
  where m.user_id = v_user
    and m.status = 'active'
  order by m.created_at
  limit 1;

  if v_org is not null then
    claims := jsonb_set(claims, '{active_org_id}', to_jsonb(v_org::text));
    claims := jsonb_set(claims, '{active_role}',   to_jsonb(v_role));
    event  := jsonb_set(event, '{claims}', claims);
  end if;

  return event;
end;
$$;

-- Solo el servidor de Auth invoca el hook; ningún cliente puede ejecutarlo
-- (evita que un usuario se auto-fabrique claims llamando a la función).
grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook(jsonb) from authenticated, anon, public;
