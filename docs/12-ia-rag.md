# 12 · Estrategia de IA / RAG anclado

> El asistente que responde "POS 14 no imprime" recorriendo el grafo y citando fuentes reales,
> nunca inventando (Constitución, regla 19). Se apoya en la búsqueda (11), el grafo (03) y la API
> (09 §6.3, `ai-assistant` reservada). Cierra el disparador de aprendizaje automático abierto en 06.

---

## 1. Postura honesta sobre "la IA nunca inventa"

Un LLM, por diseño, **puede** producir texto plausible sin base. Prometer "nunca inventa" como si
fuera magia sería mentir. Lo que sí podemos garantizar por arquitectura:

1. El modelo **solo recibe** conocimiento recuperado de la propia empresa (RAG anclado).
2. **Toda afirmación va citada** a una entidad/incidente/procedimiento real y verificable.
3. Las citas se **verifican en el servidor**: si el modelo cita un ID que no estaba en el contexto
   recuperado, se descarta antes de mostrarlo (§6).
4. Si no hay evidencia suficiente, el asistente **dice "no encontré información"** en vez de rellenar
   el hueco (§7).

> Es decir: no confiamos en que el modelo "se porte bien" — lo **encajonamos** para que inventar sea
> estructuralmente difícil y, cuando lo intente, sea detectable y se bloquee.

---

## 2. Decisiones de este entregable

| # | Decisión | Elección | Motivo |
|---|----------|----------|--------|
| D-27 | **Tipo de RAG** | **Graph-augmented RAG**: recuperación híbrida (búsqueda 11 + recorrido de relaciones + agregados SQL) | El valor de IT Brain está en las *relaciones*, no solo en documentos sueltos |
| D-28 | **Anclaje** | Respuesta **solo** desde contexto recuperado; citas obligatorias; verificación de citas server-side | Hace la regla 19 verificable, no un acto de fe |
| D-29 | **Fallback** | "No encontré información sobre X" explícito cuando la recuperación es vacía/débil | Un "no sé" honesto vale más que una respuesta inventada |
| D-30 | **Modelos** | Síntesis con **Claude Sonnet** (calidad/coste); clasificación de intención con **Claude Haiku**; embeddings con **Voyage** | Reparto por coste; embeddings de proveedor recomendado por Anthropic |
| D-31 | **Seguridad** | La IA recupera **bajo el JWT/rol del usuario**; secretos **nunca** entran al contexto del modelo | RLS también limita a la IA; un secreto jamás se envía a un LLM |
| D-32 | **Aprendizaje automático** | Disparadores por **agregados SQL** (baratos, deterministas); el LLM solo *redacta* el borrador cuando se acepta | No se gasta un LLM para "contar"; se usa para lo que es bueno (redactar) |

---

## 3. Arquitectura del asistente (Edge Function `ai-assistant`)

```
Usuario: "POS 14 no imprime"
        │
        ▼
┌──────────────────────────┐
│ 1. Clasificar intención   │  Haiku: ¿es búsqueda de entidad? ¿síntoma/diagnóstico?
│    + normalizar consulta   │  ¿pregunta sobre un procedimiento? (barato, rápido)
└────────────┬─────────────┘
             ▼
┌──────────────────────────┐
│ 2. RECUPERAR (bajo RLS)   │  a) búsqueda cascada (11) → entidad(es) ancla
│                           │  b) recorrer grafo 1-2 saltos (09 §5.2) → vecindario
│                           │  c) incidentes similares (embedding de la consulta)
│                           │  d) agregados SQL: tiempo medio de resolución,
│                           │     top-resolver, nº de repeticiones
└────────────┬─────────────┘
             ▼
┌──────────────────────────┐
│ 3. ¿Hay evidencia         │  no → devolver fallback honesto (§7), NO llamar al LLM
│    suficiente?             │  sí ↓
└────────────┬─────────────┘
             ▼
┌──────────────────────────┐
│ 4. SINTETIZAR             │  Sonnet, con prompt de anclaje (§5): solo el contexto
│    (con citas)             │  recuperado; cada dato citado a su ID
└────────────┬─────────────┘
             ▼
┌──────────────────────────┐
│ 5. VERIFICAR citas         │  descartar cualquier cita a un ID no recuperado (§6)
└────────────┬─────────────┘
             ▼
   Respuesta + tarjetas de fuentes clicables (llevan a la ficha real)
```

