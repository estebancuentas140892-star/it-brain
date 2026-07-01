# 06 · Casos de uso principales

> Flujos end-to-end sobre la arquitectura ya cerrada (03 modelo · 04 permisos · 05 base de datos).
> No se diseña nada nuevo aquí: se describe cómo interactúan las piezas existentes.
> Formato: Actor → Precondición → Flujo principal → Alternativas/errores → Postcondición → Trazado a esquema.

---

## UC-01 · Buscar y encontrar (el caso fundacional)

> *"El técnico recibe una llamada, escribe cualquier palabra y encuentra todo en <10 s"* — Constitución, principio más importante.

- **Actor:** cualquier rol autenticado (Consulta+).
- **Precondición:** sesión activa con `active_org_id` resuelto.
- **Flujo principal:**
  1. El usuario escribe un término libre (`POS 14`, `192.168.1.30`, `no imprime`, `Epson`).
  2. El cliente envía el término a una función de búsqueda combinada (RPC): FTS (`search_vector`) + similitud trigram (`name`) +, si no hay resultados fuertes, similitud semántica (`embedding`).
  3. El backend aplica RLS automáticamente: solo se ven filas de `org_id = public.org_id()`.
  4. Resultados ordenados por relevancia; cada resultado muestra tipo, estado y 1–2 relaciones destacadas (preview del vecindario, sin navegar aún).
  5. El usuario abre un resultado → UC-02.
- **Alternativas / errores:**
  - Sin resultados exactos → se relajan umbrales de trigram y se muestra "resultados aproximados".
  - Término ambiguo (coincide con varios tipos) → se agrupan resultados por arquetipo.
  - Usuario Consulta busca una credencial → ve solo metadatos (usuario, sistema, URL), nunca el secreto (política `secrets_select`, rank ≥ 3).
- **Postcondición:** se registra en `recent_views` la entidad finalmente abierta (no cada tecleo).
- **Trazado a esquema:** `entities.search_vector` (GIN), `entities.name` (`pg_trgm`), `entities.embedding` (`ivfflat`); policy `entities_select`; función RPC de búsqueda combinada (a detallar en el entregable 09 · API).
- **Objetivo de rendimiento:** primer resultado útil en <300 ms server-side (deja margen sobrado para el <10 s percibido por el usuario, que incluye escribir y decidir).

---

## UC-02 · Ver el vecindario de una entidad

> *El usuario nunca piensa "dónde está la información" — navega relaciones.*

- **Actor:** cualquier rol autenticado.
- **Precondición:** la entidad existe y pertenece a la org activa.
- **Flujo principal:**
  1. Se abre la vista de detalle de la entidad (ficha).
  2. Se cargan en paralelo: campos propios (`data` renderizado según `field_definitions` del tipo), adjuntos, comentarios, y **relaciones a 1 salto** (`relationships` por `source_entity_id` o `target_entity_id`), agrupadas por `relationship_type` con su `inverse_name` cuando corresponde.
  3. El usuario puede expandir cualquier entidad relacionada in-place (mini preview) o navegar (push) a su ficha completa, repitiendo el ciclo.
  4. Campos marcados `sensitivity = sensitive` se muestran u ocultan según `min_role_read` del campo vs. rol del usuario (enmascarado en la capa API, no en RLS — ver entregable 04 §5).
- **Alternativas / errores:**
  - Entidad archivada (`archived_at is not null`) → se muestra con badge "Archivada", visible pero no editable salvo Admin/Supervisor.
  - Relación con `valid_to` pasado → se muestra atenuada en una sección "Relaciones históricas", no mezclada con las vigentes.
- **Postcondición:** se registra/actualiza `recent_views (user_id, entity_id)`; si el usuario la marca, se crea fila en `favorites`.
- **Trazado a esquema:** `relationships` (índices `idx_rel_source`/`idx_rel_target`), `field_definitions.sensitivity/min_role_read`, `attachments`, `comments`, `favorites`, `recent_views`.

---

## UC-03 · Registrar y resolver un incidente

> El caso que convierte un problema puntual en conocimiento permanente (Constitución, regla 17).

