# IT Brain — Tests de base de datos (aislamiento de tenant)

Estos tests son el **gate de despliegue no negociable** definido en
[docs/10-seguridad.md §5](../../docs/10-seguridad.md) (decisión D-21): ningún esquema toca un
entorno real sin que pasen.

## Qué verifican (0001_tenant_isolation_test.sql)

Que un usuario de una organización **jamás** accede a datos de otra, por ninguna vía a nivel de
base de datos (RLS). 50 aserciones (21 grupos, 0–20) sobre:

- **Entidades:** lectura/escritura aislada por org, rol insuficiente, update cruzado sin efecto.
- **Secretos:** invisibles para consulta/técnico (rank < 3); supervisor solo ve el de su org.
- **Relaciones:** aisladas por org, con **control positivo** (admin A ve exactamente 1) para que
  el test no pueda pasar "por vacío" si la fixture dejara de insertar.
- **Historial / auditoría:** append-only real (UPDATE/DELETE → `42501`) y auditoría solo-admin,
  aislada por org.
- **Satélites** (comentarios, etiquetas, tags): no cruzan de tenant.
- **Meta-modelo:** un tipo/campo *custom* de A no es visible ni escribible desde B; y **nadie**
  puede escribir campos sobre un tipo de **sistema** (regresión de `fields_write`, ver abajo).
- **Rol `anon`** (sin sesión): no ve ni escribe nada.
- **Membresía suspendida:** aunque el JWT afirme la org, no hay acceso (revocación efectiva).
- **Usuario multi-org:** el claim selecciona la org **correcta**, nunca las dos a la vez.
- **El test clave** — falsear el claim `active_org_id` no otorga acceso (D-08).
- **Access token hook** (T-017): el hook `custom_access_token_hook` inyecta la org
  activa en el JWT y **nunca** una org de la que el usuario no sea miembro activo
  (un suspendido no recibe org); solo `supabase_auth_admin` puede ejecutarlo.
- **Bootstrap de org** (T-017): sin org activa, un usuario ve solo SUS membresías
  (policy `memberships_select_self`), nunca las de otros.
- **Smoke (Test 0):** guardián de la recursión de RLS (ver abajo).

### Dos defectos reales encontrados y corregidos al endurecer este gate

Escribir el test *en serio* (no solo contar filas) destapó dos huecos que un test superficial
habría tapado con una luz verde falsa:

1. **Recursión infinita en la RLS de `memberships`.** `public.org_id()`/`public.role_rank()` (0002)
   no eran `SECURITY DEFINER`, pero la política de `memberships` (0009) se define sobre
   `public.org_id()`. Leer `memberships` dentro de la función re-disparaba su RLS →
   `infinite recursion detected in policy for relation memberships`. **Ninguna** consulta
   autenticada habría funcionado. Corregido con `SECURITY DEFINER` + `search_path` fijado. El
   **Test 0** lo vigila.
2. **`fields_write` sin ámbito de org (0009).** Permitía a cualquier admin añadir campos a un
   tipo de **sistema** (`org_id IS NULL`), visible para todas las orgs → contaminación del
   esquema compartido. Acotado a los tipos de la propia org. El **Test 17** lo vigila.

## Cómo ejecutar localmente

Requiere **Docker** y la **CLI de Supabase**:

```bash
# desde la raíz del repo (que contiene supabase/)
supabase start        # levanta Postgres + auth + aplica migrations/ y seed
supabase test db      # corre los .sql de supabase/tests/ con pgTAP
supabase stop
```

En CI se ejecuta automáticamente en [.github/workflows/ci.yml](../../.github/workflows/ci.yml)
(job `tenant-isolation`), que **bloquea el merge/despliegue** si falla.

## El gate CRECE con las features

La cobertura actual es **RLS a nivel de tabla** (la frontera dura). A medida que se implementen,
cada una de estas piezas DEBE añadir su propio test de aislamiento aquí:

- [ ] RPC `v1_search_entities` / `v1_entity_neighborhood` — que la búsqueda no cruce de org
- [ ] RPC `v1_match_entities` — que la búsqueda semántica no filtre entidades de otra org (docs 12 §9)
- [ ] RPC `v1_create_incident` / `v1_close_incident`
- [ ] RPC `v1_sync_pull` — que el delta offline respete RLS y tombstones (docs 13)
- [ ] Edge Function `reveal-secret` — que solo descifre con rol/grant válido y audite (test de integración aparte)

## Estado

⚠️ **Escritos pero NO ejecutados en la máquina de desarrollo** (no hay Docker/Supabase local; el
disco C: no tenía espacio para el stack). Por diseño (D-21) el enforcement vive en CI, no en local.
La primera corrida real ocurrirá en el pipeline al hacer push al repositorio.

Los dos arreglos de arriba (recursión de RLS en 0002, ámbito de `fields_write` en 0009) se derivan
por razonamiento sobre la semántica de Postgres/RLS, **no se han podido ejecutar aún**. La primera
corrida en CI es la que los confirma: se espera que el Test 0 (recursión) y el Test 17 (fields_write)
pasen en verde. Si algún ajuste de fixtures o de la CLI hiciera falta, se corrige en esa corrida.
