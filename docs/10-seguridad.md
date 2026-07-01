# 10 · Estrategia de Seguridad

> Seguridad transversal de IT Brain. Cierra las cuestiones abiertas de los entregables 04 (permisos),
> 05 (BD) y 09 (API). Principio rector: **la fuga entre tenants es el fallo catastrófico #1**; todo
> lo demás se subordina a impedirla. Defensa en profundidad, no una sola barrera.

---

## 1. Decisiones de este entregable

| # | Decisión | Elección | Motivo |
|---|----------|----------|--------|
| D-17 | **Gestión de claves de cifrado** | **Cifrado sobre + Supabase Vault** con envelope encryption por org (DEK por tenant, KEK raíz en Vault) | Clave fuera de las tablas de negocio; aislamiento criptográfico por empresa; migrable a KMS externo sin cambiar el contrato |
| D-18 | **Rate limiting** | Token-bucket **por usuario y por org**; en BD para el MVP, Upstash Redis al escalar; WAF/Cloudflare al borde | Protege las Edge Functions con coste externo (embeddings) y frena fuerza bruta |
| D-19 | **MFA en acciones críticas** | Revelar secreto y acciones de admin exigen **AAL2** (MFA), no solo rol | Un token robado sin segundo factor no puede exfiltrar secretos |
| D-20 | **Derecho al olvido vs. historial inmutable** | **Crypto-shredding** (destruir la clave del dato) en lugar de borrar filas | Concilia GDPR con la Constitución (regla 5: nunca borrar historial) |
| D-21 | **Aislamiento de tenant** | RLS + tests automáticos de aislamiento en CI como *gate* de despliegue | El aislamiento se verifica, no se asume |

---

## 2. Gestión de claves y cifrado de secretos (cierra 04/05/09)

### 2.1 Envelope encryption por organización

```
KEK raíz (Supabase Vault / KMS externo)   ← nunca sale de la bóveda; rota sin tocar datos
   │  cifra
   ▼
DEK por organización (almacenada cifrada)  ← 1 clave por tenant = aislamiento criptográfico
   │  cifra
   ▼
secrets.ciphertext (por credencial)         ← lo que vive en la tabla (05 §7)
```

- La **DEK de cada org** se guarda cifrada (envuelta por la KEK). Descifrar un secreto requiere:
  desenvolver la DEK con la KEK (en Vault) → descifrar el `ciphertext`. Ambos pasos ocurren **solo
  dentro de la Edge Function `reveal-secret`** (09 §6.1), nunca en el cliente ni en una tabla legible.
- **Consecuencia de seguridad**: comprometer la base de datos entera **no** revela ni un secreto,
  porque la KEK vive fuera de ella. Un `SELECT` de `secrets` (permitido a supervisor+ por RLS)
  devuelve bytes inútiles.
- **Rotación**: rotar la KEK re-envuelve las DEK (barato, no toca `secrets`). Rotar una DEK de org
  re-cifra solo los secretos de esa org (operación de fondo, auditada en `secret_access_log` con
  `action='rotate'`).

### 2.2 Migrabilidad (por qué esta decisión no nos encierra)

El contrato de `reveal-secret` (09) no expone *cómo* se gestiona la clave. Pasar de Supabase Vault a
un KMS externo (AWS KMS / GCP KMS) en enterprise es cambiar la implementación de una función, no el
esquema ni el cliente. Coherente con la regla 11 (arquitectura válida a 10 años).

### 2.3 Cifrado en tránsito y en reposo

- **Tránsito**: TLS 1.2+ obligatorio en todo (Supabase por defecto); HSTS.
- **Reposo**: cifrado de disco de Postgres y Storage (gestionado por Supabase); **más** la capa de
  aplicación (envelope) para secretos — doble cobertura sobre el dato más sensible.
- **Storage**: buckets **privados**; acceso solo por **Signed URLs** caducas (09 §4); nunca URLs
  públicas para adjuntos que puedan contener información sensible (capturas, PDFs de config).

---

## 3. Rate limiting y protección de abuso (cierra 09)

