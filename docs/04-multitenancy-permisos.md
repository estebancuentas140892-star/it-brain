# 04 · Multi-tenancy y modelo de permisos

> Define el aislamiento entre organizaciones y el control de acceso por **entidad / campo / acción**.
> Frontera dura en la base de datos (RLS); grano fino en la capa de aplicación. Deriva de la
> decisión **D-01** (multi-tenant en el esquema) y **D-05** (credenciales protegidas).

---

## 1. Decisiones de este entregable

| # | Decisión | Elección | Motivo |
|---|----------|----------|--------|
| D-07 | **Estrategia multi-tenant** | Base y esquema **compartidos**, aislamiento por `org_id` + **RLS** | Estándar Supabase; escala a miles de orgs sin sobrecoste operativo |
| D-08 | **Fuente de autorización** | Tabla `memberships` (verdad) + `org_id` activo como **claim del JWT** | Soporta futuro MSP multi-org sin renunciar a rendimiento |
| D-09 | **Modelo de control de acceso** | **RBAC** (4 roles) de base + capa fina (por tipo/campo/instancia) | Simple por defecto (Constitución 12), extensible sin rediseño |
| D-10 | **Defensa** | **En profundidad**: RLS en BD (obligatoria) + checks en API (UX y grano fino) | Aunque el cliente se comprometa, la BD sigue aislada |
| D-11 | **Campos sensibles** | Secretos en tabla aparte cifrada; otros sensibles enmascarados en API | RLS es por fila, no por columna; se modela para que eso no sea un hueco |

---

## 2. Multi-tenancy

### 2.1 Modelo

**Shared database, shared schema, row-level isolation.** Cada fila de dato de negocio lleva
`org_id NOT NULL`. Postgres RLS garantiza que un usuario solo ve filas de su organización activa.
Las filas "de sistema" (arquetipos, tipos y relaciones globales) usan `org_id IS NULL` = visibles
para todas las organizaciones, no editables por el cliente.

```
organizations
├── id, name, slug, plan, status
├── created_at, settings (jsonb)

memberships                     (quién pertenece a qué org y con qué rol — VERDAD de autorización)
├── id, org_id, user_id (→ auth.users)
├── role     enum (admin | supervisor | tecnico | consulta)
├── status   enum (active | invited | suspended)
├── created_at, invited_by
└── UNIQUE (org_id, user_id)
```

### 2.2 Resolución del tenant (org activa)

1. El usuario inicia sesión con **Supabase Auth** → JWT con `auth.uid()`.
2. Un claim personalizado `active_org_id` indica la organización en la que está operando
   (en operación single-tenant es su única membership; con varias, la seleccionada).
3. Toda política RLS valida **dos cosas**: la fila pertenece a `active_org_id` **y** el usuario es
   `member` activo de esa org. Nunca basta con el claim: se contrasta contra `memberships`.

### 2.3 Funciones de apoyo (en Postgres)

```sql
-- Org activa del usuario, validada contra memberships (nunca confía solo en el claim)
create function public.org_id() returns uuid stable language sql as $$
  select m.org_id
  from memberships m
  where m.user_id = auth.uid()
    and m.status = 'active'
    and m.org_id = (auth.jwt() ->> 'active_org_id')::uuid
  limit 1;
$$;

-- Rango del rol en la org activa (consulta=1 < tecnico=2 < supervisor=3 < admin=4)
create function public.role_rank() returns int stable language sql as $$
  select case m.role
    when 'admin' then 4 when 'supervisor' then 3
    when 'tecnico' then 2 when 'consulta' then 1 else 0 end
  from memberships m
  where m.user_id = auth.uid() and m.org_id = public.org_id() and m.status = 'active';
$$;
```

> `service_role` (backend de confianza / Edge Functions) **omite** RLS. Nunca se expone al cliente;
> solo lo usan funciones servidor auditadas (p. ej. el flujo de revelado de secretos).

---

## 3. Roles (RBAC — capa base)

Cuatro roles jerárquicos. El rango superior hereda las capacidades del inferior.

| Rol | Descripción | Alcance típico |
|-----|-------------|----------------|
| **Administrador** (4) | Dueño técnico de la org | Todo: usuarios, esquema (tipos/campos), credenciales, configuración |
| **Supervisor** (3) | Responsable operativo / curador de conocimiento | Todo el conocimiento y activos; revela credenciales; no gestiona usuarios ni esquema |
| **Técnico** (2) | Operador diario | Lee todo lo no secreto; crea/edita activos, incidentes, procedimientos y relaciones; revela solo credenciales autorizadas |
| **Consulta** (1) | Solo lectura | Consulta lo no sensible; nunca ve secretos ni edita |

