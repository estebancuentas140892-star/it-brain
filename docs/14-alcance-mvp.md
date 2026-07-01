# 14 · Definición del alcance del MVP

> Cierre de la fase de diseño. Consolida las **~15 decisiones MVP/v2** que quedaron dispersas en
> los entregables 03–13 en una sola definición de qué se construye primero. A partir de aquí
> empieza la implementación (Flutter/Clean/MVVM/Riverpod sobre Supabase).

---

## 1. Criterio de corte

El MVP debe demostrar el **principio más importante** end-to-end: un técnico escribe cualquier
palabra y encuentra todo lo necesario para resolver una incidencia en menos de un minuto —
incluida la ayuda del asistente IA citando fuentes reales. Todo lo que no sirve directamente a ese
recorrido (UC-01 → UC-04) se difiere, sin importar cuán atractivo sea.

---

## 2. Qué SÍ entra en el MVP

### 2.1 Modelo de datos y multi-tenancy
- Esquema completo de `entities`/`relationships`/meta-modelo (03, 05) — **sin** herencia de tipos
  (`parent_type_id` presente en el esquema pero sin UI/lógica de herencia).
- Multi-tenant con RLS; **single-tenant en operación** (una sola empresa real usándolo) (D-01).
- 4 roles RBAC completos (Admin/Supervisor/Técnico/Consulta) con la matriz de acciones (04).
- Campos personalizados vía `field_definitions` — el meta-modelo funcionando de verdad (UC-05).
- Columna `valid_from/valid_to` en `relationships` presente en el esquema; **sin** UI para
  relaciones temporales todavía (03 §9).

### 2.2 Seguridad
- Credenciales cifradas con envelope encryption + `reveal-secret` auditado (10 §2).
- MFA obligatoria para Admin/Supervisor (04, 10 §4).
- Rate limiting básico (tabla `rate_limits`, no Redis todavía) (10 §3).
- Tests de aislamiento de tenant en CI como gate de despliegue (10 §5, D-21) — **no negociable**,
  entra desde el primer sprint de implementación, no al final.

### 2.3 Búsqueda
- Pipeline completo en cascada: normalización + FTS + trigram + semántico (11).
- Umbrales con valores iniciales razonables, calibrados manualmente con uso real (no bloquea el
  lanzamiento; se ajustan en vivo).

### 2.4 Casos de uso y UX
- Los 7 casos de uso de 06 completos: buscar, vecindario, incidente, credencial, nuevo tipo,
  adjunto, invitar usuario.
- Navegación descrita en 07 (shell de 4 destinos, drill-down por grafo) y las 5 pantallas de 08
  (Dashboard, Buscador, Ficha, Incidente, Credencial).

### 2.5 IA
- Asistente RAG anclado completo: recuperación híbrida + síntesis + verificación de citas +
  fallback honesto (12). **No** se recorta — es la funcionalidad diferenciadora del producto.
- Los 4 disparadores de aprendizaje automático vía SQL (12 §10).
- **Sin** conversación multivuelta (cada consulta es independiente) ni acciones agénticas (12 §12).

### 2.6 Offline
- Caché de solo lectura completa: favoritos + recientes + críticos + vecindario + procedimientos,
  cifrada con SQLCipher (13). **Sin** flag "no-cacheable" por campo (v2).

### 2.7 Plataformas
- Flutter en **Android, iOS y Web** desde el día 1 (una sola base de código). **Windows/Tablet
  como builds adicionales del mismo código**, validados después del lanzamiento inicial —no
  bloquean el MVP, pero no requieren desarrollo aparte.

---

## 3. Qué NO entra (diferido explícitamente a v2+)

