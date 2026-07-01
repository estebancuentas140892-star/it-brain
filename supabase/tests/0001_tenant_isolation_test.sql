-- IT Brain — Tests de aislamiento de tenant (pgTAP)
-- Gate de despliegue NO NEGOCIABLE: docs/10-seguridad.md §5 (D-21).
--
-- Verifica que un usuario de la org A NUNCA puede leer/escribir datos de la org B
-- por ninguna vía a nivel de base de datos (RLS). Se ejecuta con `supabase test db`,
-- que provee el esquema `auth`, los roles `authenticated`/`anon` y las funciones
-- auth.uid()/auth.jwt() — el entorno fiel a producción.
--
-- Método: se insertan fixtures como superusuario (bypassa RLS), y cada aserción
-- cambia al rol `authenticated` con un JWT simulado (set_config de
-- request.jwt.claims) para ejercer exactamente el contexto que usa PostgREST.
--
-- COBERTURA ACTUAL: RLS a nivel de tabla (la frontera dura). Cuando se implementen
-- las RPC (v1_search_entities, v1_entity_neighborhood, v1_match_entities...) y las
-- Edge Functions, CADA una debe añadir aquí su test de aislamiento — el gate crece
-- con las features (ver README de esta carpeta).

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions, auth;

select * from no_plan();

-- =====================================================================
-- Helpers de autenticación simulada
-- =====================================================================
-- Cambia al contexto de un usuario autenticado con una org activa dada.
create or replace function _login(p_user uuid, p_org uuid) returns void
language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated', 'active_org_id', p_org)::text,
    true
  );
end $$;

-- Vuelve a superusuario (para insertar fixtures / cambiar de usuario).
-- Se usa `reset role` en el cuerpo del test porque `authenticated` no puede
-- volver a postgres con `set role`.

-- =====================================================================
-- Fixtures (como superusuario: RLS no aplica al superusuario)
-- =====================================================================
reset role;

-- Organizaciones
insert into organizations (id, name, slug) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Org A', 'org-a'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Org B', 'org-b');

-- Usuarios (auth.users) — mínimo necesario para el FK de memberships
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'admin-a@test.local'),
  ('a0000000-0000-0000-0000-000000000002', 'super-a@test.local'),
  ('a0000000-0000-0000-0000-000000000003', 'tec-a@test.local'),
  ('a0000000-0000-0000-0000-000000000004', 'cons-a@test.local'),
  ('b0000000-0000-0000-0000-000000000001', 'admin-b@test.local');