**Punto crítico (D-31):** los pasos 2a–2d se ejecutan **con el JWT del usuario** (RPC `security
invoker`, 09 §5), por lo que RLS filtra automáticamente por org y rol. El LLM nunca ve datos de otra
empresa ni secretos — los secretos viven en `secrets` (fuera de `entities`) y **jamás** se incluyen
en el contexto enviado al modelo.

---

## 4. Recuperación híbrida (el diferenciador)

Un RAG típico solo hace búsqueda vectorial sobre documentos. IT Brain recupera **tres tipos de
señal** y las fusiona:

| Señal | Fuente | Aporta |
|---|---|---|
| **Entidad(es) ancla** | Búsqueda cascada (11) | El "sujeto" de la consulta (POS-14, la impresora…) |
| **Vecindario** | Recorrido de `relationships` 1–2 saltos (09 §5.2) | El *contexto estructural*: qué usa, de qué depende, a qué está conectado |
| **Casos y conocimiento similar** | Embedding de la consulta → `v1_match_entities` sobre incidentes/procedimientos | Soluciones previas, procedimientos aplicables |
| **Agregados** | Consultas SQL sobre incidentes históricos | Tiempo medio de resolución, quién lo resolvió más veces, nº de repeticiones |

La fusión de vecindario + casos similares es lo que permite responder no solo *"qué es POS-14"* sino
*"qué suele fallar en POS-14 y cómo se ha resuelto"* — el objetivo real de la Constitución (resolver
en <1 minuto).

---

## 5. Síntesis con anclaje (prompt)

El *system prompt* de la fase 4 impone reglas duras (resumen conceptual, no literal):

- "Responde **exclusivamente** con la información del CONTEXTO que sigue. No uses conocimiento
  externo ni general."
- "**Cada afirmación** debe ir acompañada de la referencia a su fuente (`[entidad:ID]`,
  `[incidente:ID]`, `[procedimiento:ID]`)."
- "Si el contexto **no contiene** la respuesta, di exactamente que no encontraste información sobre
  ello. **No supongas, no completes, no generalices.**"
- El contexto recuperado se inyecta como **datos estructurados** (JSON de entidades/relaciones/
  incidentes con sus IDs), no como prosa — reduce el margen de que el modelo "reinterprete".
- La salida preferida es **semiestructurada** (secciones: Equipo y relaciones · Incidentes previos ·
  Procedimientos · Datos) más que un párrafo libre — menos superficie para inventar, más fácil de
  escanear (coherente con la UX de 08).

---

## 6. Anti-alucinación: mecanismos concretos

No un principio, sino controles verificables:

1. **Recuperación primero, decisión de responder después** (paso 3): si no hay evidencia, el LLM
   **ni se llama**. No puede alucinar sobre algo que nunca se le preguntó.
2. **Anclaje estricto** (§5): contexto como única fuente permitida.
3. **Verificación de citas server-side** (paso 5): se extraen todos los IDs citados en la respuesta
   y se contrastan contra el conjunto **realmente recuperado**. Cualquier cita a un ID inexistente o
   no recuperado se **elimina**, y si eso deja una afirmación sin respaldo, se marca o se poda. Es la
   red de seguridad contra la cita fabricada (el modo más insidioso de alucinación).
