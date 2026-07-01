# 13 · Estrategia de sincronización y offline

> Caché de **solo lectura** de favoritos / recientes / críticos (decisión D-02). El técnico que
> recibe una llamada en un sótano sin señal debe poder consultar la info crítica. Se apoya en la
> seguridad (10) y la API (09). **No hay escritura offline ni resolución de conflictos** — y eso
> es una decisión de diseño, no una limitación.

---

## 1. El principio: solo lectura elimina el problema más difícil

La sincronización bidireccional con resolución de conflictos sobre un grafo y un esquema flexible es
de lo más difícil que existe (se advirtió al elegir D-02). Al restringir el offline a **lectura**:

- **No hay conflictos que resolver** — nunca dos versiones del mismo dato compitiendo.
- **No hay cola de escritura** que reconciliar ni riesgo de perder cambios del usuario.
- La complejidad se reduce a un problema tratable: **mantener una copia local fresca y segura de un
  subconjunto de datos**.

Esto respeta la regla 12 (ninguna funcionalidad rompe la simplicidad). La escritura offline con
CRDTs queda como evolución v2, si la demanda real lo justifica.

---

## 2. Decisiones de este entregable

| # | Decisión | Elección | Motivo |
|---|----------|----------|--------|
| D-33 | **Almacenamiento local** | **SQLite (Drift)** + FTS5 | Espeja el modelo relacional/grafo; permite búsqueda local; maduro en Flutter |
| D-34 | **Cifrado de la caché** | **SQLCipher** con clave en el **enclave seguro** del dispositivo (Keychain/Keystore) | Un dispositivo perdido no expone datos de la empresa |
| D-35 | **Qué se cachea** | Offline set = favoritos + recientes + críticos + **su vecindario a 1 salto** + procedimientos ligados | Cubre el caso real "resolver una incidencia" sin traer toda la base |
| D-36 | **Sincronización** | **Pull incremental** (delta por `updated_at` + tombstones); Realtime solo cuando hay conexión | Barato; nunca "invisible"; sin push desde cliente (es read-only) |
| D-37 | **Caducidad de la caché** | **Max-offline-age**: tras N días sin reconectar, la caché se bloquea | Acota la ventana en que un permiso revocado sigue vigente offline |

---

## 3. Qué se cachea (el "offline set")

| Contenido | ¿Offline? | Razón |
|---|---|---|
| Entidades **favoritas** | ✔ | El usuario las marcó como importantes explícitamente |
| Entidades **recientes** (últimas N) | ✔ | Contexto probable de la próxima consulta |
| Entidades marcadas **críticas** (por la org) | ✔ | Equipos clave que deben consultarse siempre |
| **Vecindario a 1 salto** de todo lo anterior | ✔ | Que la ficha (UC-02) funcione offline: relaciones, no solo el nodo |
| **Procedimientos** ligados a esas entidades | ✔ | Son *el* recurso para resolver sin conexión |
| Metadatos de **credenciales** del vecindario | ✔ (solo metadatos) | Ver usuario/sistema/URL |
| **Secreto** de una credencial | ✖ **nunca** | El descifrado es online-only y auditado (10 §2); jamás toca el dispositivo |
| Adjuntos pesados (video, ZIP) | Solo bajo demanda / pin | No saturar el almacenamiento; imágenes y PDF de procedimientos sí, por su valor operativo |
| Búsqueda semántica y **asistente IA** | ✖ | Requieren servidor (11/12); offline solo hay búsqueda léxica local (FTS5) |

> **Regla dura de seguridad**: la caché nunca contiene más de lo que el usuario podía leer **en el
> momento del sync** — el enmascarado de campos sensibles (04 §5) ya se aplicó en servidor antes de
> enviar. El dispositivo nunca almacena datos que el rol no alcanzaba.

---

## 4. Almacenamiento y cifrado local (D-33, D-34)

```
Dispositivo (Flutter)
├── SQLCipher (SQLite cifrado)          ← toda la caché, cifrada en reposo
│   ├── tablas espejo: entities, relationships, procedures, tags…
│   └── índice FTS5                      ← búsqueda léxica local (subconjunto de 11)
└── flutter_secure_storage
    └── clave de SQLCipher               ← en Keychain (iOS) / Keystore (Android),
                                            respaldada por enclave seguro / hardware
```

- La **clave de cifrado de la caché** vive en el enclave seguro del dispositivo, no en la app ni en
  el código. Si el dispositivo se pierde **bloqueado**, la caché es ilegible sin desbloquearlo.
- La búsqueda offline usa **FTS5 local** — una versión reducida de la cascada de 11 (sin trigram
  avanzado ni semántico, que necesitan servidor). El usuario busca dentro de lo cacheado y se le
  indica claramente que es "búsqueda en datos guardados".

---

## 5. Sincronización de lectura (D-36)

```
Al conectar / al abrir la app con red:
  1. Pull inicial (primera vez): descarga el offline set completo (§3).
  2. Delta sync:  v1_sync_pull(since = último_sync_ok)
        → entidades/relaciones cambiadas (updated_at > since)
        → TOMBSTONES: ids archivados/eliminados desde 'since'  → se purgan localmente
  3. Realtime (mientras haya conexión): suscripción a cambios del offline set
        → mantiene la caché fresca en vivo, sin polling
  4. Se guarda el nuevo cursor 'since' y el timestamp 'last_sync_ok'.
```