-- Membresías (todas activas)
insert into memberships (org_id, user_id, role, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'admin',      'active'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', 'supervisor', 'active'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003', 'tecnico',    'active'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000004', 'consulta',   'active'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'admin',      'active');

-- Entidades (tipo POS de sistema, seed 0010). 2 en A, 1 en B.
insert into entities (id, org_id, entity_type_id, name) values
  ('e1000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'POS A-1'),
  ('e1000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'POS A-2'),
  ('e2000000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'POS B-1');

-- Credenciales + secretos (una por org)
insert into entities (id, org_id, entity_type_id, name) values
  ('ec000000-0000-0000-0000-00000000000a', 'aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000050', 'Cred A'),
  ('ec000000-0000-0000-0000-00000000000b', 'bbbbbbbb-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000050', 'Cred B');
insert into secrets (org_id, credential_entity_id, ciphertext) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-00000000000a', '\x00'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-00000000000b', '\x00');

-- Relaciones (una en cada org, tipo 'usa' del seed)
insert into relationships (org_id, source_entity_id, target_entity_id, type_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
       'ec000000-0000-0000-0000-00000000000a', id
from relationship_types where key = 'usa' and org_id is null;

-- Usuarios adicionales: uno SUSPENDIDO en A, uno multi-org (consultor en A y B).
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000005', 'susp-a@test.local'),
  ('a0000000-0000-0000-0000-000000000006', 'multi-ab@test.local');
insert into memberships (org_id, user_id, role, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000005', 'tecnico',  'suspended'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000006', 'consulta', 'active'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000006', 'consulta', 'active');

-- Satélites en la org A (para probar que NO cruzan de tenant): 1 tag + 1 vínculo + 1 comentario.
insert into tags (id, org_id, name) values
  ('da000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'produccion');
insert into entity_tags (org_id, entity_id, tag_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001');
insert into comments (org_id, entity_id, author_id, body) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'a0000000-0000-0000-0000-000000000003', 'Comentario interno de la org A');

-- Auditoría: una entrada en cada org (aislamiento + solo-admin + append-only).
insert into audit_log (org_id, actor_id, action, target) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'role_changed', '{"x":1}'::jsonb),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'role_changed', '{"y":2}'::jsonb);

-- =====================================================================
-- TESTS
-- =====================================================================

-- --- 0. Smoke: leer como authenticated NO recurre en la RLS de memberships
-- public.org_id()/role_rank() son SECURITY DEFINER (0002). Si dejaran de serlo, la
-- RLS de memberships (definida sobre public.org_id()) recurriria infinitamente y
-- NINGUNA consulta autenticada funcionaria. Esta asercion es el guardian de esa
-- regresion: si vuelve, falla aqui ruidosamente en vez de dar luz verde falsa.
select _login('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select lives_ok('select count(*) from memberships',
  'Leer memberships como authenticated no dispara recursion de RLS (helpers son security definer)');
select ok((select count(*) from memberships) > 0,
  'Tecnico A ve las membresias de su org (public.org_id() resuelve a una org, no null)');
reset role;

-- --- 1. Lectura: el técnico de A ve solo entidades de A -------------------
select _login('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select is(
  (select count(*) from entities where entity_type_id = '00000000-0000-0000-0000-000000000001')::int,
  2,
  'Tecnico A ve exactamente las 2 entidades POS de su org'
);
select is(
  (select count(*) from entities where id = 'e2000000-0000-0000-0000-000000000001')::int,
  0,
  'Tecnico A NO ve la entidad de la org B (aislamiento de lectura)'
);
reset role;

-- --- 2. Escritura legítima en la propia org ------------------------------
select _login('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select lives_ok(
  $$insert into entities (org_id, entity_type_id, name)
    values ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','POS A-3')$$,
  'Tecnico A puede crear una entidad en su propia org'
);
reset role;

-- --- 3. Escritura cruzada: insertar en la org B DEBE fallar --------------
select _login('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select throws_ok(
  $$insert into entities (org_id, entity_type_id, name)
    values ('bbbbbbbb-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','Intruso')$$,
  '42501',
  null,
  'Tecnico A NO puede insertar una entidad en la org B (RLS with check)'
);
reset role;

-- --- 4. Update cruzado: no afecta filas de la org B ---------------------
select _login('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select is(
  (with u as (
     update entities set name = 'hackeado'
     where id = 'e2000000-0000-0000-0000-000000000001' returning 1
   ) select count(*) from u)::int,
  0,
  'Update de tecnico A sobre entidad de org B no afecta ninguna fila'
);
reset role;

-- --- 5. Rol insuficiente: consulta no puede crear -----------------------
select _login('a0000000-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select throws_ok(
  $$insert into entities (org_id, entity_type_id, name)
    values ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','X')$$,
  '42501',
  null,
  'Rol consulta NO puede crear entidades (role_rank < 2)'
);
reset role;

-- --- 6. Secretos: consulta y tecnico no los ven (rank < 3) --------------
select _login('a0000000-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from secrets)::int, 0,
  'Rol consulta NO ve ningun secreto (role_rank < 3)');
reset role;

select _login('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from secrets)::int, 0,
  'Rol tecnico NO ve secretos (role_rank < 3)');
reset role;

-- --- 7. Secretos: supervisor ve solo el de su org -----------------------
select _login('a0000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from secrets)::int, 1,
  'Supervisor A ve exactamente 1 secreto (el de su org, no el de B)');
select is(
  (select count(*) from secrets where org_id = 'bbbbbbbb-0000-0000-0000-000000000001')::int,
  0,
  'Supervisor A NO ve el secreto de la org B'
);
reset role;

-- --- 8. Relaciones: aislamiento por org ---------------------------------
-- Control positivo PRIMERO: admin A ve exactamente la 1 relacion de su org.
-- Sin esto, si la fixture insertara 0 filas (p.ej. un rename de la clave 'usa'
-- en el seed), la asercion de aislamiento pasaria por la razon equivocada.
select _login('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from relationships)::int, 1,
  'Admin A ve exactamente 1 relacion en su org (control positivo: la fixture no esta vacia)');
reset role;

select _login('b0000000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from relationships)::int, 0,
  'Admin B no ve la relacion creada en la org A');
reset role;

-- --- 9. Historial append-only: no se puede update/delete ----------------
select _login('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select throws_ok(
  $$delete from entity_history$$,
  '42501',
  null,
  'Nadie (authenticated) puede DELETE sobre entity_history (append-only)'
);
select throws_ok(
  $$update entity_history set reason = 'x'$$,
  '42501',
  null,
  'Nadie (authenticated) puede UPDATE sobre entity_history (append-only)'
);
reset role;

-- --- 10. Gestión de miembros: solo admin (rank 4) -----------------------
select _login('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select throws_ok(
  $$insert into memberships (org_id, user_id, role, status)
    values ('aaaaaaaa-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','admin','active')$$,
  '42501',
  null,
  'Tecnico NO puede gestionar membresias (role_rank < 4)'
);
reset role;

-- --- 11. Esquema (tipos): solo admin puede crear tipos ------------------
select _login('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select throws_ok(
  $$insert into entity_types (org_id, key, name, archetype)
    values ('aaaaaaaa-0000-0000-0000-000000000001','balanza','Balanza','device')$$,
  '42501',
  null,
  'Tecnico NO puede crear tipos de entidad (role_rank < 4)'
);
reset role;

select _login('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select lives_ok(
  $$insert into entity_types (org_id, key, name, archetype)
    values ('aaaaaaaa-0000-0000-0000-000000000001','balanza','Balanza','device')$$,
  'Admin SI puede crear un tipo de entidad nuevo (meta-modelo, UC-05)'
);
reset role;

-- --- 12. EL TEST CLAVE: manipular el claim active_org_id no da acceso ----
-- Admin de A pone active_org_id = org B en su JWT. Como public.org_id() valida
-- contra memberships (no confia en el claim), no es miembro de B -> ve 0.
select _login('a0000000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from entities)::int, 0,
  'Falsear active_org_id hacia una org ajena NO otorga acceso (D-08: nunca se confia solo en el claim)');
reset role;

-- --- 13. Rol anon (sin sesion): no ve nada, no escribe nada --------------
-- PostgREST expone las tablas al rol `anon` para peticiones no autenticadas.
-- public.org_id() sin JWT es null -> ninguna fila casa -> 0. Frontera siempre presente.
select set_config('request.jwt.claims', '{}', true);
set local role anon;
select is((select count(*) from entities)::int, 0,
  'anon (sin sesion) NO ve ninguna entidad (RLS: public.org_id() es null)');
select is((select count(*) from secrets)::int, 0,
  'anon NO ve ningun secreto');
select throws_ok(
  $$insert into entities (org_id, entity_type_id, name)
    values ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','anon-intruso')$$,
  '42501', null,
  'anon NO puede insertar entidades');
reset role;

-- --- 14. Membresia SUSPENDIDA: aunque el claim afirme la org, no hay acceso
-- public.org_id() exige status='active'; un miembro suspendido -> null -> 0 filas.
-- Es la aplicacion real de una revocacion de acceso a nivel de base de datos.
select _login('a0000000-0000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from entities)::int, 0,
  'Miembro SUSPENDIDO de A NO ve entidades de A (revocacion efectiva a nivel BD)');
select throws_ok(
  $$insert into entities (org_id, entity_type_id, name)
    values ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','susp')$$,
  '42501', null,
  'Miembro suspendido NO puede escribir (public.org_id() null -> with check falla)');
reset role;

-- --- 15. Usuario MULTI-ORG: el claim selecciona la org CORRECTA (no laxo) --
-- El mismo usuario es consulta en A y en B. Con claim=A ve solo A; con claim=B
-- ve solo B; nunca las dos a la vez. Es el escenario canonico de fuga (un
-- consultor sirviendo a dos clientes) y prueba que org_id() no es permisivo.
select _login('a0000000-0000-0000-0000-000000000006', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select ok((select count(*) from entities where org_id = 'aaaaaaaa-0000-0000-0000-000000000001') > 0,
  'Usuario multi-org con claim=A SI ve entidades de A (control positivo)');
select is((select count(*) from entities where org_id = 'bbbbbbbb-0000-0000-0000-000000000001')::int, 0,
  'Usuario multi-org con claim=A NO ve ninguna entidad de B');
reset role;
select _login('a0000000-0000-0000-0000-000000000006', 'bbbbbbbb-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from entities where org_id = 'aaaaaaaa-0000-0000-0000-000000000001')::int, 0,
  'El mismo usuario con claim=B NO ve ninguna entidad de A (cambio de contexto sin fuga)');
reset role;

-- --- 16. Satelites (comentarios / etiquetas): no cruzan de tenant --------
select _login('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from comments)::int, 1,
  'Tecnico A ve el comentario de su org (control positivo)');
select is((select count(*) from entity_tags)::int, 1,
  'Tecnico A ve el vinculo de etiqueta de su org (control positivo)');
reset role;
select _login('b0000000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from comments)::int, 0,
  'Admin B NO ve comentarios de la org A (satelite aislado)');
select is((select count(*) from entity_tags)::int, 0,
  'Admin B NO ve vinculos de etiqueta de la org A');
select is((select count(*) from tags)::int, 0,
  'Admin B NO ve tags de la org A');
reset role;

-- --- 17. Meta-modelo: un tipo/campo CUSTOM de A no es visible ni escribible
-- por B; y NADIE puede escribir campos sobre un tipo de SISTEMA (hueco de
-- 0009 corregido: fields_write acotado a los tipos de la propia org).
-- (Test 11 ya creo el entity_type 'balanza' en A como admin.)
select _login('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select lives_ok(
  $$insert into field_definitions (entity_type_id, key, label, data_type)
    select id, 'capacidad_kg', 'Capacidad (kg)', 'number'
    from entity_types where key = 'balanza' and org_id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  'Admin A SI puede añadir un campo a SU propio tipo custom (balanza)');
select throws_ok(
  $$insert into field_definitions (entity_type_id, key, label, data_type)
    values ('00000000-0000-0000-0000-000000000001','backdoor','Backdoor','text')$$,
  '42501', null,
  'Admin A NO puede añadir un campo a un tipo de SISTEMA (no contamina esquema compartido)');
reset role;
select _login('b0000000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from entity_types where key = 'balanza')::int, 0,
  'Admin B NO ve el tipo custom "balanza" creado por A');
select ok((select count(*) from entity_types where org_id is null) > 0,
  'Admin B SI ve los tipos de SISTEMA (org_id null) — control positivo');
select is((select count(*) from field_definitions where key = 'capacidad_kg')::int, 0,
  'Admin B NO ve el campo custom de un tipo de otra org (field_definitions aislado)');
reset role;

-- --- 18. Auditoria: solo admin de la propia org; append-only ------------
select _login('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from audit_log)::int, 0,
  'Tecnico A NO ve el audit_log (rank < 4)');
reset role;
select _login('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from audit_log)::int, 1,
  'Admin A ve exactamente 1 entrada de auditoria (la suya)');
select is((select count(*) from audit_log where org_id = 'bbbbbbbb-0000-0000-0000-000000000001')::int, 0,
  'Admin A NO ve la auditoria de la org B');
select throws_ok($$delete from audit_log$$, '42501', null,
  'Nadie (authenticated) puede DELETE sobre audit_log (append-only, revoke 0008)');
select throws_ok($$update audit_log set action = 'x'$$, '42501', null,
  'Nadie (authenticated) puede UPDATE sobre audit_log (append-only)');
reset role;

-- --- 19. Access token hook: inyecta la org activa CORRECTA en el JWT (T-017)
-- En produccion lo invoca supabase_auth_admin; aqui se ejerce como superusuario.
-- La propiedad de seguridad clave: el hook NUNCA inyecta una org de la que el
-- usuario no sea miembro ACTIVO.
reset role;
select is(
  public.custom_access_token_hook(
    jsonb_build_object(
      'user_id', 'a0000000-0000-0000-0000-000000000001', 'claims', '{}'::jsonb)
  ) #>> '{claims,active_org_id}',
  'aaaaaaaa-0000-0000-0000-000000000001',
  'Hook: admin A recibe active_org_id = su org');
select is(
  public.custom_access_token_hook(
    jsonb_build_object(
      'user_id', 'a0000000-0000-0000-0000-000000000001', 'claims', '{}'::jsonb)
  ) #>> '{claims,active_role}',
  'admin',
  'Hook: admin A recibe active_role = admin');
select ok(
  (public.custom_access_token_hook(
    jsonb_build_object(
      'user_id', 'a0000000-0000-0000-0000-000000000005', 'claims', '{}'::jsonb)
  ) #> '{claims,active_org_id}') is null,
  'Hook: miembro SUSPENDIDO no recibe active_org_id (revocacion en la emision del token)');
select ok(
  (public.custom_access_token_hook(
    jsonb_build_object(
      'user_id', 'a0000000-0000-0000-0000-000000000006', 'claims', '{}'::jsonb)
  ) #>> '{claims,active_org_id}') in
    ('aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001'),
  'Hook: usuario multi-org recibe una de SUS orgs (jamas una ajena)');

-- Seguridad: un usuario autenticado NO puede ejecutar el hook (execute revocado).
select _login('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001');
set local role authenticated;
select throws_ok(
  $$select public.custom_access_token_hook('{}'::jsonb)$$,
  '42501', null,
  'authenticated NO puede ejecutar el hook (solo supabase_auth_admin)');
reset role;

-- --- 20. Bootstrap de org: ver las propias membresias SIN org activa (T-017) -
-- Con el claim active_org_id ausente, public.org_id() es null; aun asi el usuario
-- ve SUS membresias (policy memberships_select_self) para resolver/elegir org,
-- y NUNCA las de otros usuarios.
select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', 'a0000000-0000-0000-0000-000000000006', 'role', 'authenticated')::text,
  true);
set local role authenticated;
select ok((select count(*) from memberships) >= 2,
  'Sin org activa, el usuario multi-org ve sus 2 membresias propias (bootstrap)');
select is(
  (select count(*) from memberships
     where user_id <> 'a0000000-0000-0000-0000-000000000006')::int,
  0,
  'Bootstrap: solo ve SUS membresias, ninguna de otros usuarios');
reset role;

select * from finish();
rollback;