| Superficie | Límite | Dónde |
|---|---|---|
| `search-semantic` (coste de embedding externo) | p. ej. 30/min por usuario, 300/min por org | Token-bucket en Edge Function |
| `reveal-secret` | p. ej. 10/min por usuario + alerta a admin si pico anómalo | Edge Function + `secret_access_log` |
| Login / reset password | Límite por IP + backoff exponencial | Supabase Auth + WAF |
| PostgREST (CRUD masivo) | `limit` máx 100, sin offset profundo (09 §3) | Convención de API + WAF |

- **MVP**: contadores en una tabla `rate_limits` (org_id, user_id, bucket, window). **Al escalar**:
  Upstash Redis (baja latencia, TTL nativo).
- **Borde**: Cloudflare/WAF delante del dominio para mitigar DoS volumétrico y bots antes de que
  lleguen a las Functions.
- **Alerta, no solo bloqueo**: un pico de `reveal-secret` de un usuario dispara notificación al
  Admin (posible cuenta comprometida) — detección, no solo prevención.

---

## 4. Autenticación reforzada (cierra 04)

- **MFA (TOTP / AAL2)**: obligatorio para Admin y Supervisor (ya en 04). Aquí se **eleva**: revelar
  un secreto exige `aal2` en el JWT **independientemente del rol** — un Técnico con grant debe tener
  MFA activa. La Edge Function rechaza `aal1` con `MFA_REQUIRED`.
- **Sesiones**: JWT de vida corta + refresh rotativo; revocación de sesión al cambiar rol o suspender
  membership. Cambio de `active_org_id` reemite el token (04 §2.2).
- **Invitaciones**: enlaces de un solo uso con caducidad; el rol se asigna en el servidor, nunca
  viaja como parámetro manipulable desde el cliente.
- **SSO/SAML corporativo**: v2 (04 §10), sin cambiar el modelo de roles.

---

## 5. Aislamiento multi-tenant — el control crítico

Es el fallo catastrófico #1, así que se defiende en tres capas y **se verifica**:

1. **RLS en todas las tablas** (05 §9) — la frontera dura. `org_id` derivado siempre del JWT vía
   `public.org_id()`, nunca de un parámetro del cliente.
2. **RPC `security invoker`** (09 §5) — las operaciones compuestas heredan RLS; ninguna función de
   negocio usa `security definer`.
3. **Edge Functions** — aunque usan `service_role` (que omite RLS), cada una revalida `membership`
   y filtra por `org_id` manualmente; las que consultan datos lo hacen **con el JWT del usuario**
   (09 §6.2), no con `service_role`, salvo el descifrado puntual.

> **Gate de despliegue (D-21)**: una batería de tests de aislamiento en CI crea 2 orgs y verifica
> que el usuario A **jamás** puede leer/escribir/buscar datos de la org B por ninguna vía (CRUD, RPC,
> Edge, búsqueda semántica). Si un solo test falla, no se despliega. El aislamiento no se asume.

---

## 6. Modelo de amenazas (checklist accionable)

| Amenaza | Vector | Mitigación en IT Brain |
|---|---|---|
| **Fuga entre tenants** | RLS mal escrita, `org_id` de parámetro, `definer` descuidado | RLS + `public.org_id()` desde JWT + tests de aislamiento en CI (§5) |
| **Exposición de secretos** | DB comprometida, log del valor, cache en cliente | Envelope encryption con clave fuera de la BD (§2); se audita el *acceso*, nunca el *valor* (04 §7); sin cache, revelado único |
| **Escalada de privilegios** | Manipular rol/claim | Rol resuelto en servidor desde `memberships`; `role_rank()` en cada request; cambios en `audit_log` |
| **IDOR** (acceso a id ajeno) | Adivinar UUID de otra org | RLS devuelve 404 (no 403) para recursos fuera de la org (09 §3) |
| **Inyección SQL** | Entrada no parametrizada | PostgREST y RPC parametrizados; `search_path=''` si algún día hay `definer` (09 §7) |
| **Mass assignment** | Escribir campos no permitidos en `data` JSONB | Validación en backend contra `field_definitions` (`min_role_write`, tipos) antes de persistir (04 §5) |
| **JWT robado / replay** | Token filtrado | Vida corta + refresh rotativo + revocación; **MFA (AAL2)** para acciones críticas (§4) |
| **DoS por cómputo caro** | Abusar de `search-semantic` | Rate limiting por usuario/org + WAF (§3) |
| **Acceso a Storage** | URL de adjunto adivinable | Buckets privados + Signed URLs caducas (§2.3) |
| **Cadena de suministro** | Dependencia Flutter/Deno comprometida | *Pinning* de versiones, escaneo de dependencias en CI, revisión de paquetes nuevos |
| **Manipulación de auditoría** | Borrar/editar logs para ocultar rastro | `revoke update, delete` (05 §6/§8); solo `service_role` inserta; retención inmutable (§7) |