- **Actor:** Técnico+.
- **Precondición:** existe (o se crea en el mismo flujo) la entidad `case` afectada.
- **Flujo principal:**
  1. Técnico crea entidad tipo `Incidente` (arquetipo `case`): prioridad, descripción, equipo afectado.
  2. Se crea automáticamente la relación `Incidente —afecta_a→ <entidad afectada>`.
  3. Durante el diagnóstico, el técnico **busca** (UC-01) si existe un procedimiento o incidente similar → si lo encuentra y lo aplica, se crea la relación `Incidente —resuelto_por→ Procedimiento` (o `—similar_a→ Incidente previo`).
  4. Al cerrar: se registra diagnóstico, causa, solución y tiempo de resolución; `status` pasa a `resuelto`.
  5. **Aprendizaje automático (Constitución, sección homónima):** si el sistema detecta que este mismo tipo de incidente ya ocurrió N veces sobre entidades del mismo tipo sin un procedimiento asociado, sugiere: *"¿Convertir esta solución en un procedimiento permanente?"* → si se acepta, se crea una entidad `Knowledge/Procedimiento` pre-rellenada y relacionada.
- **Alternativas / errores:**
  - Incidente sin equipo afectado identificable (ej. problema de proceso) → se permite relacionar contra una entidad `Location` o `Party` en su lugar; el modelo no lo impide (Constitución, regla 3: todo se relaciona con todo).
  - Consulta intenta crear un incidente → bloqueado por policy `entities_insert` (rank ≥ 2).
- **Postcondición:** nueva entidad `case` + relaciones creadas; cambios de `status`/`data` quedan en `entity_history` vía trigger automático.
- **Trazado a esquema:** `entities` (tipo `case`), `relationships` + `relationship_types` (`afecta_a`, `resuelto_por`, `similar_a`), `entity_history` (trigger `trg_entities_history`).

---

## UC-04 · Consultar y revelar una credencial

> El único punto donde seguridad y velocidad de resolución chocan a propósito — y se resuelve con auditoría, no con fricción excesiva.

- **Actor:** consulta de metadatos = cualquier rol; revelado = Supervisor+ (o Técnico con *grant*, v2).
- **Precondición:** la credencial (arquetipo `credential`) existe; el secreto vive en `secrets`, referenciado por `credential_entity_id`.
- **Flujo principal:**
  1. Cualquier usuario encuentra la credencial vía UC-01/UC-02 y ve sus metadatos (sistema relacionado, usuario, URL, expiración) — nunca el secreto.
  2. Si necesita el secreto, pulsa "Revelar" → el cliente llama a la función RPC `reveal_secret(secret_id)` (`security definer`).
  3. La función valida rol (`role_rank() >= 3` o grant explícito), descifra `ciphertext`, inserta una fila en `secret_access_log` (`action = 'reveal'`, IP, user agent) y devuelve el valor **una sola vez** (no se cachea en cliente más allá de la sesión de vista).
  4. El secreto se muestra con opción de copiar y un aviso visual "Esta consulta ha sido registrada".
- **Alternativas / errores:**
  - Técnico sin grant intenta revelar → RPC rechaza; se le sugiere "Solicitar acceso a Supervisor" (v2: flujo de solicitud).
  - Secreto expirado (`credential.data.expiration < now()`) → se revela igual (para poder rotarlo) pero con badge "Expirada".
- **Postcondición:** fila nueva en `secret_access_log`; **nunca** se modifica `entity_history` de la credencial con el valor del secreto (no se audita el *valor*, solo el *acceso*).
- **Trazado a esquema:** `secrets`, `secret_access_log`, policies `secrets_select`/`secret_log_select`; función RPC descrita en el entregable 09 (API) — es la pieza server-side que hace cumplir D-05.

---

## UC-05 · Crear un tipo de entidad y sus campos desde configuración

> La prueba de que "no hay que rediseñar cuando aparece un activo nuevo" (Constitución, regla 7).

- **Actor:** Administrador.
- **Precondición:** ninguna — es la operación que habilita todo lo demás.
- **Flujo principal:**
  1. Admin entra a Configuración → Tipos de entidad → "Nuevo tipo".
  2. Elige un **arquetipo** base (ej. `device`) y define `key`/`name`/`icon`/`color` → se crea fila en `entity_types` con `org_id` propio (no de sistema).
  3. Añade campos personalizados (ej. "Voltaje de operación", tipo `number`; "Certificado ATEX", tipo `bool`) → cada uno crea una fila en `field_definitions`, marcando `is_searchable`, `sensitivity`, `min_role_write` según corresponda.
  4. El formulario de creación/edición de entidades de ese tipo se **renderiza dinámicamente** a partir de `field_definitions` — sin ningún despliegue de código.
  5. Si un campo es `data_type = reference`, Admin elige a qué `entity_type_id` apunta — este campo, al rellenarse en una entidad, crea automáticamente una fila en `relationships`.