- **`v1_sync_pull(since)`** es un RPC nuevo a añadir al contrato de 09, `security invoker` (RLS
  aplica: solo devuelve lo que el usuario puede ver **ahora**). Devuelve cambios **y tombstones**
  para que la caché no conserve algo que fue archivado o que el usuario ya no puede ver.
- **Nunca invisible**: como el offline set es pequeño, el delta es rápido; entre syncs, la entidad
  ya cacheada sigue disponible con su marca de frescura (§7).

---

## 6. Coherencia y permisos al reconectar — el punto delicado

Qué pasa si, **mientras el usuario estaba offline**, un admin le bajó el rol, lo suspendió, o
restringió un dato. Un dispositivo verdaderamente sin red **no se puede purgar en remoto** — hay que
acotar la exposición, no fingir que se elimina:

1. **Max-offline-age (D-37)**: si la caché lleva más de N días sin un sync exitoso, se **bloquea**
   (no se muestra) hasta reconectar y revalidar. Acota la ventana de un permiso revocado. `N` es
   configurable por org según su sensibilidad (p. ej. 7 días por defecto, menos para orgs muy
   sensibles).
2. **Revalidación al reconectar**: el primer acto tras recuperar red es validar `membership`/rol. Si
   el usuario fue **suspendido** → se **purga toda la caché** de inmediato. Si fue **degradado** →
   `v1_sync_pull` devuelve como tombstones lo que ya no puede ver, y se purga.
3. **Los secretos nunca son el problema**: como jamás se cachean (§3), un permiso de credencial
   revocado offline no expone nada — el secreto siempre requirió servidor.
4. **Honestidad de diseño**: existe una ventana inherente (dispositivo offline con permiso recién
   revocado) que **ninguna** solución puede cerrar sin conexión. La acotamos con max-offline-age y la
   documentamos; no la ocultamos. Para datos que no toleran esa ventana, la respuesta correcta es
   marcarlos como no-cacheables (v2: flag por tipo/campo).

---

## 7. Experiencia de usuario offline

- **Banner claro**: *"Sin conexión — mostrando datos guardados del 01/07 14:30"*. El usuario siempre
  sabe que ve una copia y de cuándo.
- **Frescura por entidad**: badge sutil "actualizado hace X" en fichas cacheadas; si supera cierto
  umbral, se resalta como "puede estar desactualizado".
- **Acciones de escritura deshabilitadas** con explicación ("Disponible al reconectar"), no ocultas
  sin más — coherente con la transparencia del resto de la UX (08).
- **Delimitación del offline set**: se puede ver "qué tengo disponible sin conexión" para que el
  usuario entienda los límites (y pueda *fijar* algo antes de perder señal).

---

## 8. Gestión de tamaño

- **LRU con tope configurable**: lo menos usado se expulsa primero al alcanzar el límite.
- **Pin explícito**: marcar favorito **garantiza** retención (no se expulsa por LRU) — el usuario
  controla qué siempre está disponible.
- Los adjuntos pesados no cuentan al offline set por defecto; se descargan bajo demanda o al fijarlos.

---

## 9. Qué NO está disponible offline (degradación explícita)

| Función | Offline | Alternativa |
|---|---|---|
| Consultar entidades del offline set | ✔ | — |
| Búsqueda léxica local (FTS5) | ✔ | Solo dentro de lo cacheado |
| Ver vecindario / procedimientos cacheados | ✔ | — |
| Revelar secreto | ✖ | Requiere servidor + auditoría (10) |
| Búsqueda semántica / asistente IA | ✖ | Requieren servidor (11/12) |
| Crear/editar cualquier cosa | ✖ | Read-only por diseño (D-02) |

---

## 10. Contrato de API añadido (extiende 09)

```
v1_sync_pull(p_since timestamptz)
  returns jsonb  -- { changed: entity[], relations[], procedures[], tombstones: uuid[], cursor }
  security invoker   -- RLS: solo lo que el usuario puede ver AHORA
```
- Alimenta el pull inicial (`since = null`) y el delta. Los tombstones son la pieza que evita caché
  obsoleta o sobre-privilegiada.

---

## 11. Cumplimiento de la Constitución

| Regla | Cómo se cumple |
|---|---|
| Sección OFFLINE (prompt) | Consulta de info crítica sin conexión; sincroniza al volver la red |
| 12 · No romper la simplicidad | Solo lectura → sin resolución de conflictos, el problema difícil se elimina de raíz |
| 10 · Sensación instantánea | Caché local sirve al instante; Realtime la mantiene fresca online |
| 4 / 9 · Conocimiento disponible, celular = computador | El técnico consulta desde el móvil aunque esté sin señal |

---

## 12. Cuestiones abiertas

1. **Valor por defecto de max-offline-age** (7 días propuesto): confirmar por perfil de sensibilidad
   de org.
2. **Flag "no-cacheable" por tipo/campo** (para datos que no toleran la ventana offline): diseñado
   conceptualmente, implementación v2.
3. **Tope de tamaño de caché por defecto** y política de adjuntos: calibrar con dispositivos reales.

---

### Próxima tarea
**T-012 · Definición del alcance del MVP** (entregable 14) — qué entra en la primera versión
entregable y qué se difiere, sintetizando todas las decisiones MVP/v2 tomadas a lo largo de 03–13.
