# 09 · Diseño de la API

> Contrato formal que sirve las pantallas (08) sobre el esquema (05) y los permisos (04).
> Principio de arquitectura: **usar todo lo que Supabase da gratis (PostgREST + RLS) y añadir
> lógica propia solo donde aporta** — atomicidad, seguridad reforzada o cómputo que SQL no cubre.

---

## 1. Decisiones de este entregable

| # | Decisión | Elección | Motivo |
|---|----------|----------|--------|
| D-12 | **Estilo de API** | PostgREST (auto) + **RPC de Postgres** + **Edge Functions**, según necesidad | Menos código propio = menos superficie de bug/seguridad |
| D-13 | **CRUD básico** | **PostgREST auto-generado**, protegido solo por RLS | El SDK de Flutter habla directo; RLS ya es la frontera dura (05 §9) |
| D-14 | **Operaciones compuestas** | **RPC `security invoker`** por defecto; `security definer` solo cuando es imprescindible | `invoker` conserva RLS; `definer` es la excepción auditada |
| D-15 | **Secretos y cómputo externo** | **Edge Functions** (embeddings, descifrado, IA futura) | Necesitan claves/`service_role`/red que nunca deben tocar el cliente |
| D-16 | **Versionado** | Prefijo `rpc/v1_*` en funciones públicas; *breaking changes* → nueva versión conviviendo | Permite evolucionar sin romper clientes desplegados (Constitución 11) |

---

## 2. Las tres capas del API — cuándo se usa cada una

```
┌────────────────────────────────────────────────────────────┐
│ CLIENTE (Flutter · supabase-dart)                          │
└───────────┬─────────────────┬───────────────────┬──────────┘
            │                 │                   │
            ▼                 ▼                   ▼
   ┌────────────────┐ ┌────────────────┐ ┌──────────────────┐
   │ PostgREST      │ │ RPC Postgres   │ │ Edge Functions   │
   │ (CRUD + RLS)   │ │ (compuestas)   │ │ (claves/red/IA)  │
   ├────────────────┤ ├────────────────┤ ├──────────────────┤
   │ leer/crear/    │ │ búsqueda,      │ │ reveal_secret,   │
   │ editar         │ │ vecindario,    │ │ embed+semántica, │
   │ entidades,     │ │ crear/cerrar   │ │ asistente IA     │
   │ relaciones,    │ │ incidente      │ │ (entregable 12)  │
   │ tags, comments │ │                │ │                  │
   └───────┬────────┘ └───────┬────────┘ └────────┬─────────┘
           │                  │                    │
           ▼                  ▼                    ▼ (service_role)
   ┌──────────────────────────────────────────────────────────┐
   │ PostgreSQL — RLS activo en todas las tablas de negocio     │
   └──────────────────────────────────────────────────────────┘
```

**Regla de oro:** el cliente **nunca** usa `service_role`. Solo las Edge Functions lo hacen, y cada
una revalida identidad y permiso manualmente antes de actuar.

---

## 3. Convenciones transversales

- **Autenticación:** JWT de Supabase Auth en cada request; `active_org_id` como claim. RLS y las
  funciones resuelven org/rol vía `public.org_id()` / `public.role_rank()` (05 §1).
- **Paginación:** *keyset* (`created_at`/`id` como cursor) en listados grandes; `limit` por defecto
  25, máximo 100. Nada de `offset` profundo (degrada con decenas de miles de filas).
- **Errores:** modelo uniforme `{ code, message, details? }`. Códigos de dominio propios
  (`FORBIDDEN_ROLE`, `SECRET_ACCESS_DENIED`, `ENTITY_NOT_FOUND`, `VALIDATION_ERROR`) además del
  HTTP status. Nunca se filtra información de otra org (un recurso de otro tenant devuelve
  `404`, no `403`, para no revelar su existencia).
- **Idempotencia:** las mutaciones que el cliente pueda reintentar (crear incidente offline→online)
  aceptan un `client_request_id` para deduplicar en el servidor.
- **Formato:** JSON; timestamps ISO-8601 UTC.

---

## 4. Capa PostgREST (CRUD auto-generado + RLS)

Se expone directamente, sin código propio. La seguridad es **100 % RLS** (05 §9).

| Recurso | Operaciones | Rol mínimo (vía RLS) | Notas |
|---------|-------------|----------------------|-------|
| `entities` | select / insert / update | read: consulta · write: técnico | `archived_at` para baja lógica; nunca DELETE físico |
| `relationships` | select / insert / delete | read: consulta · write: técnico | alta/baja de aristas del grafo |
| `entity_types`, `field_definitions` | select (todos) · write (admin) | write: admin | crear tipos/campos = INSERT (regla 7) |
| `tags`, `entity_tags` | select / insert / delete | write: técnico | etiquetas globales por org |
| `attachments` | select / insert / delete | write: técnico | binario en Storage; fila = metadato |
| `comments` | select / insert | write: técnico | |
| `favorites`, `recent_views` | select / insert / delete | dueño (cualquier rol) | policy `*_own` (user_id = auth.uid()) |
| `memberships` | select · write (admin) | write: admin | invitar / cambiar rol |
| `secrets` | **select (solo ciphertext)** | supervisor+ | select directo devuelve bytes cifrados **inútiles** sin la clave; el descifrado real va por Edge Function (§6) |

