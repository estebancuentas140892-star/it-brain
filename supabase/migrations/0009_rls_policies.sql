-- IT Brain — 0009: Row-Level Security — políticas por tabla
-- Ver docs/05-base-de-datos.md §9, docs/04-multitenancy-permisos.md, docs/10-seguridad.md §5
--
-- Frontera dura contra fuga entre tenants (el fallo catastrófico #1, docs 10 §5).
-- Patrón: lectura = miembro activo de la org; escritura = role_rank() >= 2 (técnico+),
-- salvo lo marcado. IMPORTANTE: esta migración debe ir acompañada, en CI, de los
-- tests de aislamiento de tenant (docs 10 §5, D-21) como gate de despliegue.

alter table entities enable row level security;
alter table relationships enable row level security;
alter table attachments enable row level security;
alter table comments enable row level security;
alter table entity_tags enable row level security;
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

-- relationships
create policy relationships_select on relationships for select using (org_id = public.org_id());
create policy relationships_write on relationships for all
  using (org_id = public.org_id() and public.role_rank() >= 2)
  with check (org_id = public.org_id() and public.role_rank() >= 2);

-- attachments / comments
create policy attachments_select on attachments for select using (org_id = public.org_id());
create policy attachments_write on attachments for all
  using (org_id = public.org_id() and public.role_rank() >= 2)
  with check (org_id = public.org_id() and public.role_rank() >= 2);

create policy comments_select on comments for select using (org_id = public.org_id());
create policy comments_write on comments for all
  using (org_id = public.org_id() and public.role_rank() >= 2)
  with check (org_id = public.org_id() and public.role_rank() >= 2);

-- tags / entity_tags (org_id desnormalizado en entity_tags, docs 05 §12.3)
create policy tags_all on tags for all
  using (org_id = public.org_id())
  with check (org_id = public.org_id() and public.role_rank() >= 2);

create policy entity_tags_select on entity_tags for select using (org_id = public.org_id());
create policy entity_tags_write on entity_tags for all
  using (org_id = public.org_id() and public.role_rank() >= 2)
  with check (org_id = public.org_id() and public.role_rank() >= 2);

-- favorites / recent_views: solo el propio usuario, cualquier rol
create policy favorites_own on favorites for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy recent_views_own on recent_views for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- entity_history: lectura para todos los miembros; nunca escritura directa
create policy history_select on entity_history for select using (org_id = public.org_id());

-- secrets: solo supervisor+ (revelado real vía Edge Function, no select directo de valor)
create policy secrets_select on secrets for select using (org_id = public.org_id() and public.role_rank() >= 3);
create policy secrets_write on secrets for all
  using (org_id = public.org_id() and public.role_rank() >= 3)
  with check (org_id = public.org_id() and public.role_rank() >= 3);

create policy secret_log_select on secret_access_log for select
  using (org_id = public.org_id() and public.role_rank() >= 3);

create policy audit_select on audit_log for select using (org_id = public.org_id() and public.role_rank() >= 4);

-- entity_types / field_definitions / relationship_types:
-- lectura para todos (incluye tipos de sistema org_id is null); escritura solo admin
create policy types_select on entity_types for select using (org_id is null or org_id = public.org_id());
create policy types_write on entity_types for all
  using (org_id = public.org_id() and public.role_rank() >= 4)
  with check (org_id = public.org_id() and public.role_rank() >= 4);

create policy fields_select on field_definitions for select
  using (exists (
    select 1 from entity_types t
    where t.id = entity_type_id and (t.org_id is null or t.org_id = public.org_id())
  ));
-- Escritura solo admin (rank 4) Y solo sobre tipos de la PROPIA org.
-- El join a entity_types es imprescindible: field_definitions no tiene org_id,
-- y sin el filtro `t.org_id = public.org_id()` un admin podría añadir campos a un
-- tipo de SISTEMA (org_id IS NULL) — visible para todas las orgs vía fields_select —
-- contaminando el esquema compartido (docs 10 §5: integridad cross-tenant; 0010:
-- los tipos de sistema no son editables por el cliente). Cubierto por el test 17.
create policy fields_write on field_definitions for all
  using (public.role_rank() >= 4 and exists (
    select 1 from entity_types t
    where t.id = entity_type_id and t.org_id = public.org_id()))
  with check (public.role_rank() >= 4 and exists (
    select 1 from entity_types t
    where t.id = entity_type_id and t.org_id = public.org_id()));

create policy relationship_types_select on relationship_types for select
  using (org_id is null or org_id = public.org_id());
create policy relationship_types_write on relationship_types for all
  using (org_id = public.org_id() and public.role_rank() >= 4)
  with check (org_id = public.org_id() and public.role_rank() >= 4);

-- memberships: cada quien ve las de su org; solo admin gestiona
create policy memberships_select on memberships for select using (org_id = public.org_id());
-- Bootstrap de org (T-017, docs 04 §2.2): un usuario SIEMPRE puede ver las SUYAS,
-- aunque aún no tenga org activa resuelta (claim ausente → public.org_id() null).
-- Permite listar sus orgs para elegir (multi-org v2) y como degradación si el
-- access token hook no está desplegado. No filtra datos ajenos (solo filas
-- propias) y no recurre: auth.uid() no lee memberships.
create policy memberships_select_self on memberships for select
  using (user_id = auth.uid());
create policy memberships_write on memberships for all
  using (org_id = public.org_id() and public.role_rank() >= 4)
  with check (org_id = public.org_id() and public.role_rank() >= 4);
