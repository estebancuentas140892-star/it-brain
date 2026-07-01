# IT Brain — Changelog (tareas completadas)

> Archivo append-only. Las tareas completadas se mueven aquí desde [TASKS.md](TASKS.md),
> más recientes arriba. Nada se elimina (Constitución: nunca perder conocimiento ni trazabilidad).

---

## 2026-07

- **Fix (scaffold T-013)** · El guard del router no reaccionaba al cambio de sesión — *2026-07-01, hallado en la primera corrida real contra Supabase hosted*
  - `app/lib/core/router/app_router.dart`: faltaba `refreshListenable`, así que tras iniciar sesión go_router no re-evaluaba el `redirect` y la app se quedaba en `/login`. Añadido `GoRouterRefreshStream` (puente Stream→Listenable) sobre `auth.onAuthStateChange`.
  - **Primera validación end-to-end contra el backend real:** login → Dashboard funciona contra el proyecto Supabase hosted. `flutter analyze` limpio. Confirma que la config de entorno, la inicialización de Supabase y el flujo de auth del scaffold funcionan de verdad.
- **T-017** · Resolución de organización activa + bootstrap del claim `active_org_id` — *completada 2026-07-01 (validación end-to-end pendiente del backend real)*
  - **Problema:** en el primer login el JWT no trae `active_org_id`, así que `public.org_id()` es null y la RLS bloquea todo; peor, el cliente no puede leer sus propias membresías para elegir org porque la RLS de `memberships` depende de `public.org_id()` (bootstrap circular). Descubierto al implementar T-016.
  - **Solución (mecanismo correcto para MVP single-tenant, D-01):**
    1. `supabase/migrations/0011_auth_access_token_hook.sql`: **Custom Access Token Hook** `public.custom_access_token_hook` (SECURITY DEFINER, `search_path` fijado) que inyecta `active_org_id` + `active_role` en el JWT desde la membresía **activa** del usuario. Un suspendido/invitado no recibe org (revocación desde la emisión del token). `execute` concedido solo a `supabase_auth_admin`, revocado a authenticated/anon/public. Configurado en `config.toml` (`[auth.hook.custom_access_token]`).
    2. `0009`: policy `memberships_select_self` (`user_id = auth.uid()`) — el usuario ve SUS membresías aunque aún no tenga org activa (bootstrap + degradación si el hook no está desplegado + base del selector multi-org de v2). No filtra datos ajenos, no recurre.
    3. Cliente: `activeOrgProvider` ahora lee `active_org_id`/`active_role` del JWT (misma fuente que la RLS → sin divergencia), con la consulta a `memberships` como fallback.
  - **Gate T-015 crece:** grupos 19–20 del test de aislamiento (el hook nunca inyecta una org ajena; solo `supabase_auth_admin` lo ejecuta; el bootstrap no filtra membresías de otros). La suite pasa de 43 a **50 aserciones (21 grupos, 0–20)**.
  - **Verificado:** `flutter analyze` limpio + `flutter test` 3/3. El SQL (hook + policy) se razona y lo confirma la primera corrida en CI/backend, igual que el resto del gate. **Desbloquea el criterio "Hecho cuando" de T-016.**
- **T-015** · Tests de aislamiento de tenant en CI (gate de despliegue) — *completada 2026-07-01, endurecida 2026-07-01*
  - `supabase/tests/0001_tenant_isolation_test.sql`: suite pgTAP, **43 aserciones (19 grupos, 0–18)** tras la revisión rigurosa — lectura/escritura de entidades entre orgs, secretos por rol, relaciones (con control positivo anti "paso por vacío"), historial y auditoría append-only, satélites, meta-modelo, rol `anon`, membresía suspendida, usuario multi-org, y **el test clave**: falsear `active_org_id` en el JWT no da acceso (D-08, se valida contra memberships).
  - **La auditoría (no solo escribir el test) destapó DOS defectos reales, corregidos**, que un test superficial habría tapado con luz verde falsa:
    1. **Recursión infinita de RLS** — `public.org_id()`/`public.role_rank()` (0002) no eran `SECURITY DEFINER`, pero la RLS de `memberships` (0009) se define sobre `public.org_id()`: leer memberships dentro de la función re-disparaba su RLS → `infinite recursion detected in policy`. **Ninguna consulta autenticada habría funcionado.** Corregido con `security definer` + `search_path` fijado; el Test 0 lo vigila.
    2. **`fields_write` sin ámbito de org** (0009) — cualquier admin podía añadir campos a un tipo de **sistema** (visible cross-org), contaminando el esquema compartido. Acotado a tipos de la propia org; el Test 17 lo vigila.
  - `.github/workflows/ci.yml`: job `tenant-isolation` (supabase start → test db) como gate no negociable + job flutter (analyze/test). `supabase/config.toml` para la CLI.
  - **NO ejecutado localmente** (sin Docker/Supabase; C: sin espacio). Por diseño (D-21) el enforcement vive en CI; la primera corrida verde ocurrirá al inicializar git + push, y es la que **confirma los dos arreglos**. El README de tests documenta que el gate CRECE: cada RPC/Edge futura debe añadir su test de aislamiento.