> Los adjuntos usan **Signed URLs** de Supabase Storage (caducas), no URLs públicas — el acceso al
> binario se autoriza igual que el acceso a la entidad.

---

## 5. Capa RPC de Postgres (operaciones compuestas)

Funciones SQL/PLpgSQL invocadas con `supabase.rpc(...)`. **`security invoker`** salvo que se indique,
de modo que RLS sigue aplicando y no hay riesgo de fuga entre tenants.

### 5.1 `v1_search_entities` — búsqueda léxica (UC-01)

```
v1_search_entities(q text, p_limit int default 25, p_cursor uuid default null)
  returns table(id, name, type_key, archetype, status, snippet, rank, top_relations jsonb)
  security invoker  -- RLS filtra por org automáticamente
```
- Combina FTS (`search_vector @@ websearch_to_tsquery`) + similitud trigram sobre `name`
  (`similarity(name, q)`), con *ranking* ponderado. Si el mejor `rank` FTS es débil, eleva el peso
  del trigram (degradación tolerante a errores, entregable 06 UC-01).
- `top_relations`: 1–2 relaciones destacadas por resultado (preview de vecindario sin navegar, 08 §2).
- **No** incluye búsqueda semántica: eso es Edge Function (§6.2), porque requiere generar el
  embedding de `q`.

### 5.2 `v1_entity_neighborhood` — vecindario paginado (UC-02)

```
v1_entity_neighborhood(p_entity_id uuid, p_limit int default 50, p_cursor uuid default null)
  returns jsonb  -- { entity, fields[], relations[]{ type, direction, target_summary }, counts }
  security invoker
```
- Devuelve la entidad + sus relaciones a **1 salto**, agrupadas por tipo, con el resumen de cada
  entidad relacionada (para pintar la ficha sin N requests). Los saltos siguientes son llamadas
  nuevas (drill-down `push`, entregable 07 §3).
- Campos con `sensitivity` que el rol no alcanza se **omiten del payload** aquí mismo (no se envían
  al cliente y se enmascaran en UI) — el enmascarado de grano fino ocurre en servidor (04 §5).

### 5.3 `v1_create_incident` — alta atómica (UC-03)

```
v1_create_incident(p_affected_entity_id uuid, p_priority text, p_description text,
                   p_client_request_id uuid default null)
  returns jsonb  -- { incident, similar_incidents[] }
  security invoker  -- los INSERT quedan sujetos a RLS (requiere técnico+)
```
- En una transacción: crea la entidad `case`, crea la relación `afecta_a`, y devuelve **incidentes
  similares** (por embedding de la descripción vía §6.2, o por trigram si no hay embedding) para el
  panel "Incidentes similares" en vivo (08 §4).
- Idempotente vía `p_client_request_id` (soporta reintento offline→online).

### 5.4 `v1_close_incident` — cierre + aprendizaje (UC-03)

```
v1_close_incident(p_incident_id uuid, p_diagnosis text, p_cause text, p_solution text,
                  p_resolution_seconds int, p_procedure_id uuid default null)
  returns jsonb  -- { incident, suggest_procedure bool, repeat_count int }
  security invoker
```
- Registra la solución, cambia `status`, opcionalmente crea `resuelto_por → procedimiento`.
- Calcula `repeat_count` (incidentes del mismo patrón sobre el mismo tipo) y devuelve
  `suggest_procedure` cuando supera el umbral → dispara el banner de aprendizaje automático (08 §4).
  El umbral exacto se cierra en el entregable 12 (IA).

### 5.5 `v1_match_entities` — vecino semántico (soporte para §6.2)

```
v1_match_entities(p_embedding vector(1536), p_limit int default 10, p_threshold float default 0.75)
  returns table(id, name, type_key, similarity)
  security invoker  -- RLS aplica; solo devuelve entidades de la org del invocador
```
- Búsqueda por distancia coseno sobre `entities.embedding` (índice `ivfflat`, 05 §3). La llama la
  Edge Function de búsqueda semántica pasando el JWT del usuario, de modo que RLS scoping se mantiene.

---

## 6. Capa Edge Functions (claves, red externa, IA)

Deno/TypeScript. Usan `service_role` y/o claves externas. **Cada una hace: (1) validar JWT →
(2) resolver membership+rol → (3) actuar → (4) auditar.**

### 6.1 `reveal-secret` — descifrado auditado (UC-04, D-05)