Mapeo a **OWASP Top 10** (A01 Broken Access Control → §5/RLS; A02 Cryptographic Failures → §2; A04
Insecure Design → todo el enfoque de diseño-primero; A07 Auth Failures → §4; A09 Logging Failures → §7).

---

## 7. Auditoría, retención y cumplimiento

- **Inmutabilidad**: `entity_history`, `secret_access_log`, `audit_log` son append-only por permisos
  (05). Refuerzo opcional v2: **encadenamiento de hash** (cada fila incluye el hash de la anterior)
  para detección de manipulación a nivel criptográfico.
- **Retención**: logs de acceso a secretos y auditoría admin se conservan mínimo el periodo legal
  aplicable; los datos de negocio no caducan (Constitución 4/6). Retención configurable por org.
- **Derecho al olvido (GDPR) vs. historial inmutable (D-20)**: no se borran filas de historial
  —se aplica **crypto-shredding**: los datos personales sensibles se cifran con una clave por sujeto;
  al ejercer el derecho de supresión, se **destruye esa clave**, dejando el dato irrecuperable pero
  la traza de auditoría intacta. Resuelve la tensión sin violar ninguna de las dos exigencias.
- **Residencia de datos**: la región de Supabase por org es un requisito enterprise (v2); el esquema
  multi-tenant no lo impide.

---

## 8. Seguridad en el ciclo de desarrollo (DevSecOps)

- **Migraciones**: revisadas; ninguna abre RLS por error (una migración que crea tabla sin
  `enable row level security` debe fallar el lint de CI).
- **Secret scanning** en el repo (que no se filtren claves en commits).
- **Tests de seguridad como parte del pipeline**: aislamiento de tenant (§5), verificación de que
  las políticas RLS existen en cada tabla nueva, y que las Edge Functions rechazan `aal1` donde toca.
- **Principio de menor privilegio** en las credenciales de servicio (la `service_role` solo la usan
  las Edge Functions, nunca el frontend ni CI general).

---

## 9. Cumplimiento de la Constitución

| Regla | Cómo se cumple |
|---|---|
| 4 · No depender de personas | Roles y accesos gestionados centralmente; revocables sin perder conocimiento |
| 5 / 13 · Registro y trazabilidad | Auditoría inmutable + encadenamiento de hash (v2) + crypto-shredding que preserva la traza |
| 11 · Arquitectura a 10 años | Gestión de claves migrable a KMS externo sin cambiar contrato ni esquema |
| 19 · IA solo usa lo almacenado | La IA recupera bajo el rol del usuario; RLS impide que cruce a otra org o a un secreto |

---

## 10. Cuestiones abiertas

1. **Encadenamiento de hash en auditoría**: ¿MVP o v2? Recomendación: v2 (append-only ya da la
   garantía base; el hash-chain es defensa contra un atacante con `service_role`, escenario avanzado).
2. **Proveedor de KMS externo** para enterprise (AWS vs. GCP): se decide con el primer cliente que lo
   exija; el diseño ya lo contempla.
3. **Política concreta de retención por jurisdicción**: se parametriza por org; los valores por
   defecto se fijan con asesoría legal antes del lanzamiento comercial.

---

### Próxima tarea
**T-009 · Estrategia de búsqueda** (entregable 11) — pipeline FTS + trigram + embeddings, fusión y
tuning de relevancia, y el umbral de degradación tolerante a errores que quedó abierto en UC-01.
