# 07 · Navegación y arquitectura de información

> Cómo se organizan en pantallas los 7 casos de uso de T-004. Principio rector: **el buscador es
> el centro gravitacional del sistema, no un menú de carpetas** (Constitución, regla 1). La
> navegación por jerarquía existe, pero es secundaria a la navegación por relaciones (grafo).

---

## 1. Decisión de fondo: navegación por grafo, no por módulos

Un IA (información arquitectura) tradicional de ERP/CMDB organiza por módulos: "Activos → POS →
lista → detalle". Eso obliga al usuario a **saber dónde vive el dato** antes de buscarlo — exactamente
lo que la Constitución prohíbe (regla 1). IT Brain invierte el flujo:

```
Entrada al sistema
        │
        ▼
┌───────────────────┐        el usuario NUNCA elige
│   BUSCADOR         │◀────  un módulo primero; escribe
│   (siempre visible)│        lo que sabe (UC-01)
└─────────┬──────────┘
          │ resultado elegido
          ▼
┌───────────────────┐        drill-down libre por
│  FICHA DE ENTIDAD  │◀──┐   relaciones (UC-02): cada
│  (vecindario)      │───┘   salto abre otra ficha
└─────────┬──────────┘
          │
          ▼
   acciones contextuales
   (UC-03..07 según tipo)
```

Los "módulos" (Activos, Incidentes, Procedimientos…) **siguen existiendo**, pero como **filtros
sobre el buscador**, no como jerarquía de navegación obligatoria. Un usuario puede entrar por
"Incidentes recientes" desde el Dashboard, pero es un atajo — nunca la única puerta.

---

## 2. Estructura de shell (armazón de la app)

### 2.1 Móvil (prioridad — Constitución regla 9: "el celular tiene la misma importancia que el computador")

Bottom navigation de **4 destinos fijos**, deliberadamente pocos:

| Destino | Contenido |
|---|---|
| **Inicio** | Dashboard: buscador, favoritos, recientes, incidentes abiertos, alertas |
| **Buscar** | Buscador a pantalla completa (mismo motor que el de Inicio, sin distracción) |
| **Crear** (botón central, FAB) | Acceso directo a: nuevo Incidente, nueva Entidad, nuevo Adjunto rápido (cámara) |
| **Yo** | Favoritos, mis incidentes asignados, notificaciones, configuración de cuenta |

No hay un 5º ítem "Módulos". Los tipos de entidad (POS, Servidor, Switch…) se alcanzan **buscando
o filtrando desde Inicio/Buscar**, nunca desde un tab dedicado — así se cumple la regla 7
(ningún tipo nuevo requiere un nuevo ítem de navegación).

### 2.2 Web / Tablet / Windows

Mismo modelo, con un **rail lateral** en vez de bottom nav (más espacio horizontal), y el buscador
anclado en la parte superior de **todas** las pantallas (patrón "command palette" tipo Raycast/Linear
— accesible también con atajo de teclado, ej. `Ctrl+K`). El rail añade, opcionalmente, accesos de
**Configuración/Administración** (solo visibles para Admin) que en móvil quedan dentro de "Yo".

> Una sola base de código Flutter (Constitución, plataformas): el shell se adapta por *breakpoint*,
> no se duplica la lógica de navegación.

---

## 3. Patrón de drill-down por el grafo (UC-02)

Este es el punto más delicado: navegar relaciones puede crear una pila de pantallas sin límite
(POS → Impresora → Switch → Puerto → Servidor → BD → …). Reglas:

1. **Cada salto es un `push` normal** en el stack de navegación (no un modal) — el botón "atrás"
   del sistema siempre funciona y es predecible.
2. **Breadcrumb de grafo** en la cabecera de la ficha: no muestra una ruta de carpetas, muestra la
   **cadena de relaciones recorrida** (`POS-14 → conectado_a → Switch Piso 2`), para que el
   usuario nunca pierda el hilo de *por qué* llegó ahí.
3. **Deduplicación de ciclos:** si el usuario recorre A→B→A, no se apila una ficha repetida — se
   vuelve (`pop`) a la instancia existente en el stack. Evita el problema clásico de los grafos
   (bucles infinitos de navegación).
4. **Preview in-place vs. push completo:** expandir una relación en la propia ficha (mini-card, sin
   navegar) es la acción por defecto (0 clics extra); solo se hace `push` a ficha completa si el
   usuario pulsa explícitamente sobre la entidad relacionada. Esto cumple la regla 8 (mínimos clics)
   sin sacrificar profundidad de exploración.