- **Alternativas / errores:**
  - Admin intenta editar un tipo `is_system = true` → bloqueado; solo puede *derivar* un tipo propio (v2: herencia vía `parent_type_id`, ver cuestión abierta del entregable 03).
  - Técnico intenta esta operación → bloqueado por policy `types_write`/`fields_write` (rank ≥ 4).
- **Postcondición:** nuevo tipo utilizable de inmediato por cualquier miembro con permiso de creación (UC de creación de entidad estándar, no descrito aparte).
- **Trazado a esquema:** `entity_types`, `field_definitions`, policies `types_write`/`fields_write`; el campo `reference` es el puente meta-modelo ↔ grafo descrito en el entregable 03 §4.

---

## UC-06 · Adjuntar evidencia a una entidad (foto, captura, video)

- **Actor:** Técnico+.
- **Flujo principal:** captura/selecciona archivo → sube a Supabase Storage → se crea fila en `attachments` (`entity_id`, `kind`, `storage_path`) → visible de inmediato en la ficha (UC-02).
- **Postcondición:** el adjunto queda disponible para cualquier miembro de la org con acceso de lectura a esa entidad.
- **Trazado a esquema:** `attachments`, policy `attachments_write` (rank ≥ 2).
- **Nota UX:** esta es la acción de "menos clics" por excelencia (Constitución, regla 8) — debe poder hacerse en una sola pantalla desde la cámara del celular sin pasos intermedios.

---

## UC-07 · Invitar usuario y asignar rol

- **Actor:** Administrador.
- **Flujo principal:** Admin invita por email → se crea `membership (status='invited', role=<elegido>)` → al primer login del invitado, `status` pasa a `active` → el usuario queda con `active_org_id` resuelto para esa org.
- **Alternativas:** Admin cambia el `role` de un miembro existente → se registra en `audit_log` (`action = 'role_changed'`).
- **Postcondición:** el nuevo rol aplica de inmediato (las funciones `public.role_rank()` se evalúan en cada request, no hay caché de permisos que invalidar).
- **Trazado a esquema:** `memberships`, `audit_log`, policy `memberships_write` (rank ≥ 4).

---

## Matriz de trazabilidad (resumen)

| Caso de uso | Tablas principales | Policies clave | Regla de Constitución que valida |
|---|---|---|---|
| UC-01 Buscar | `entities`, índices FTS/trgm/vector | `entities_select` | 1 (búsqueda > navegación) |
| UC-02 Vecindario | `relationships`, `field_definitions` | `entities_select` | 3 (todo se relaciona) |
| UC-03 Incidente | `entities`, `relationships`, `entity_history` | `entities_insert/update` | 17 (incidente → conocimiento) |
| UC-04 Credencial | `secrets`, `secret_access_log` | `secrets_select` (rank≥3) | 19/D-05 (seguridad de secretos) |
| UC-05 Nuevo tipo | `entity_types`, `field_definitions` | `types_write` (rank≥4) | 7 (no rediseñar) |
| UC-06 Adjunto | `attachments` | `attachments_write` | 8 (mínimos clics) |
| UC-07 Invitar usuario | `memberships`, `audit_log` | `memberships_write` (rank≥4) | 5/13 (trazabilidad) |

---

## Cuestiones abiertas

1. **Umbral exacto de relajación de búsqueda** (cuándo pasar de FTS a trigram a semántica): se
   afinará empíricamente en el entregable 11 (estrategia de búsqueda) con datos reales.
2. **Flujo de solicitud de grant** (UC-04, Técnico sin acceso) queda anotado como v2, coherente con
   `entity_grants` diferido en el entregable 04.
3. **Sugerencia automática de procedimiento** (UC-03 paso 5): el umbral "N veces" y el disparador
   exacto se definen en el entregable 12 (estrategia de IA).

---

### Próxima tarea
**T-005 · Navegación y arquitectura de información** (entregable 07) — cómo se organizan estos
casos de uso en pantallas y jerarquía de navegación (tabs, drill-down, breadcrumbs del grafo).