---

## 4. Permisos por acción (matriz)

**Verbos de acción:** `read` · `create` · `update` · `archive` (baja lógica, nunca borrado físico) ·
`relate` (gestionar aristas) · `comment` · `attach` · `reveal_secret` · `export` ·
`manage_schema` (tipos/campos) · `admin` (usuarios/roles/org).

| Capacidad | Consulta | Técnico | Supervisor | Admin |
|-----------|:---:|:---:|:---:|:---:|
| Leer entidades no sensibles | ✔ | ✔ | ✔ | ✔ |
| Leer **metadatos** de credencial (usuario, URL, sistema) | ✔ | ✔ | ✔ | ✔ |
| **Revelar secreto** de credencial | ✖ | ◑¹ | ✔ | ✔ |
| Crear / editar activos, redes, software | ✖ | ✔ | ✔ | ✔ |
| Crear / editar incidentes y procedimientos | ✖ | ✔ | ✔ | ✔ |
| Comentar y adjuntar | ✖ | ✔ | ✔ | ✔ |
| Gestionar relaciones (aristas) | ✖ | ✔ | ✔ | ✔ |
| Archivar (baja lógica) | ✖ | ◑² | ✔ | ✔ |
| Exportar / reportes masivos | ✖ | ◑³ | ✔ | ✔ |
| Gestionar esquema (tipos y campos) | ✖ | ✖ | ✖ | ✔ |
| Gestionar usuarios, roles y org | ✖ | ✖ | ✖ | ✔ |

- **◑¹** Técnico revela un secreto **solo** si existe un *grant* explícito (por tipo o por instancia). Siempre auditado.
- **◑²** Técnico archiva solo entidades de las que es `owner` (configurable por org).
- **◑³** Exportar es capacidad activable por org para el rol Técnico (por defecto, no).

---

## 5. Permisos por campo

RLS es **por fila, no por columna**. Se resuelve por diseño, no forzando RLS donde no llega:

1. **Secretos** (`data_type = secret`): nunca viven en `entities.data`. Van a la tabla `secrets`
   cifrada (§7 del [modelo de entidades](03-modelo-entidades-relaciones.md)), con su propia RLS y
   log de acceso. Revelarlos es una acción servidor (`reveal_secret`) que descifra, registra y
   devuelve el valor una sola vez. **Este es el único caso realmente crítico y ya está blindado.**
2. **Campos sensibles no-secretos** (marcados en `field_definitions.sensitivity = sensitive`): al
   estar dentro del JSONB `entities.data`, RLS por columna no aplica. Se enmascaran en la **capa de
   API/RPC** según el rol (defensa en profundidad, no frontera dura). Regla de diseño: *lo que deba
   ser una frontera dura no se guarda en JSONB* — se modela como tabla protegida, como los secretos.
3. **Escritura de campos por rol:** `field_definitions` puede declarar `min_role_write`; la
   validación ocurre en el backend al persistir.

`field_definitions` se amplía con: `sensitivity (normal | sensitive | secret)`,
`min_role_read`, `min_role_write`.

---

## 6. Permisos por instancia (grants) — esbozo v2

Para casos como "esta credencial de producción solo la ve el equipo de Infra":

```
entity_grants                    (ACL de excepción sobre una entidad concreta)
├── id, org_id, entity_id
├── subject_type enum (user | role | team)
├── subject_id
├── action       enum (read | update | reveal_secret | relate | archive)
├── effect       enum (allow | deny)   -- deny gana sobre allow
└── granted_by, granted_at
```

Resolución de permiso efectivo: `deny` explícito → `allow` explícito → default del rol (matriz §4).
**MVP:** no se implementa la UI ni la tabla; el rol basta. Se deja el diseño reservado para no
rediseñar después (Constitución 7).

---

## 7. Defensa en profundidad — dónde se aplica cada cosa

| Capa | Qué controla | Ejemplos |
|------|--------------|----------|
| **BD (RLS)** — frontera dura | Aislamiento por org + lectura/escritura por rango de rol | `org_id = public.org_id()`; escritura si `role_rank() >= 2` |
| **API / RPC** — grano fino y UX | Acción concreta, enmascarado de campos, revelado de secretos, reglas de negocio | `reveal_secret` con log; ocultar campos `sensitive`; validar `manage_schema` |
| **Cliente (Flutter)** — solo UX | Ocultar botones/campos según rol | Nunca es seguridad: todo se revalida en servidor |