4. **Sin invención de números**: tiempos, contadores y "top-resolver" vienen de **agregados SQL**
   (§4), no de que el modelo los estime. Se le pasan ya calculados; su trabajo es redactarlos, no
   producirlos.
5. **Trazabilidad de la respuesta**: cada tarjeta de fuente es clicable y lleva a la ficha real
   (09/08) — el usuario puede verificar en un toque, cerrando el bucle de confianza.

---

## 7. El fallback honesto (D-29)

Cuando la recuperación es vacía o de baja confianza:

> *"No encontré información registrada sobre **'POS 14'** en el sistema. ¿Quieres crear una entidad
> nueva o registrar un incidente?"*

- Nunca una respuesta inventada, nunca un "probablemente sea…". El "no sé" es una **feature de
  confianza**, no un fallo.
- El fallback es **constructivo**: ofrece la acción de capturar ese conocimiento que falta —
  convirtiendo el vacío en una oportunidad de crecer el cerebro colectivo (regla 17).

---

## 8. Ejemplo end-to-end — *"POS 14 no imprime"*

1. **Intención** (Haiku): consulta mixta — entidad `POS 14` + síntoma `no imprime`.
2. **Recuperación** (bajo RLS): ancla `POS-14`; vecindario → `Impresora Epson`, `Switch Piso 2`,
   `Puerto 24`, `Servidor SQL`; incidentes similares → 3 previos de impresión; agregados → tiempo
   medio 4 min, top-resolver "Juan", repeticiones 3.
3. **Síntesis** (Sonnet), citada:
   > *POS-14 [entidad:…] usa la impresora Epson TM-T20 [entidad:…], conectada al Puerto 24 del
   > Switch Piso 2 [entidad:…]. Se registraron 3 incidentes de impresión previos [incidente:…],
   > resueltos en promedio en 4 min con el procedimiento "Reiniciar cola de impresión"
   > [procedimiento:…]. Quien más los ha resuelto: Juan.*
4. **Verificación**: todos los IDs citados estaban en el contexto recuperado → se muestran.
5. **Resultado**: respuesta + tarjetas clicables a cada ficha. El técnico resuelve sin haber
   navegado manualmente por seis pantallas.

---

## 9. Seguridad y privacidad de la IA (refuerza 10)

- **RLS también para la IA** (D-31): recuperación con el JWT del usuario; imposible que el contexto
  incluya datos de otra org o de un rol superior.
- **Secretos excluidos**: nunca entran al prompt. Si el usuario pregunta "¿cuál es la contraseña de
  SAP?", el asistente responde con los **metadatos** de la credencial y **remite al flujo de
  revelado auditado** (UC-04) — no la recita.
- **Proveedor del LLM**: se exige acuerdo de no-entrenamiento sobre los datos enviados. Para
  enterprise con datos muy sensibles, se contempla despliegue con un proveedor que garantice
  aislamiento o modelo autoalojado (v2). El contexto enviado se **minimiza** a lo estrictamente
  necesario para responder.
- **Auditoría**: las consultas al asistente se registran (qué se preguntó, qué fuentes se usaron) —
  útil para mejorar y para trazabilidad, sin guardar datos sensibles innecesarios.

---

## 10. Aprendizaje automático del conocimiento (D-32) — cierra 06 UC-03

Los cuatro disparadores del prompt original, cada uno con su mecanismo:

| Disparador | Cómo se detecta | Umbral (calibrable) | Acción |
|---|---|---|---|
| **Incidente repetido → sugerir procedimiento** | Agregado SQL: nº de incidentes con patrón/tipo similar sin procedimiento asociado | ≥ 3–5 repeticiones | Banner no bloqueante (08 §4); si se acepta, **Sonnet redacta el borrador** del procedimiento a partir de las soluciones registradas |
| **Procedimiento muy usado → recomendado** | Contador de uso (relaciones `resuelto_por`) | Percentil alto de uso | Badge "Recomendado" en la ficha |
| **Activo con demasiados incidentes → revisión** | Agregado SQL de incidentes por entidad en ventana temporal | Configurable por org | Alerta en dashboard (08 §1) |
| **Solución escrita a mano → conocimiento permanente** | Detectado al cerrar un incidente con solución libre no ligada a procedimiento | Inmediato (pregunta) | Prompt "¿Convertir en procedimiento permanente?" |