| Elemento | Entregable de origen | Por qué se difiere |
|---|---|---|
| Herencia de tipos (`parent_type_id` con UI) | 03 §9 | Añade validación compleja sin la cual el meta-modelo ya funciona |
| Grants por instancia (`entity_grants`) | 04 §6 | El rol basta para el 90% de casos; grano fino es refinamiento |
| Roles personalizados / SSO-SAML | 04 §10 | Requerido por enterprise, no por el primer cliente |
| Multi-org real por usuario (UI) | 04 §10 | El esquema ya lo soporta; la UI espera demanda MSP |
| Hash-chain de auditoría | 10 §10 | Append-only ya da la garantía base; esto es defensa avanzada |
| KMS externo (AWS/GCP) | 10 §10 | Vault de Supabase basta hasta que un cliente enterprise lo exija |
| Automatizar reajuste de ranking de búsqueda | 11 §10 | Requiere volumen de datos que no existe el día 1 |
| Vectorizar comentarios | 11 §5 | Sin evidencia de que aporte, se evalúa si hay demanda |
| Conversación multivuelta / acciones agénticas de la IA | 12 §12 | Aumenta drásticamente la superficie de riesgo de "inventar" |
| Modelo IA autoalojado (enterprise) | 12 §9 | Decisión comercial, no técnica del MVP |
| Escritura offline + resolución de conflictos | 13 §1 (D-02) | El problema más difícil del proyecto; se evita de raíz |
| Flag "no-cacheable" por campo | 13 §12 | Refinamiento de seguridad offline, no bloquea el caso base |

---

## 4. Criterios de aceptación del MVP ("definition of done")

El MVP está **listo** cuando, con datos reales de una organización piloto:

1. Un Técnico busca un término libre (nombre, IP, código, síntoma) y obtiene el resultado correcto
   en <10 segundos percibidos (objetivo servidor <300 ms, 09 §8 / 11 §8).
2. Desde ese resultado, navega el vecindario (relaciones) sin perder el hilo (breadcrumb de grafo,
   07 §3), en máximo 2 toques adicionales.
3. Puede registrar un incidente, ver incidentes similares sugeridos en vivo, y cerrarlo con
   solución — y si se repite, el sistema sugiere crear un procedimiento (06 UC-03, 12 §10).
4. Puede consultar metadatos de una credencial sin fricción y revelar el secreto con auditoría
   visible antes de confirmar (06 UC-04, 08 §5).
5. Un Administrador puede crear un tipo de entidad nuevo con campos propios **sin ayuda de
   desarrollo** y usarlo de inmediato (06 UC-05).
6. El asistente IA responde una consulta tipo "POS 14 no imprime" citando fuentes reales
   verificables, y dice honestamente "no encontré información" cuando no la hay (12 §8, §7).
7. Con el dispositivo en modo avión, el técnico consulta sus favoritos/recientes con toda su
   información de vecindario (13 §3).
8. Los tests de aislamiento de tenant pasan en CI antes de cada despliegue (10 §5) — sin excepción.

---

## 5. Secuencia de construcción recomendada

No es un roadmap de fechas (eso es el entregable 15), es el **orden lógico de dependencias
técnicas** para minimizar retrabajo:

```
1. Scaffolding Flutter (Clean/MVVM + Riverpod) + proyecto Supabase
2. Migraciones: esquema completo (05) + RLS (04/05) + seed de arquetipos/tipos de sistema (03)
3. Tests de aislamiento de tenant en CI (10 §5) — ANTES de construir features sobre el esquema
4. Meta-modelo funcionando: crear tipo/campo (UC-05) → prueba de que el modelo dirigido por datos
   funciona de verdad, antes de construir el resto de pantallas sobre un supuesto no verificado
5. Buscador (11) + Ficha de entidad/vecindario (UC-01/02) — el núcleo de la experiencia
6. Incidentes (UC-03) + Credenciales (UC-04)
7. Caché offline de lectura (13)
8. Asistente IA (12) — al final porque depende de que 5 y 6 ya tengan datos reales que recuperar
```

---

## 6. Cumplimiento de la Constitución

| Regla | Cómo se cumple |
|---|---|
| Principio más importante | Es literalmente el criterio de corte (§1) y el primer criterio de aceptación (§4.1-4.2) |
| 11 · Arquitectura a 10 años | Todo lo diferido a v2 tiene su lugar ya reservado en el esquema (columnas, tablas) — no se rediseña, se activa |
| 12 · No romper la simplicidad | La lista de "qué NO entra" (§3) es tan importante como la de qué sí |

---

## 7. Cuestiones abiertas

Ninguna nueva: las cuestiones abiertas de 03–13 permanecen como están, a resolver durante la
implementación de cada pieza correspondiente (no bloquean el arranque del desarrollo).

---

### Próxima tarea
**Fin de la fase de diseño.** Comienza la implementación: scaffolding del proyecto Flutter
(Clean Architecture + MVVM + Riverpod) conectado a Supabase, siguiendo la secuencia de §5.