### Ejemplos de políticas RLS (ilustrativas; el DDL final es la tarea T-003)

```sql
alter table entities enable row level security;

-- Lectura: cualquier miembro de la org activa
create policy entities_select on entities for select
  using (org_id = public.org_id());

-- Inserción / edición: técnico o superior, sin cruzar de org
create policy entities_insert on entities for insert
  with check (org_id = public.org_id() and public.role_rank() >= 2);
create policy entities_update on entities for update
  using (org_id = public.org_id() and public.role_rank() >= 2)
  with check (org_id = public.org_id() and public.role_rank() >= 2);

-- Secretos: solo supervisor+ o grant explícito (el descifrado ocurre en RPC servidor)
create policy secrets_select on secrets for select
  using (org_id = public.org_id() and public.role_rank() >= 3);

-- Historial y auditoría: append-only (sin update ni delete para nadie salvo service_role)
revoke update, delete on entity_history, secret_access_log, audit_log from authenticated;
```

---

## 8. Autenticación y MFA

- **Supabase Auth**: email/contraseña en MVP; SSO/SAML y OAuth corporativo en v2.
- **MFA (TOTP / AAL2)**: soportado por Supabase. Política: **obligatorio para Administrador y
  Supervisor**; recomendado/optativo para el resto (configurable por org).
- **Invitaciones**: alta de usuarios por email con rol asignado; membership en estado `invited`
  hasta el primer login.
- **Sesión**: rotación de tokens; el cambio de org activa reemite el claim `active_org_id`.

---

## 9. Auditoría

- `secret_access_log` — cada `view`/`reveal`/`update`/`rotate` de un secreto (quién, cuándo, IP, agente).
- `audit_log` — acciones administrativas: cambios de rol, alta/baja de usuarios, cambios de esquema
  (tipos/campos), grants de permisos, cambios de configuración de la org.
- `entity_history` — cambios de datos a nivel de campo (definido en el entregable 03).

Las tres son **append-only** (Constitución 5 y 13).

---

## 10. Alcance: MVP vs. después

| Elemento | MVP | v2+ |
|----------|:---:|:---:|
| Aislamiento por org + RLS | ✔ | |
| 4 roles + matriz de acciones | ✔ | |
| Secretos cifrados + revelado auditado | ✔ | |
| Enmascarado de campos `sensitive` en API | ✔ | |
| MFA para Admin/Supervisor | ✔ | |
| Grants por instancia (`entity_grants`) | | ✔ |
| Roles personalizados / permisos a medida | | ✔ |
| SSO / SAML corporativo | | ✔ |
| Multi-org real por usuario (MSP) | esquema listo | UI ✔ |

---

## 11. Cumplimiento de la Constitución

| Regla | Cómo se cumple |
|-------|----------------|
| 4 · El conocimiento no depende de una persona | Todo vive en la org, no en el usuario; roles reasignables |
| 5 / 13 · Toda modificación registrada / trazabilidad | `entity_history`, `audit_log`, `secret_access_log` append-only |
| 12 · No romper la simplicidad | RBAC de 4 roles por defecto; el grano fino es opcional y diferido |
| 19 · La IA solo usa conocimiento almacenado | La IA opera bajo el rol del usuario: RLS limita también su recuperación (no filtra datos de otra org ni secretos) |

---

## 12. Cuestiones abiertas

1. **¿MSP multi-org desde ya en la UI?** Recomendación: esquema preparado, UI en v2.
2. **¿Técnico puede archivar solo lo propio o nada?** Recomendación: solo lo propio, configurable.
3. **Rotación de claves de cifrado de secretos**: ¿KMS externo o `pgsodium`/Vault de Supabase?
   → a decidir en el entregable 10 (Seguridad); afecta a `secrets.ciphertext`.
4. **Enmascarado de campos `sensitive`**: ¿vía RPC/vista o filtrado en Edge Function? → se concreta en T-003 (BD) y entregable 09 (API).

---

### Próxima tarea
**T-003 · Base de datos** — aterrizar el esquema físico completo (DDL, índices, las políticas RLS de
este documento, triggers de historial y funciones `public.org_id()` / `public.role_rank()`).