- **T-014** · Migraciones del esquema completo + RLS + seed (paso 2 de la secuencia) — *completada 2026-07-01*
  - `supabase/migrations/0001..0010`: extensiones, multi-tenancy (`organizations`/`memberships`/`public.org_id()`/`public.role_rank()`), meta-modelo, `entities` con búsqueda (FTS/trigram/pgvector, `embedding` ya en `vector(1024)` para Voyage), grafo (`relationships`), satélites, historial append-only, secretos/auditoría, **todas** las políticas RLS de 04/05, y seed de ~35 tipos de sistema con campos representativos + 11 tipos de relación.
  - `supabase/README.md`: cómo aplicar y advertencia explícita de que el gate de aislamiento (T-015) es no negociable antes de producción.
- **T-013** · Scaffolding del proyecto Flutter (paso 1 de la secuencia) — *completada 2026-07-01*
  - `app/`: proyecto Flutter (Clean Architecture + MVVM + Riverpod + go_router) con Supabase, generado a mano (core/config, providers, router con guard de sesión, tema, errores) y carpetas de plataforma (android/ios/web/windows) fusionadas desde `flutter create`.
  - Instalado Flutter SDK 3.44.4 en `D:\flutter` (C: sin espacio suficiente), activado Modo de desarrollador de Windows (symlinks de plugins) con confirmación del usuario.
  - **Verificado de verdad, no solo escrito**: `flutter analyze` sin errores (3 issues reales encontrados y corregidos: super parameter en `PermissionFailure`, `anonKey`→`publishableKey` deprecado, test por defecto roto), `flutter test` pasa, y `flutter build web` compila exitosamente — confirma que el scaffold corre en un target real (Web), cumpliendo el criterio de aceptación de T-013.
  - **Fin de la fase de diseño puro; primeras dos tareas de implementación cerradas.**
- **T-012** · Definición del alcance del MVP (entregable 14) — *completada 2026-07-01*
  - `docs/14-alcance-mvp.md`: cierre de la fase de diseño. Consolida ~15 decisiones MVP/v2 dispersas en 03–13 en una definición única in/out.
  - MVP incluye: esquema+RLS+RBAC completos, seguridad de credenciales con MFA, pipeline de búsqueda completo, los 7 casos de uso y 5 pantallas, asistente IA/RAG completo (sin recortar), caché offline de lectura. Diferido a v2: herencia de tipos, grants por instancia, SSO, hash-chain, KMS externo, conversación multivuelta de la IA, escritura offline.
  - 8 criterios de aceptación concretos (definition of done) y secuencia de construcción de 8 pasos para minimizar retrabajo en la implementación.
  - **Fin de la Fase de diseño (roadmap 01–14). Arranca la implementación Flutter.**
- **T-011** · Estrategia de sincronización y offline (entregable 13) — *completada 2026-07-01*
  - `docs/13-offline-sync.md`: caché de solo lectura elimina de raíz la resolución de conflictos (respeta D-02). Offline set = favoritos + recientes + críticos + vecindario a 1 salto + procedimientos; secretos NUNCA se cachean.
  - Almacenamiento SQLite/Drift + FTS5 (búsqueda léxica local) cifrado con SQLCipher, clave en enclave seguro (Keychain/Keystore). Sync pull incremental (`v1_sync_pull(since)` con tombstones) + Realtime online.
  - Punto delicado resuelto con honestidad: permisos revocados mientras offline → max-offline-age (D-37) + revalidación/purga al reconectar; ventana inherente acotada y documentada, no ocultada. Decisiones D-33 a D-37.
  - Abiertas: valor de max-offline-age, flag no-cacheable por campo (v2), tope de tamaño de caché.