```
POST /functions/v1/reveal-secret   { secret_id, client_meta? }
  → 200 { value, logged_at }   |   403 SECRET_ACCESS_DENIED
```
1. Autentica el JWT y resuelve `membership`. Exige `role_rank >= 3` **o** `entity_grant` explícito
   (v2). Si no, `403` sin descifrar nada.
2. Lee `secrets.ciphertext` con `service_role` y lo **descifra con la clave**, que vive **solo aquí**
   (variable de entorno / KMS — la gestión concreta se decide en el entregable 10). *La clave nunca
   está en la base de datos ni en el cliente.*
3. Inserta en `secret_access_log` (`action='reveal'`, IP, user agent) **en la misma operación** —
   la auditoría no depende de que el cliente coopere.
4. Devuelve el valor **una sola vez**.

> Por eso el `select` directo de `secrets` (§4) es seguro aunque lo permita RLS a supervisores:
> devuelve solo bytes cifrados, ilegibles sin la clave que custodia esta función. Defensa en
> profundidad real.

### 6.2 `search-semantic` — embedding + match (UC-01 avanzado, UC-03 similares)

```
POST /functions/v1/search-semantic   { q }        (o { description } para incidentes similares)
  → 200 { results[] }
```
1. Genera el embedding de `q` llamando al modelo de embeddings (clave externa, solo aquí).
2. Invoca `v1_match_entities(embedding, ...)` **con el JWT del usuario** → RLS garantiza que solo
   se recuperan entidades de su org (nunca fuga entre tenants, ni siquiera vía IA — regla 19).
3. Devuelve resultados fusionables con los léxicos de `v1_search_entities`.

### 6.3 `ai-assistant` — reservado (entregable 12)

El asistente RAG se especifica en el entregable 12. Contrato adelantado: recibe la consulta,
recupera contexto **exclusivamente** vía las RPC/Edge anteriores (bajo el rol del usuario), y nunca
inventa (Constitución, regla 19). Se documenta aquí solo como punto de anclaje.

---

## 7. Reglas de seguridad para funciones `security definer`

En este diseño **ninguna RPC de negocio necesita `definer`** (todas van `invoker` + RLS). Si en el
futuro se introduce alguna, será obligatorio:

1. Fijar `search_path` explícito (`set search_path = ''`) para evitar secuestro de resolución.
2. Revalidar `public.org_id()` y `public.role_rank()` dentro de la función (no confiar en el llamador).
3. Nunca aceptar `org_id` como parámetro de confianza del cliente — derivarlo del JWT.
4. Documentar por qué no puede resolverse con `invoker`.

---

## 8. Rendimiento

- Búsqueda y vecindario se apoyan en los índices ya creados (GIN FTS, `pg_trgm`, `ivfflat`, GIN
  JSONB — 05 §3). Objetivo: `v1_search_entities` < 300 ms server-side (08 §2 / regla 10).
- Payload del vecindario acotado (`p_limit` 50 relaciones/página) para no colapsar fichas de
  entidades muy conectadas (un switch con cientos de puertos).
- Respuestas cacheables (tipos/campos de sistema, `entity_types`) marcadas con `Cache-Control`
  corto; los datos de negocio no se cachean en CDN (dependen de RLS por usuario).

---

## 9. Cumplimiento de la Constitución

| Regla | Cómo se cumple |
|---|---|
| 4 · No depender de personas | Todo el conocimiento se accede por API uniforme, no por saber a quién preguntar |
| 10 · Sensación instantánea | Índices + keyset pagination + objetivo <300 ms |
| 11 · Arquitectura a 10 años | Versionado `v1_*`; capas desacopladas; preparada para microservicios (regla del prompt) |
| 19 · IA solo usa lo almacenado | `search-semantic`/`ai-assistant` invocan RPC bajo el rol del usuario; RLS impide fuga entre tenants o de secretos |

---

## 10. Cuestiones abiertas

1. **Gestión de la clave de descifrado** de `reveal-secret`: env var vs. `pgsodium` vs. KMS externo →
   se decide en el entregable 10 (Seguridad). Afecta solo a la implementación, no al contrato.
2. **Proveedor y dimensión de embeddings**: fija la firma `vector(1536)` de `v1_match_entities` →
   entregable 12 (IA).
3. **Realtime**: ¿suscripción a `entities`/`incidents` vía Supabase Realtime para actualizaciones
   en vivo del dashboard? Recomendación: sí para incidentes abiertos, evaluado en el MVP; no
   bloquea este contrato.
4. **Rate limiting** de Edge Functions (especialmente `search-semantic`, que tiene coste externo):
   a definir en el entregable 10.

---

### Próxima tarea
Fin de la especificación de la API. Siguiente bloque del roadmap: **entregable 10 · Seguridad**
(transversal: gestión de claves, rate limiting, cifrado, checklist OWASP), que además resuelve
varias de las cuestiones abiertas acumuladas (descifrado, rate limit). Se creará como nueva tarea
en el tablero.