- **Clave de diseño**: la *detección* es **SQL determinista** (barata, sin alucinación posible); el
  LLM solo interviene para **redactar** el borrador cuando el humano ya decidió crearlo — y ese
  borrador se genera anclado a las soluciones reales ya registradas, con revisión humana antes de
  guardarse. La IA **propone**, la persona **dispone**.

---

## 11. Modelos y embeddings (cierra la dimensión abierta en 05/09)

| Uso | Modelo | Nota |
|---|---|---|
| Clasificación de intención / enrutamiento | **Claude Haiku** | Barato, rápido, se llama en cada consulta |
| Síntesis de respuesta / redacción de borradores | **Claude Sonnet** | Calidad de redacción sin el coste de Opus |
| Embeddings (búsqueda semántica, similares) | **Voyage** (p. ej. `voyage-3`) | Proveedor de embeddings recomendado por Anthropic |

> **Impacto en el esquema**: el `vector(1536)` de `entities.embedding` (05 §3) fue un *placeholder*.
> Al elegir Voyage, la dimensión real (p. ej. **1024** en `voyage-3`) fija el tipo definitivo →
> **actualizar a `vector(1024)`** en la migración correspondiente antes de generar embeddings. Esta
> es la cuestión abierta de 05/09 ahora resuelta; queda pendiente solo confirmar el modelo Voyage
> exacto y su dimensión en el momento de implementar.

---

## 12. Alcance: MVP vs. después

| Elemento | MVP | v2+ |
|---|---|---|
| RAG anclado con citas + verificación server-side | ✔ | |
| Fallback honesto "no encontré" | ✔ | |
| Respuesta con vecindario + similares + agregados | ✔ | |
| Aprendizaje automático (4 disparadores por SQL) | ✔ | |
| Redacción de borrador de procedimiento (LLM) | ✔ | |
| Conversación multivuelta / memoria de sesión | | ✔ |
| Acciones agénticas (crear/editar por instrucción) | | ✔ |
| Reajuste automático de umbrales de aprendizaje | | ✔ |
| Modelo autoalojado para enterprise | | ✔ |

---

## 13. Cumplimiento de la Constitución

| Regla | Cómo se cumple |
|---|---|
| 19 · La IA nunca inventa | Anclaje estricto + verificación de citas + fallback honesto + números desde SQL (§1, §6, §7) |
| 15/16/17 · Aprendizaje colectivo | Disparadores de aprendizaje automático (§10) convierten cada incidente en conocimiento reutilizable |
| 4 · No depender de personas | "Top-resolver" y soluciones previas quedan en el sistema, no en la cabeza de Juan |
| Principio más importante | El ejemplo §8 resuelve la llamada real recorriendo el grafo por el técnico |

---

## 14. Cuestiones abiertas

1. **Modelo Voyage exacto y su dimensión** (fija `vector(N)`): confirmar al implementar; el diseño
   ya asume la actualización del esquema.
2. **Umbrales de aprendizaje automático** (3 vs. 5 repeticiones, ventana temporal de "demasiados
   incidentes"): calibrar con datos reales, igual que los umbrales de búsqueda (11 §10).
3. **Proveedor/aislamiento para enterprise sensible**: decisión comercial con el primer cliente que
   lo exija; el diseño de minimización de contexto ya reduce la exposición.

---

### Próxima tarea
**T-011 · Estrategia de sincronización y offline** (entregable 13) — la caché de solo lectura de
favoritos/críticos (decisión D-02) y cómo se mantiene coherente con el servidor.
