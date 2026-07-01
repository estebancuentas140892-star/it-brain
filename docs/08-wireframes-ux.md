# 08 · Wireframes / UX de pantallas clave

> Forma visual de la arquitectura de navegación (07) sobre los casos de uso (06).
> Wireframes descritos en estructura de bloques (no pixel-perfect — eso es tarea de UI final),
> con jerarquía visual, estados y comportamiento responsive. Referencia estética: Linear, Notion,
> Apple HIG, Raycast, Obsidian. **Nada recargado. Mucho espacio en blanco. Tipografía como jerarquía.**

---

## 0. Principios visuales transversales

1. **Densidad progresiva**: la vista por defecto muestra lo esencial; el detalle se revela al
   interactuar (hover en desktop, tap en móvil), nunca todo de una vez.
2. **Una acción primaria por pantalla**, visualmente dominante; el resto son acciones secundarias
   (texto o icono, no botones compitiendo).
3. **Estados siempre diseñados, no como ocurrencia tardía**: vacío, cargando, error y "sin resultados"
   se especifican junto con el estado feliz, no después.
4. **Color con significado, no decorativo**: estado de entidad (activo/crítico/archivado), prioridad
   de incidente. Fuera de eso, monocromo con acentos mínimos.
5. **La misma jerarquía de información en móvil y desktop** — cambia el contenedor, no el modelo
   mental (Constitución, regla 9).

---

## 1. Dashboard (Inicio)

```
┌─────────────────────────────────────────────┐
│  🔍  Buscar cualquier cosa...           ⌘K   │  ← franja de búsqueda, siempre arriba, fija
├─────────────────────────────────────────────┤
│  ⚠ 2 activos requieren revisión              │  ← alertas (aprendizaje automático), solo si hay
├───────────────────┬───────────────────────────┤
│ Incidentes         │  Favoritos                │
│ abiertos (3)       │  ★ Servidor SQL Principal  │
│ • POS-14 no imprime│  ★ Switch Piso 2           │
│ • VPN caída Sede N │  ★ Proc. Reinicio impresión│
├───────────────────┼───────────────────────────┤
│ Recientes          │  Procedimientos            │
│ (últimos 5, con    │  más usados                │
│  timestamp relativo)│  (top 3, con contador)     │
└───────────────────┴───────────────────────────┘
```

- **Móvil:** las cuatro secciones se apilan verticalmente (una columna), en el mismo orden de
  prioridad definido en el entregable 07 §5. Incidentes abiertos siempre primero tras alertas.
- **Estado vacío:** un usuario nuevo ve la franja de búsqueda dominante y un mensaje breve
  ("Empieza buscando un equipo, o crea tu primera entidad") — nunca secciones vacías con bordes
  punteados genéricos.
- **Carga:** *skeleton* (bloques grises pulsantes) por sección, nunca un spinner de pantalla completa
  — cumple "la app debe sentirse instantánea" (regla 10) al mostrar estructura antes que datos.

---

## 2. Buscador (UC-01)

```
┌─────────────────────────────────────────────┐
│  🔍  POS 14                              ✕   │
├─────────────────────────────────────────────┤
│  ▸ POS-14                          [Device]  │  ← resultado principal, tipo como badge
│    Caja 3 · Sede Centro · Activo             │
│    Relacionado: Impresora Epson, Switch P2   │  ← preview de vecindario, sin navegar
├─────────────────────────────────────────────┤
│  ▸ Incidente #1189 — "POS 14 no imprime"     │  ← resultados de otros tipos, mismo carril
│    Resuelto hace 12 días · 4 min             │
├─────────────────────────────────────────────┤
│  ▸ Proc. Reinicio de cola de impresión       │
│    Usado 23 veces · Tiempo est. 3 min        │
└─────────────────────────────────────────────┘
```

- Resultados **agrupados solo si hay ambigüedad real** (mismo término, tipos muy distintos);
  si no, lista única ordenada por relevancia — evita el "acordeón de categorías" que ralentiza
  el escaneo visual.
