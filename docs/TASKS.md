# IT Brain — Tablero de Tareas

> **Tablero operativo único.** Siempre existe **exactamente una** tarea En proceso.
> Estratégico → [roadmap](README.md) · Histórico → [changelog](CHANGELOG.md)

---

## Reglas de operación (automáticas)

1. Toda tarea nueva entra en **Pendientes** (al final de la cola, salvo prioridad explícita).
2. Al empezar a trabajar una tarea, sube a **En proceso**. **Máximo una a la vez.**
3. Al terminar, se **archiva** en [CHANGELOG.md](CHANGELOG.md) con su fecha y se retira del tablero.
4. Tras completar, se **promueve automáticamente** la primera de Pendientes a En proceso.
5. IDs correlativos `T-NNN`, nunca se reutilizan (trazabilidad — Constitución, regla 13).
6. El orden de **Pendientes = prioridad**. El usuario puede reordenar cuando quiera (no es intervención manual, es re-priorización).
7. El **Backlog** guarda ideas futuras aún sin priorizar; no entran en la cola hasta moverse a Pendientes.

---

## 🔵 En proceso

### T-016 · Meta-modelo funcionando — crear tipo/campo (UC-05)
- **Deriva de:** paso 4 de la secuencia de construcción, [14-alcance-mvp.md §5](14-alcance-mvp.md) · docs/06-casos-de-uso.md UC-05
- **Objetivo:** implementar en Flutter el flujo que demuestra que el modelo dirigido por datos funciona de verdad: crear un tipo de entidad con campos personalizados desde la app, y que el formulario de creación/edición de entidades de ese tipo se **renderice dinámicamente** desde `field_definitions`. Es el paso que valida el supuesto central antes de construir el resto de pantallas encima.
- **Hecho cuando:** desde la app (rol admin) se puede crear un `entity_type` + `field_definitions` y luego crear una entidad de ese tipo con un formulario generado dinámicamente, contra el Supabase real.
- **Modelo sugerido:** Sonnet · Alto (implementación de feature: capas data/domain/presentation + UI dinámica).
- **Nota:** promovida desde el Backlog al completar T-015. **Requiere un proyecto Supabase real conectado** para el criterio "Hecho cuando" (ver bloqueante abajo).

- **Progreso (2026-07-01) — código implementado y verificado localmente, NO validado end-to-end:**
  - **Dominio** (`app/lib/features/meta_model/domain/`): `Archetype`, `FieldDataType` (con bandera `supportedInForm`), `EntityType`, `FieldDefinition`, interfaz `MetaModelRepository`.
  - **Datos**: `MetaModelRemoteDataSource` (PostgREST bajo RLS, nunca `service_role`) + `MetaModelRepositoryImpl` (traduce 42501→`PermissionFailure`, 23505→`ValidationFailure`, etc.).
  - **Presentación**: `EntityTypesScreen` (lista sistema+org, FAB "Nuevo tipo" gated por rol), `CreateEntityTypeScreen` (crea tipo + N campos), `CreateEntityScreen` + `DynamicFieldInput` (**el formulario dinámico** desde `field_definitions` → `data` JSONB tipado). Rutas en `app_router.dart`; entrada desde el dashboard.
  - **Alcance MVP**: form soporta text/number/bool/date/datetime/enum/ip/mac/url/email; `reference`/`secret`/`json`/`geo` diferidos con etiqueta explícita (`secret` **jamás** como input plano — va cifrado a `secrets`).
  - **Verificado (mismo listón que T-013):** `flutter analyze` limpio · `flutter test` 3/3 (incl. test que valida el supuesto central: el form se genera desde las defs y produce `data` tipada) · `flutter build web` OK.
  - **Dependencia descubierta y RESUELTA (T-017):** insertar `entity_types`/`entities` exige `org_id = public.org_id()` (RLS, sin default) → UC-05 dependía de resolver la org activa (docs 04 §2.2). Resuelto con el access token hook + policy de bootstrap de T-017; `activeOrgProvider` ya lee el claim del JWT.
  - **Falta para "Hecho":** SOLO ejecutar el flujo contra un Supabase real (crear tipo→crear entidad) una vez conectado el backend.

---

## ⚠️ Bloqueante antes de cerrar T-016

Para *validar* la feature contra datos reales hacen falta dos cosas que dependen del usuario:
1. **Crear un proyecto Supabase** (supabase.com) y aplicar las migraciones (`supabase/migrations/`).
2. **Inicializar git + repositorio remoto** para que el CI (y su gate de aislamiento T-015) corra por primera vez.

El código de la feature ya está escrito y verificado localmente; falta solo la validación end-to-end.

---

## ⚪ Pendientes

_(vacío — siguiente en cola tras cerrar T-016: buscador + ficha de entidad (UC-01/02), ver Backlog)_

---

## 📌 Backlog (sin priorizar)

### Núcleo ya diseñado (docs 01–14)
- Buscador + Ficha de entidad/vecindario (UC-01/02) — paso 5
- Incidentes (UC-03) + Credenciales (UC-04) — paso 6
- Caché offline de lectura (13) — paso 7
- Asistente IA (12) — paso 8, al final
- Roadmap de versiones, backlog de producto, despliegue y crecimiento (entregables 15–18)

### Visión ampliada del usuario (2026-07-01) — alcance NUEVO sobre el diseño 01–14
Coincide ~80% con el diseño existente; lo siguiente es lo genuinamente nuevo a diseñar:
- **Explorar por categorías en el home** (grid de tipos → listado de entidades del tipo). Revisa la decisión de docs 07 (grafo/buscador vs módulos); recomendación: **ambos** conviven. Requiere UI nueva sobre el meta-modelo ya construido.
- **Editor visual de diagramas (tipo Miro)** — lienzo con bloques, conexiones, flechas, notas; adjuntos por bloque. Módulo nuevo, no cubierto en 01–14. Requiere entregable de diseño propio.
- **Guías de diagnóstico / árboles de decisión** — flujos interactivos ("¿encendida? sí/no → …") para troubleshooting guiado. Módulo nuevo; se relaciona con `knowledge`/procedimientos y con la IA (12).
- **Flujo de aprobación de cambios** (RBAC) — hoy los roles hacen CRUD por rango; añadir estado "propuesto → aprobado" con rol aprobador. Extiende docs 04.
- **Tipos/menores**: añadir DVR/NVR al seed; **Mantenimientos** como concepto de primer nivel (registro + "último mantenimiento" + programación). Rol "Coordinador" ≈ `supervisor` actual (alinear nomenclatura).
- Nota: fotos/adjuntos/PDF/video en procedimientos y fichas ya están cubiertos por `attachments`; la auditoría con antes/después/motivo ya está en `entity_history`.
