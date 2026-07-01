# 03 · Modelo de Entidades + Relaciones

> El corazón de IT Brain. Todo lo demás (base de datos, búsqueda, IA, UX) se deriva de aquí.
> Este documento define el modelo **lógico**, no el esquema físico (eso es el entregable 05).

---

## 1. Principios de diseño

1. **Todo es una Entidad**, pero no toda entidad es igual: cada una pertenece a un **Arquetipo**
   que le da comportamiento y campos base, y a un **Tipo** que la especializa.
2. **Los tipos son datos, no código.** Añadir "Cámara térmica" o "Balanza de caja" no requiere
   desplegar nada: se crea un tipo desde configuración (Constitución, regla 7).
3. **El grafo vive en aristas explícitas y con significado.** No es "todo enlazado con todo" a
   ciegas: cada relación tiene un tipo semántico (`depende_de`, `conectado_a`, `resuelto_por`…),
   pero *cualquier* entidad puede relacionarse con *cualquier* otra (Constitución, regla 3).
4. **Modelo híbrido, no EAV puro** (Decisión D-04): lo común va en columnas tipadas; lo variable,
   en `JSONB` validado por la definición del tipo.
5. **Multi-tenant desde el esquema** (D-01): `org_id` en cada fila, aislado por RLS.
6. **Historial a nivel de valor y append-only** (Constitución, reglas 5 y 13): nada se pierde.

---

## 2. La capa que lo cambia todo: Arquetipos

En lugar de 40 "módulos" rígidos, definimos **~10 Arquetipos**. Un arquetipo es una familia de
entidades que comparten comportamiento, campos base y semántica de relación. Esto es lo que hace
que el sistema **no se rediseñe** cuando aparece un activo nuevo: solo se crea un tipo dentro de
un arquetipo existente.

| Arquetipo | Qué agrupa | Campos base característicos |
|-----------|-----------|-----------------------------|
| **Device** (Activo físico/virtual) | POS, Servidor, Switch, Router, Firewall, Access Point, Impresora, UPS, Cámara, Teléfono IP, Tablet, Celular, Monitor, Rack, VM | marca, modelo, serial, IP, MAC, ubicación, estado operativo, garantía |
| **Network** (Elemento de red) | VLAN, Red/Subred, Puerto, Dominio | rango, gateway, máscara, número de puerto |
| **Software** (Lógico) | Sistema, Servicio, Base de Datos, Aplicación | versión, fabricante, puerto, endpoint |
| **License** | Licencia | tipo, asientos, fecha de expiración, clave (protegida) |
| **Credential** | Credencial, Secreto, API Key | usuario, **secreto cifrado**, URL, expiración *(seguridad especial → §7)* |
| **Identity** | Usuario, Rol | email, cargo, permisos |
| **Location** | Sede, Oficina, Rack, Sala | dirección, piso, contacto |
| **Party** (Tercero) | Proveedor, Cliente | contacto, teléfono, contrato, SLA |
| **Knowledge** | Procedimiento, Manual, Solución, Problema Frecuente | objetivo, pasos, dificultad, tiempo estimado |
| **Case** (Evento/Trabajo) | Incidente, Problema, Proyecto | prioridad, estado, diagnóstico, causa, solución, tiempos |

> **Guardrail:** los arquetipos son un conjunto *cerrado y versionado* (los define el equipo de
> IT Brain, no el cliente). El cliente crea **tipos** libremente dentro de ellos. Así evitamos el
> *inner-platform effect* sin sacrificar la flexibilidad que pediste.

**Multimedia (PDF, video, imagen, captura):** no son entidades de primer nivel por defecto — son
**adjuntos** de cualquier entidad (§6). Se pueden *promover* a entidad Knowledge cuando un manual
o video merece vida propia y relaciones. Decisión abierta marcada en §9.

---

## 3. Estructura común de toda Entidad

Todas las entidades comparten este núcleo (Constitución: estructura común):

```
entities
├── id              uuid  (PK)
├── org_id          uuid  → organizations        (multi-tenant, RLS)
├── entity_type_id  uuid  → entity_types          (el tipo, que apunta a un arquetipo)
├── name            text                          (buscable, obligatorio)
├── description     text                          (buscable)
├── status          text                          (por tipo: activo, en reparación, dado de baja…)
├── category        text
├── owner_id        uuid  → identities            (responsable)
├── data            jsonb                         (valores de campos personalizados, validados)
├── search_vector   tsvector  (generado)          (FTS)
├── embedding       vector    (pgvector)          (búsqueda semántica / IA)
├── created_at      timestamptz
├── updated_at      timestamptz
├── created_by      uuid
├── updated_by      uuid
└── archived_at     timestamptz  (nullable)       (baja lógica; nunca se borra)
```

