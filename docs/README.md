# IT Brain — Documentación de Arquitectura

> El "segundo cerebro" del propio proyecto. Cada entregable del roadmap vive aquí como
> documento vivo. **Primero se diseña y se valida; solo después se desarrolla.**

---

## Decisiones fundacionales (bloqueadas)

Estas decisiones ya están tomadas y condicionan todo lo demás. Cambiarlas requiere una
nueva ADR (Architecture Decision Record) justificada.

| # | Decisión | Elección | Consecuencia principal |
|---|----------|----------|------------------------|
| D-01 | **Modelo de despliegue** | Single-tenant en operación, **multi-tenant en el esquema** | `org_id` + RLS en todas las tablas desde el día 1; validamos con una sola empresa |
| D-02 | **Alcance offline (MVP)** | **Caché de solo lectura** de favoritos / recientes / críticos | Se descarta la sincronización bidireccional en el MVP (es v2+); reduce drásticamente el riesgo |
| D-03 | **Motor de búsqueda** | **PostgreSQL nativo** (FTS + `pg_trgm` + `pgvector`) tras una abstracción | Sin infraestructura extra; migrable a Typesense/Meilisearch si un benchmark lo justifica |
| D-04 | **Modelo de datos** | **Híbrido**: columnas tipadas + `JSONB` + tabla de aristas + tipos dirigidos por datos | Se evita el anti-patrón EAV puro y el *inner-platform effect* |
| D-05 | **Credenciales** | Secreto **cifrado, nunca indexado en texto plano**; se busca por metadatos | La búsqueda no compromete la seguridad; acceso auditado |
| D-06 | **IA** | **RAG anclado** al grafo con citas y *fallback* "no encontré información" | Se mitiga la alucinación y toda respuesta es verificable (no se elimina al 100%) |

---

## Gestión operativa

- **Tablero de tareas** (una sola tarea activa, flujo automático): [TASKS.md](TASKS.md)
- **Historial de tareas completadas:** [CHANGELOG.md](CHANGELOG.md)

---

## Roadmap de entregables

### Fase 0 — Fundamentos
- [ ] 01 · Visión del producto
- [ ] 02 · Arquitectura general
- [x] **03 · Modelo de Entidades + Relaciones** ← *en curso* ([documento](03-modelo-entidades-relaciones.md))
- [x] **04 · Multi-tenancy y modelo de permisos** ([documento](04-multitenancy-permisos.md))

### Fase 1 — Producto
- [x] **05 · Base de datos** (esquema físico, índices, RLS, triggers) ([documento](05-base-de-datos.md))
- [x] **06 · Casos de uso** ([documento](06-casos-de-uso.md))
- [x] **07 · Navegación** ([documento](07-navegacion.md))
- [x] **08 · Wireframes / UX** ([documento](08-wireframes-ux.md))

### Fase 2 — Plataforma
- [x] **09 · API** ([documento](09-api.md))
- [x] **10 · Seguridad** ([documento](10-seguridad.md))
- [x] **11 · Estrategia de búsqueda** ([documento](11-busqueda.md))
- [x] **12 · Estrategia de IA** ([documento](12-ia-rag.md))
- [x] **13 · Estrategia de sincronización y offline** ([documento](13-offline-sync.md))

### Fase 3 — Ejecución
- [x] **14 · Alcance del MVP** ([documento](14-alcance-mvp.md)) — *cierre de la fase de diseño*
- [ ] 15 · Roadmap de versiones
- [ ] 16 · Backlog
- [ ] 17 · Estrategia de despliegue
- [ ] 18 · Estrategia de crecimiento

### Fase 4 — Implementación ← *en curso*
Ver secuencia de construcción en [14-alcance-mvp.md §5](14-alcance-mvp.md#5-secuencia-de-construcción-recomendada)
y el tablero [TASKS.md](TASKS.md) para el detalle paso a paso.

---

## Stack de referencia
Frontend **Flutter** (Android · iOS · Windows · Web · Tablet, base única) · Estado **Riverpod** ·
Arquitectura **Clean + MVVM** · Backend **Supabase** (PostgreSQL · Auth · Storage · RLS) ·
Búsqueda **Postgres FTS + pg_trgm + pgvector**.