---

## 4. Jerarquía de pantallas por caso de uso (T-004 → pantalla)

| Caso de uso | Pantalla(s) | Nº de toques desde Inicio |
|---|---|---|
| UC-01 Buscar | Buscador (Inicio o tab Buscar) → lista de resultados | 1 (escribir cuenta como 1 acción) |
| UC-02 Vecindario | Ficha de entidad (con secciones colapsables: Datos / Relaciones / Historial / Adjuntos) | 2 (buscar → abrir) |
| UC-03 Incidente | FAB "Crear" → formulario de Incidente (con entidad afectada pre-vinculada si se abrió desde una ficha) | ≤3 |
| UC-04 Credencial | Ficha de credencial → botón "Revelar" (con confirmación ligera, no fricción excesiva) | 2–3 |
| UC-05 Nuevo tipo/campo | Solo accesible vía "Yo/Configuración → Tipos de entidad" (Admin) — deliberadamente fuera del flujo diario | N/A (administrativo) |
| UC-06 Adjunto | Ficha de entidad → botón cámara/adjuntar (acceso también directo desde el FAB de Inicio: "Adjuntar rápido") | 1–2 |
| UC-07 Invitar usuario | "Yo/Configuración → Miembros" (Admin) | N/A (administrativo) |

> Regla de diseño explícita: **las pantallas administrativas (UC-05, UC-07) están intencionalmente
> apartadas** del flujo de "resolver una incidencia". Mezclarlas violaría la regla 12
> (ninguna funcionalidad puede romper la simplicidad del sistema).

---

## 5. El Dashboard como punto de entrada (no como página de aterrizaje pasiva)

Ya definido en la Constitución/prompt original; aquí se fija su **prioridad visual** (de arriba a
abajo, más frecuente primero):

1. Buscador (siempre lo primero, siempre visible).
2. Incidentes abiertos asignados a mí / al equipo (acción inmediata).
3. Favoritos.
4. Recientes.
5. Alertas del sistema (activos con demasiados incidentes, credenciales por expirar, etc. — UC de
   aprendizaje automático).
6. Procedimientos más utilizados.

Esta jerarquía es **configurable por rol**: Consulta no ve "Incidentes asignados a mí" si no
gestiona incidentes; Admin ve además un resumen de salud del sistema.

---

## 6. Deep linking y estado

- Toda entidad, incidente y procedimiento tiene una URL/deep-link canónica (`itbrain://entity/{id}`)
  — necesario para compartir un enlace por WhatsApp/email y que abra directo la ficha (cumple la
  filosofía de "todo el conocimiento centralizado", evita que el enlace en sí se vuelva la fuga de
  información que IT Brain busca eliminar).
- El estado de navegación (stack, breadcrumb de grafo) se restaura al reabrir la app en móvil
  (persistencia de sesión de navegación), no solo el estado de datos.

---

## 7. Qué NO hace esta capa (para no romper simplicidad)

- No hay un árbol de carpetas ni un selector de "módulo" como paso obligatorio.
- No hay más de 4 destinos fijos en la navegación principal, en ninguna plataforma.
- No se introduce breadcrumb de *ubicación jerárquica* (tipo "Activos > POS > Caja 3") — el
  breadcrumb es siempre de **relación recorrida**, coherente con el modelo de grafo.

---

## 8. Cumplimiento de la Constitución

| Regla | Cómo se cumple |
|---|---|
| 1 · Búsqueda > navegación | Buscador como shell persistente, no como pantalla entre otras |
| 8 · Mínimos clics | Preview in-place por defecto; FAB con accesos directos; tabla §4 con conteo real de toques |
| 9 · Celular = computador | Mismo modelo de IA en ambas plataformas, solo cambia el contenedor visual (bottom nav ↔ rail) |
| 12 · No romper la simplicidad | Administración deliberadamente separada del flujo operativo diario |

---

## 9. Cuestiones abiertas

1. **Atajo de teclado global en desktop** (`Ctrl+K` estilo Raycast): confirmar tecla exacta al
   hacer los wireframes (T-006) para no chocar con atajos nativos de Windows/navegador.
2. **Persistencia del stack de navegación al cerrar la app en móvil**: ¿siempre, o solo si se cerró
   sin completar una acción? Se decide con datos de uso real, no bloquea el MVP.

---

### Próxima tarea
**T-006 · Wireframes / UX de pantallas clave** (entregable 08) — dar forma visual a esta jerarquía:
Dashboard, Buscador, Ficha de entidad con vecindario, formulario de Incidente.
