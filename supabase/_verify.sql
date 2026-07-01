-- IT Brain — VERIFICACIÓN del esquema (hosted)
-- =====================================================================
-- Ejecuta este script (todo de una vez) en el SQL Editor DESPUÉS de correr
-- _setup_hosted.sql. Devuelve una lista de chequeos: si todos dan '✅ OK',
-- el esquema está aplicado a la perfección. Cualquier '❌ FALTA' indica que
-- esa parte no se creó (revisa el error del setup).
-- =====================================================================

with checks as (
  select 'extensiones (uuid-ossp, pg_trgm, vector, pgcrypto)' as chequeo, 4 as esperado,
    (select count(*) from pg_extension
      where extname in ('uuid-ossp','pg_trgm','vector','pgcrypto')) as actual
  union all
  select 'tablas del dominio', 17,
    (select count(*) from information_schema.tables
      where table_schema = 'public' and table_name in
      ('organizations','memberships','entity_types','field_definitions','entities',
       'relationship_types','relationships','tags','entity_tags','attachments',
       'comments','favorites','recent_views','entity_history','secrets',
       'secret_access_log','audit_log'))
  union all
  select 'funciones (org_id, role_rank, hook, 2 triggers)', 5,
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in
      ('org_id','role_rank','custom_access_token_hook',
       'entities_update_search_vector','entities_log_history'))
  union all
  select 'tablas con RLS habilitada', 16,
    (select count(*) from pg_tables t join pg_class c on c.relname = t.tablename
      where t.schemaname = 'public' and c.relrowsecurity and t.tablename in
      ('entities','relationships','attachments','comments','entity_tags','tags',
       'favorites','recent_views','entity_history','secrets','secret_access_log',
       'audit_log','entity_types','field_definitions','relationship_types','memberships'))
  union all
  select 'tipos de entidad de sistema (seed 0010)', 37,
    (select count(*) from entity_types where is_system)
  union all
  select 'tipos de relación de sistema (seed 0010)', 11,
    (select count(*) from relationship_types where org_id is null)
  union all
  select 'hook ejecutable por supabase_auth_admin', 1,
    (select case when has_function_privilege(
        'supabase_auth_admin', 'public.custom_access_token_hook(jsonb)', 'execute')
      then 1 else 0 end)
)
select chequeo, esperado, actual,
  case when actual >= esperado then '✅ OK' else '❌ FALTA' end as estado
from checks
order by estado desc, chequeo;