- Tipeo con debounce corto (~150 ms); resultados aproximados (`pg_trgm`) se marcan con un matiz
  visual sutil ("resultado aproximado") para no confundir con coincidencia exacta.
- **Sin resultados:** nunca una pantalla vacía seca — sugiere: "¿Quisiste decir…?" (trigram) o
  "Crear una entidad nueva con este nombre" (acción constructiva, no callejón sin salida).
- **Desktop:** se abre como *command palette* superpuesta (`⌘K`/`Ctrl+K`), no como página aparte —
  refuerza que el buscador es shell, no destino (entregable 07 §1).

---

## 3. Ficha de entidad — vecindario (UC-02)

La pantalla más importante del sistema después del buscador. Estructura en **secciones
colapsables**, todas visibles en resumen, expandibles bajo demanda:

```
┌─────────────────────────────────────────────┐
│ ← POS-14 → conectado_a → Switch Piso 2       │  ← breadcrumb de RELACIÓN recorrida (no carpeta)
├─────────────────────────────────────────────┤
│ 🖥  POS-14                     [Activo] ★ ⋯  │  ← nombre + tipo + estado + favorito + menú
│    Caja 3 · Sede Centro                      │
├─────────────────────────────────────────────┤
│ ▾ Datos                                      │  ← campos propios, renderizados desde
│    Serial: XT4021    IP: 192.168.1.30        │    field_definitions (dinámico)
│    Modelo: Epson X350                        │
├─────────────────────────────────────────────┤
│ ▾ Relaciones (6)                              │
│   🖨 usa → Impresora Epson TM-T20      [+]   │  ← [+] expande preview in-place
│   🔀 depende_de → Servidor SQL          [+]   │
│   ⚠ afecta_a ← Incidente #1189 (resuelto)     │
│   📄 documentado_por → Proc. Reinicio...      │
├─────────────────────────────────────────────┤
│ ▾ Historial (4 cambios)                       │  ← colapsado por defecto
├─────────────────────────────────────────────┤
│ ▾ Adjuntos (2)        📷 Foto  📎 Manual PDF  │
└─────────────────────────────────────────────┘
   [＋ Adjuntar]  [＋ Comentar]  [＋ Incidente]   ← acciones contextuales fijas al pie (móvil)
```

- **Campos sensibles** (`sensitivity = sensitive`): se muestran atenuados con un icono de candado
  si el rol no alcanza `min_role_read`; nunca simplemente ocultos sin explicación (transparencia
  sobre por qué no se ve algo).
- **Relaciones**: cada fila muestra el **verbo semántico** (`usa`, `depende_de`, `documentado_por`)
  y la dirección (→/←), coherente con `inverse_name` del entregable 03/05.
- **Desktop/tablet:** dos columnas — Datos+Relaciones a la izquierda, Historial+Adjuntos+Comentarios
  a la derecha, sin necesidad de colapsar tanto (más espacio horizontal disponible).

---

## 4. Formulario de Incidente (UC-03)

```
┌─────────────────────────────────────────────┐
│  Nuevo Incidente                        ✕    │
├─────────────────────────────────────────────┤
│  Afecta a: [POS-14 ✕]  + añadir otro equipo  │  ← pre-vinculado si se abrió desde una ficha
│  Prioridad: ○ Baja ● Media ○ Alta ○ Crítica  │
│  Descripción:                                │
│  ┌───────────────────────────────────────┐   │
│  │ No imprime desde esta mañana...        │   │
│  └───────────────────────────────────────┘   │
├─────────────────────────────────────────────┤
│  💡 Incidentes similares (2)                  │  ← sugerencia en vivo mientras se escribe
│     #1189 "POS 14 no imprime" → resuelto en   │    (búsqueda semántica sobre la descripción)
│     4 min con Proc. Reinicio de cola          │
├─────────────────────────────────────────────┤
│              [Cancelar]   [Crear Incidente]   │
└─────────────────────────────────────────────┘
```

- La caja **"Incidentes similares"** es la materialización visual de UC-03 paso 3 (buscar antes de
  reinventar la solución) — aparece *durante* la creación, no después, para acortar el tiempo de
  resolución real.