- **T-010** · Estrategia de IA / RAG anclado (entregable 12) — *completada 2026-07-01*
  - `docs/12-ia-rag.md`: postura honesta sobre "nunca inventa" — no se confía en el modelo, se le encajona. Graph-augmented RAG: recuperación híbrida (búsqueda 11 + recorrido de grafo + agregados SQL) bajo el JWT del usuario (RLS también para la IA; secretos jamás en el contexto).
  - Anti-alucinación con controles verificables: recuperar antes de decidir responder, anclaje estricto, verificación de citas server-side (descartar IDs no recuperados), números desde SQL (no estimados por el LLM), fallback honesto "no encontré". Decisiones D-27 a D-32.
  - Aprendizaje automático: 4 disparadores por agregados SQL deterministas; el LLM solo redacta el borrador cuando el humano acepta. Modelos: Haiku (intención) + Sonnet (síntesis) + Voyage (embeddings → fija vector(1024), actualiza el placeholder vector(1536) de 05).
  - Abiertas: modelo Voyage exacto/dimensión, umbrales de aprendizaje, proveedor enterprise.
- **T-009** · Estrategia de búsqueda (entregable 11) — *completada 2026-07-01*
  - `docs/11-busqueda.md`: pipeline en cascada (normalización → FTS → trigram → semántico), no fusión ponderada simultánea — el camino feliz (IP/serial/nombre) se resuelve en una sola query SQL sin coste externo.
  - Normalización de patrones técnicos (IP/MAC/serial/email) con match exacto que domina el ranking sobre cualquier score textual; embeddings solo sobre nombre/descripción/incidentes/procedimientos, reindexado asíncrono para no bloquear la escritura.
  - Medición con `search_events` (búsquedas sin clic, feedback implícito) para calibrar pesos/umbrales manualmente en el MVP. Decisiones D-22 a D-26.
  - Abiertas: valores exactos de umbrales/pesos (calibración con datos reales), vectorizar comentarios, automatizar reajuste de ranking (v2).
- **T-008** · Estrategia de Seguridad (entregable 10) — *completada 2026-07-01*
  - `docs/10-seguridad.md`: envelope encryption por org (DEK por tenant, KEK raíz en Vault/KMS — clave fuera de la BD, migrable sin cambiar contrato); rate limiting por usuario/org (BD→Upstash→WAF); MFA/AAL2 obligatoria para revelar secretos y acciones admin.
  - Aislamiento multi-tenant como fallo catastrófico #1: RLS + RPC invoker + Edge con revalidación, verificado por tests de aislamiento en CI como gate de despliegue (D-21).
  - Modelo de amenazas accionable (fuga cross-tenant, IDOR, mass assignment JSONB, JWT replay, DoS por embeddings, manipulación de auditoría) mapeado a OWASP; crypto-shredding para conciliar GDPR con historial inmutable (D-20). Decisiones D-17 a D-21.
  - Abiertas: hash-chain de auditoría (v2), proveedor KMS enterprise, retención por jurisdicción.
- **T-007** · Diseño de la API (entregable 09) — *completada 2026-07-01*
  - `docs/09-api.md`: contrato en tres capas — PostgREST auto (CRUD+RLS), RPC Postgres `security invoker` (búsqueda léxica, vecindario, crear/cerrar incidente, match semántico), Edge Functions (`reveal-secret`, `search-semantic`, `ai-assistant` reservado).
  - Regla de oro: el cliente nunca usa `service_role`; cada Edge Function valida JWT→membership→rol→audita. `select` directo de secretos devuelve solo ciphertext inútil sin la clave (que vive solo en la Edge Function).
  - Convenciones: keyset pagination, modelo de error uniforme (404 en vez de 403 cross-tenant), idempotencia por `client_request_id`, versionado `v1_*`. Reglas para `security definer` si alguna vez se necesita.
  - Abiertas y trasladadas a entregable 10: gestión de clave de descifrado, rate limiting; a 12: proveedor/dimensión de embeddings.
