# 11 · Estrategia de búsqueda

> El pipeline que hace real el principio más importante: escribir cualquier palabra y encontrar
> todo en <10 s (UC-01). Se apoya en las primitivas ya elegidas en 03/05 (FTS + `pg_trgm` +
> `pgvector`) y en el contrato ya definido en 09 (`v1_search_entities`, `search-semantic`).
> Aquí se cierra **cómo se combinan, en qué orden, y con qué umbrales**.

---

## 1. Decisiones de este entregable

| # | Decisión | Elección | Motivo |
|---|----------|----------|--------|
| D-22 | **Estrategia de fusión** | **Cascada con fallback**, no fusión ponderada simultánea | Más barata (evita llamar al modelo de embeddings en cada tecleo) y más predecible de depurar |
| D-23 | **Normalización de consulta** | Detectar y normalizar **patrones técnicos** (IP, MAC, serial) antes de tokenizar | `192.168.1.30` y `192.168.001.030` deben encontrar lo mismo; el tokenizador `simple` de Postgres no lo hace solo |
| D-24 | **Cuándo se dispara lo semántico** | Solo si la cascada léxica no supera el umbral de confianza, o el usuario pide explícitamente "buscar por significado" | El embedding tiene coste (latencia + dinero); no se gasta si el léxico ya resuelve (caso mayoritario: IDs, nombres, códigos) |
| D-25 | **Medición de relevancia** | Panel de **búsquedas sin clic** + *feedback* implícito (qué resultado se abrió) | Sin esto, "mejorar el ranking" es opinión, no dato |
| D-26 | **Reindexado** | Incremental por trigger (ya en 05); recomputo de `embedding` **asíncrono**, no en el request de escritura | Generar un embedding es una llamada de red; no debe bloquear guardar una entidad |

---

## 2. El pipeline en cascada

```
consulta del usuario ("192.168.1.30", "POS 14", "no imprime", "epson")
        │
        ▼
┌─────────────────────────┐
│ 1. Normalización        │  detecta IP/MAC/serial/email → formato canónico (D-23)
└───────────┬─────────────┘
            ▼
┌─────────────────────────┐
│ 2. FTS (search_vector)   │  websearch_to_tsquery — rápido, exacto por palabra/prefijo
└───────────┬─────────────┘
            │ rank máximo ≥ umbral_alto (ej. 0.3)?
      sí ───┤─── no
      │     ▼
      │  ┌─────────────────────────┐
      │  │ 3. Trigram (pg_trgm)     │  tolera typos: "epson" ~ "epsom", "impresra"
      │  └───────────┬─────────────┘
      │              │ similarity máxima ≥ umbral_medio (ej. 0.35)?
      │        sí ───┤─── no
      │        │     ▼
      │        │  ┌─────────────────────────┐
      │        │  │ 4. Semántico (embedding)│  vía Edge Function search-semantic (09 §6.2)
      │        │  └───────────┬─────────────┘
      │        │              │
      ▼        ▼              ▼
   ┌─────────────────────────────────┐
   │ Resultados + fuente (badge:      │
   │ exacto / aproximado / semántico) │
   └─────────────────────────────────┘
```

- **No es una carrera de las tres a la vez.** Es cascada: cada nivel solo se activa si el anterior
  no dio confianza suficiente. Esto cumple D-22 y mantiene el caso mayoritario (buscar un código,
  una IP, un nombre) en **una sola query SQL, sin red externa** — el camino más rápido posible.
- **Excepción explícita:** si el usuario pulsa "Buscar por significado" (ej. describe un síntoma:
  "la pantalla se pone azul al iniciar"), se salta directo al paso 4 — el semántico es superior ahí,
  no tiene sentido esperar a que el léxico falle primero.

---

## 3. Normalización de consultas (D-23)

Antes de tocar cualquier motor de búsqueda, la consulta pasa por detección de patrones:

| Patrón detectado | Normalización | Ejemplo |
|---|---|---|
| IPv4 | ceros a la izquierda eliminados, se busca por columna `data->>'ip'` indexada además del texto | `192.168.001.030` → `192.168.1.30` |
| MAC | separadores unificados (`:`/`-`/sin separador) a un formato canónico | `AA-BB-CC-DD-EE-FF` → `aa:bb:cc:dd:ee:ff` |
| Serial / código de activo | sin transformación de mayúsculas (los seriales son *case-sensitive* en la práctica) | — |
| Email | minúsculas | `Juan@Empresa.com` → `juan@empresa.com` |
| Texto libre | tokenización estándar `simple` de Postgres | `no imprime` → tokens `no`, `imprime` |

- Los patrones detectados **añaden una condición extra** a `v1_search_entities` (filtro directo sobre
  el campo tipado, ej. `data->>'ip' = '192.168.1.30'`), que se ejecuta en paralelo al FTS y siempre
  gana en prioridad de ranking si hay coincidencia exacta — es más específico que cualquier score
  de texto libre.
- Esta es la razón de que `field_definitions.is_searchable` (05 §2) no baste por sí solo: los campos
  de tipo `ip`/`mac` necesitan normalización **antes** de comparar, no solo indexación de texto.

---

## 4. Ranking (fórmula y pesos)

Dentro de `v1_search_entities` (09 §5.1), el score final combina:

```
score = w1 · match_exacto_campo_tipado        (1.0 si hay coincidencia normalizada, si no 0)
      + w2 · ts_rank(search_vector, query)      (FTS, con setweight ya definido: name=A, desc=B, campos=C — 05 §3)
      + w3 · similarity(name, query)            (trigram, solo si se llegó a este nivel)
      + w4 · boost_favorito_o_reciente          (pequeño empujón si el usuario ya lo marcó/vio)
```