Alrededor giran tablas satélite compartidas por **todas** las entidades:

- `tags` (globales por organización) + `entity_tags` — etiquetas globales (Constitución).
- `attachments` — fotos, capturas, videos, PDF, Office, ZIP, audio, enlaces (§6).
- `comments` — hilos de comentarios.
- `entity_history` — auditoría a nivel de campo, append-only (§5).
- `favorites (user_id, entity_id)` — favoritos por usuario.
- `recent_views (user_id, entity_id, viewed_at)` — recientes automáticos.

---

## 4. El meta-modelo (tipos y campos como datos)

Aquí es donde "añadir campos sin programar" se vuelve real.

```
entity_types
├── id, org_id (nullable = tipo de sistema)
├── key            text   ('pos', 'servidor', 'impresora'…)
├── name, icon, color
├── archetype      enum   (device | network | software | license | credential |
│                          identity | location | party | knowledge | case)
├── parent_type_id uuid   (herencia opcional: 'POS' hereda de 'Device genérico')
└── is_system      bool

field_definitions           (define el formulario dinámico de cada tipo)
├── id, entity_type_id
├── key, label, help_text
├── data_type      enum   (text | number | bool | date | datetime | enum |
│                          reference | ip | mac | url | email | secret | json | geo)
├── is_required, is_unique, is_searchable
├── options        jsonb  (para enum)
├── reference_type uuid   (si data_type = reference → a qué tipo apunta)
└── group, sort_order      (para maquetar la vista de detalle)
```

- Los **valores** de esos campos se guardan en `entities.data` (JSONB) y se **validan** contra las
  `field_definitions` al escribir (en el backend, no en el cliente).
- `is_searchable = true` → ese campo se proyecta al `search_vector` mediante trigger.
- `data_type = reference` es el puente entre el formulario y el grafo: seleccionar un valor de
  referencia **crea una relación** automáticamente (ej.: el campo "Impresora asignada" de un POS).

---

## 5. Modelo de Relaciones (el grafo)

```
relationship_types
├── id, org_id (nullable = de sistema)
├── key            text   ('depende_de', 'conectado_a', 'ubicado_en', 'ejecuta',
│                          'licenciado_por', 'documentado_por', 'resuelto_por', 'afecta_a'…)
├── name           text   ('depende de')
├── inverse_name   text   ('da servicio a')          ← el grafo se lee en ambos sentidos
├── is_directional bool
└── source_archetypes / target_archetypes  (restricciones blandas de qué conecta con qué)

relationships                (la tabla de aristas — EL grafo)
├── id, org_id
├── source_entity_id  uuid  → entities
├── target_entity_id  uuid  → entities
├── type_id           uuid  → relationship_types
├── metadata          jsonb (ej.: puerto físico, fecha de instalación, criticidad del vínculo)
├── valid_from, valid_to    (relaciones con vigencia temporal — opcional)
├── created_at, created_by
```

Índices en **ambas** direcciones (`source_entity_id` y `target_entity_id`) para poder recorrer el
vecindario de cualquier entidad en milisegundos. La navegación del usuario y las respuestas de la
IA son, literalmente, recorridos de 1–2 saltos sobre esta tabla.

### Historial (append-only)

```
entity_history
├── id, org_id, entity_id
├── field            text     (qué campo cambió; 'relationship' para altas/bajas de aristas)
├── old_value, new_value  jsonb
├── changed_by, changed_at
└── reason           text     (motivo, opcional)
```

Nunca se hace `UPDATE`/`DELETE` sobre esta tabla. Poblada por triggers.

---

## 6. Adjuntos y multimedia

```
attachments
├── id, org_id, entity_id
├── kind        enum (image | screenshot | video | pdf | office | zip | audio | link)
├── storage_path / external_url
├── caption, mime_type, size_bytes
├── uploaded_by, uploaded_at
```

Los binarios viven en **Supabase Storage**; la fila `attachments` es el metadato + la relación con
la entidad. Cualquier entidad puede tener N adjuntos (Constitución: multimedia universal).

---

## 7. Credenciales — el caso especial de seguridad (D-05)

Una credencial **es** una entidad (arquetipo `credential`), pero su secreto **no** se guarda en
`entities.data` ni se indexa. Va a una tabla endurecida y separada:

```
secrets
├── id, org_id
├── credential_entity_id  → entities   (la parte "pública": usuario, URL, sistema, expiración)
├── ciphertext            bytea        (cifrado; clave gestionada fuera de la fila)
└── rotated_at

secret_access_log        (auditoría: Constitución de Credenciales)
├── secret_id, user_id, action (view | reveal | update | rotate), at, ip, user_agent
```

- Se **busca** una credencial por metadatos (sistema, activo, usuario, URL) — nunca por el secreto.
- Revelar el secreto es una acción explícita, con permiso, y **queda registrada** (quién y cuándo).

---

## 8. Ejemplo de extremo a extremo — *"POS 14 no imprime"*

Así se modela y así lo recorre el sistema. Este es el caso que justifica toda la arquitectura.

**Entidades** (cada una con su arquetipo):
`POS-14` (device) · `Impresora Epson TM-T20` (device) · `Switch Piso 2` (device) ·
`Puerto 24` (network) · `Servidor SQL` (device/software) · `BD Ventas` (software) ·
`SAP` (software) · `Licencia SAP` (license) · `Epson` (party/proveedor) ·
`Proc. "Reiniciar cola de impresión"` (knowledge) · `Incidente #1234` (case).

**Relaciones (aristas):**
```
POS-14 ──usa──▶ Impresora Epson
Impresora Epson ──conectada_a──▶ Puerto 24 ──en──▶ Switch Piso 2
POS-14 ──depende_de──▶ Servidor SQL ──aloja──▶ BD Ventas
POS-14 ──ejecuta──▶ SAP ──licenciado_por──▶ Licencia SAP
Impresora Epson ──suministrada_por──▶ Epson (proveedor)
Incidente #1234 ──afecta_a──▶ POS-14
Incidente #1234 ──resuelto_por──▶ Proc. "Reiniciar cola de impresión"
Proc. ──documenta──▶ Impresora Epson
```

**Recorrido real del técnico (Constitución: <10 s, <3 toques):**
1. Escribe `POS 14` (o `192.168.1.30`, o `Caja 3`) → FTS + trigram lo encuentra pese a typos.
2. Abre la entidad → la **vista de detalle muestra su vecindario** (1–2 saltos): impresora, switch,
   puerto, servidor, licencia, proveedor, procedimientos e incidentes previos.
3. La **IA** responde recorriendo esas aristas + recuperando incidentes con firma similar vía
   `embedding`: *"Este POS usa la Epson TM-T20 en el Puerto 24 del Switch Piso 2. Incidentes
   previos de impresión (3) se resolvieron con el procedimiento X. Tiempo medio: 4 min. Quien más
   lo ha resuelto: Juan."* — todo **citado** contra entidades reales; si no hay datos, lo dice.

---

## 9. Cuestiones abiertas (a decidir en los próximos entregables)

1. **Herencia de tipos** (`parent_type_id`): ¿la habilitamos en el MVP o la dejamos para v2? Añade
   potencia (campos heredados) pero también complejidad de validación. *Recomendación: v2.*
2. **Promoción de adjuntos a entidad Knowledge** (§2): ¿flujo manual o sugerido por IA?
3. **Relaciones temporales** (`valid_from/valid_to`): ¿MVP o v2? *Recomendación: columna presente,
   UI en v2.*
4. **Cardinalidad y validación de relaciones**: ¿bloqueamos aristas inválidas (device→license sin
   sentido) o solo advertimos? *Recomendación: advertir, no bloquear — favorece la flexibilidad.*
5. **`status` como texto libre vs. catálogo por tipo**: *Recomendación: catálogo por tipo* para
   permitir dashboards por estado.

---

## 10. Cómo esta capa cumple la Constitución

| Regla | Cómo se cumple |
|-------|----------------|
| 2 · Todo es una Entidad | Tabla `entities` universal + arquetipos |
| 3 · Todo se relaciona con todo | Tabla `relationships` con tipos semánticos |
| 6 · Todo puede evolucionar | `field_definitions` + `JSONB`: campos nuevos sin código |
| 7 · No rediseñar por un activo nuevo | Nuevo *tipo* dentro de un arquetipo existente |
| 5 · Toda modificación queda registrada | `entity_history` append-only + triggers |
| 13 · Siempre trazabilidad | Historial + `secret_access_log` + auditoría |

---

### Próximo entregable sugerido
**04 · Multi-tenancy y permisos** (define RLS y permisos por entidad/campo/acción antes de aterrizar
el esquema físico), o directamente **05 · Base de datos** (DDL, índices, triggers y políticas RLS).