- **T-006** · Wireframes / UX de pantallas clave (entregable 08) — *completada 2026-07-01*
  - `docs/08-wireframes-ux.md`: wireframes en bloques para Dashboard, Buscador (command palette en desktop), Ficha de entidad con vecindario/breadcrumb de relación, formulario de Incidente (con sugerencia de similares en vivo), revelado de credencial.
  - Tabla de estados obligatorios por pantalla (vacío/cargando/error/sin permiso); principios visuales transversales (densidad progresiva, skeletons en vez de spinners).
  - Abiertas: sistema de diseño formal (tokens), checklist de accesibilidad — diferidas a implementación.
- **T-005** · Navegación y arquitectura de información (entregable 07) — *completada 2026-07-01*
  - `docs/07-navegacion.md`: navegación por grafo en vez de módulos; el buscador como shell persistente (no una pantalla más).
  - Shell de 4 destinos fijos (bottom nav móvil / rail desktop); patrón de drill-down con breadcrumb de relación recorrida y deduplicación de ciclos; preview in-place vs. push completo.
  - Tabla de conteo real de toques por caso de uso (T-004 → pantalla); administración (UC-05/07) deliberadamente separada del flujo operativo.
  - Abiertas: atajo de teclado global en desktop, persistencia del stack de navegación al cerrar app.
- **T-004** · Casos de uso principales (entregable 06) — *completada 2026-07-01*
  - `docs/06-casos-de-uso.md`: 7 casos de uso end-to-end (buscar UC-01, vecindario UC-02, incidente UC-03, credencial UC-04, nuevo tipo UC-05, adjunto UC-06, invitar usuario UC-07), cada uno con actor/precondición/flujo/alternativas/postcondición y trazado a tablas y policies reales del entregable 05.
  - Matriz de trazabilidad caso de uso ↔ reglas de la Constitución.
  - Abiertas: umbral de relajación de búsqueda (→ 11), flujo de solicitud de grant (→ v2), disparador de sugerencia de procedimiento (→ 12·IA).
- **T-003** · Base de datos — esquema físico (entregable 05) — *completada 2026-07-01*
  - `docs/05-base-de-datos.md`: DDL completo — `organizations`/`memberships`, meta-modelo (`entity_types`/`field_definitions`), `entities` con `search_vector`/`embedding`, `relationships`, satélites (tags, attachments, comments, favorites, recent_views), `entity_history` append-only, `secrets`/`secret_access_log`, `audit_log`.
  - Índices: GIN (FTS), `pg_trgm` (tolerancia a errores), `ivfflat` (pgvector semántico), GIN sobre `data` JSONB.
  - Políticas RLS completas tabla por tabla materializando los roles y la matriz de permisos del entregable 04; funciones `public.org_id()`/`public.role_rank()`.
  - Abiertas: dimensión de embedding (pendiente de 12·IA), gestión de clave de cifrado (pendiente de 10·Seguridad), desnormalizar `org_id` en tablas N:N.
- **T-002** · Multi-tenancy y modelo de permisos (entregable 04) — *completada 2026-07-01*
  - `docs/04-multitenancy-permisos.md`: aislamiento shared-schema + RLS por `org_id`; `memberships` como verdad de autorización + claim `active_org_id`.
  - 4 roles (Admin/Supervisor/Técnico/Consulta) + matriz de acciones; permisos por campo (secretos en tabla aparte, `sensitive` enmascarado en API); grants por instancia esbozados para v2.
  - Defensa en profundidad (RLS dura + API grano fino), MFA para Admin/Supervisor, auditoría append-only. Decisiones D-07 a D-11.
- **T-001** · Sistema de gestión de tareas — *completada 2026-07-01*
  - Creada estructura de 3 capas: roadmap (estratégico) · `TASKS.md` (táctico) · `CHANGELOG.md` (histórico).
  - Flujo automático: una sola tarea En proceso, promoción automática de la siguiente pendiente, archivado con fecha.