- **Pesos iniciales sugeridos** (a calibrar con datos reales, no son ley): `w1=100` (domina si hay
  match exacto), `w2=10`, `w3=5`, `w4=1`. La intención de diseño: un match exacto de IP/serial
  **siempre** gana a cualquier score textual — es la búsqueda más común y más urgente en una llamada
  real ("¿qué es 192.168.1.30?").
- **Umbrales de cascada** (D-24): `umbral_alto` y `umbral_medio` (§2) se calibran empíricamente en
  las primeras semanas de uso real (ver §6), no son un número definitivo hoy.

---

## 5. Embeddings — cuándo y qué se vectoriza

| Contenido | ¿Se vectoriza? | Cuándo |
|---|---|---|
| `entities.name` + `description` | Sí | Al crear/editar (encolado async, D-26) |
| Descripción de incidente (para "similares", UC-03) | Sí | Al crear el incidente |
| Contenido de un Procedimiento (objetivo + pasos) | Sí | Al crear/editar |
| Metadatos puros (IP, serial, fechas) | No | Ya cubiertos por match exacto (§3) — vectorizarlos no aporta y diluye la señal |
| Comentarios sueltos | No en MVP | Ruido para la búsqueda de "vecindario"; se reevalúa si hay demanda |

- **Reindexado asíncrono (D-26)**: guardar una entidad no espera a que el embedding se genere. El
  `trigger` de `search_vector` (FTS/trigram) es síncrono y barato (05 §3); el embedding se calcula
  en una cola/Edge Function de fondo y actualiza `entities.embedding` cuando termina. Mientras tanto,
  la entidad ya es buscable por FTS/trigram — nunca "invisible" a la espera del vector.

---

## 6. Medición y mejora continua (D-25)

- **Búsquedas sin clic**: se registra si una sesión de búsqueda terminó sin que el usuario abriera
  ningún resultado — señal de que el ranking o la cobertura fallan.
- **Feedback implícito**: qué resultado (posición en la lista) terminó abriéndose, para medir si
  los primeros puestos son realmente los útiles (similar a CTR).
- Estos datos **no entrenan nada automáticamente** en el MVP (evita la complejidad de un pipeline de
  ML); se usan para **ajustar manualmente los pesos y umbrales** (§4) cada cierto tiempo. Automatizar
  el reajuste queda como evolución v2, condicionada a tener volumen de datos suficiente.
- Estas métricas viven en una tabla ligera `search_events` (consulta normalizada, resultados
  mostrados, cuál se abrió, cuándo) — **no** en `entity_history` (que es historial de negocio, no de
  telemetría de producto).

---

## 7. Autocompletado y sugerencias (soporte a 08 §2)

- **Sugerencias mientras se escribe** (a partir de 2-3 caracteres): consulta ligera solo contra
  `name` con `pg_trgm` (`ILIKE`/`%` con índice GIN trigram) — deliberadamente **sin** FTS completo
  ni semántico en cada tecleo (coste). El resultado completo (cascada §2) se dispara al confirmar o
  tras una pausa de tecleo (debounce, ya definido en 08 §2, ~150 ms).
- **"¿Quisiste decir…?"**: cuando el trigram encuentra una coincidencia cercana pero no supera el
  umbral, se ofrece como sugerencia clicable en vez de autoejecutarse — el usuario decide, el
  sistema no adivina en silencio (evita el efecto "autocorrector molesto").

---

## 8. Rendimiento

- Objetivo ya fijado en 09 §8: `v1_search_entities` <300 ms server-side para la mayoría de consultas
  (las que no llegan al nivel semántico, que es el caso común).
- El nivel semántico (Edge Function, llamada externa) puede tardar más (~500 ms-1 s) — aceptable
  porque **solo se activa cuando el léxico ya falló**, no en el camino feliz.
- Todos los índices que sostienen esto ya existen en el esquema (05 §3): GIN sobre `search_vector`,
  GIN trigram sobre `name`, `ivfflat` sobre `embedding`.

---

## 9. Cumplimiento de la Constitución

| Regla | Cómo se cumple |
|---|---|
| 1 · Búsqueda > navegación | Pipeline completo diseñado como el corazón de la experiencia, no una feature más |
| 10 · Sensación instantánea | Cascada evita coste innecesario; camino feliz resuelto en una sola query SQL indexada |
| 16 · Persona nueva aprende rápido | "¿Quisiste decir…?" y sugerencias en vivo reducen la curva de "saber cómo escribir la búsqueda correcta" |
| Principio más importante (prompt) | Match exacto de IP/MAC/serial normalizado prioritario — resuelve literalmente el ejemplo "192.168.1.30" |

---

## 10. Cuestiones abiertas

1. **Valores exactos de los umbrales** (`umbral_alto`, `umbral_medio`, pesos `w1..w4`): se calibran
   con datos reales de las primeras semanas (§6), no se fijan hoy como definitivos.
2. **¿Vectorizar comentarios?**: diferido a demanda real, según nota de §5.
3. **Automatizar el reajuste de ranking con los datos de `search_events`**: v2, condicionado a
   volumen suficiente de uso.

---

### Próxima tarea
**T-010 · Estrategia de IA / RAG anclado** (entregable 12) — el asistente que responde "POS 14 no
imprime" recorriendo el grafo y citando fuentes, nunca inventando (Constitución, regla 19).