- Al cerrar el incidente (pantalla separada, no descrita aquí en detalle): campos de diagnóstico/
  causa/solución con el mismo patrón de "sugerir procedimiento similar" y, si aplica, el prompt de
  aprendizaje automático: *"Este tipo de incidente ya ocurrió 5 veces. ¿Crear un procedimiento
  permanente?"* — un banner discreto, no un modal bloqueante.

---

## 5. Revelado de credencial (UC-04)

```
┌─────────────────────────────────────────────┐
│  🔑 Credencial: SAP — Usuario Ventas          │
├─────────────────────────────────────────────┤
│  Sistema: SAP           URL: sap.empresa.com  │
│  Usuario: ventas01      Expira: 2026-12-01    │
├─────────────────────────────────────────────┤
│  Contraseña: •••••••••••     [ Revelar ]      │  ← oculto por defecto, siempre
├─────────────────────────────────────────────┤
│  ℹ Esta acción quedará registrada             │  ← visible ANTES de pulsar, no después
└─────────────────────────────────────────────┘
        ↓ al pulsar "Revelar"
┌─────────────────────────────────────────────┐
│  Contraseña: Kx9$mPz2Qw          [Copiar]     │
│  ✓ Consulta registrada · 01/07/2026 14:32     │  ← confirmación visible, refuerza confianza
└─────────────────────────────────────────────┘
```

- Fricción **mínima pero honesta**: un solo toque para revelar, pero el aviso de auditoría es
  visible *antes* de la acción, no una letra pequeña. Coherente con "no soy un gestor de
  contraseñas que oculta lo que hace con ellas".
- Si el rol no alcanza permiso: el botón "Revelar" se sustituye por "Solicitar acceso" (v2) —
  nunca desaparece sin explicación ni deja al usuario adivinando por qué no puede.

---

## 6. Tabla de estados obligatorios por pantalla

| Pantalla | Vacío | Cargando | Error | Sin permiso |
|---|---|---|---|---|
| Dashboard | Mensaje + CTA "buscar/crear" | Skeleton por sección | Banner discreto, resto de la UI usable | N/A |
| Buscador | Sugerencia "¿Quisiste decir…?" + crear nueva | Skeleton de 3 filas | "No se pudo buscar, reintentar" | N/A |
| Ficha de entidad | N/A (siempre tiene datos) | Skeleton de secciones | Sección con error inline, resto carga igual | Campo con candado + tooltip |
| Incidente (form) | N/A | Botón "Crear" con spinner inline | Validación inline por campo | Formulario no accesible (bloqueado antes de abrir) |
| Credencial | N/A | Spinner solo en el valor revelado | "No se pudo descifrar, reintentar" | Botón "Solicitar acceso" |

---

## 7. Cumplimiento de la Constitución

| Regla | Cómo se cumple |
|---|---|
| 1 · Búsqueda > navegación | Command palette en desktop; franja fija en móvil; nunca una "página" aparte |
| 8 · Mínimos clics | Preview in-place `[+]`; acciones contextuales fijas al pie; revelar en 1 toque |
| 10 · Sensación instantánea | Skeletons en vez de spinners de pantalla completa |
| 15/16 · Aprendizaje colectivo | "Incidentes similares" visible durante la creación, no como paso posterior |

---

## 8. Cuestiones abiertas

1. **Sistema de diseño formal** (tokens de color, tipografía, espaciado): se define como
   entregable propio si el proyecto lo requiere antes de implementar en Flutter, o se deriva
   directamente de un paquete de theming (Material 3 / Cupertino adaptativo) — decisión de
   implementación, no bloquea el diseño funcional aquí descrito.
2. **Accesibilidad (contraste, tamaños táctiles, lector de pantalla):** a incorporar como checklist
   en el momento de implementación de cada pantalla, no como documento aparte del roadmap original.

---

### Próxima tarea
**T-007 · Diseño de la API** (entregable 09) — contrato formal (RPCs, vistas, Edge Functions) que
sirve estas pantallas: búsqueda combinada, vecindario paginado, `reveal_secret`, alta de incidente.
