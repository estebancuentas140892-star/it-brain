# IT Brain — App (Flutter)

Cliente multiplataforma de IT Brain. Base única para Android · iOS · Web · Windows · Tablet.
La arquitectura y decisiones de producto viven en [`../docs`](../docs).

## Stack

- **Flutter** + **Riverpod** (estado) + **go_router** (navegación)
- **Clean Architecture** + **MVVM**
- **Supabase** (Auth · Postgres · Storage · RLS)
- **Drift/SQLite + SQLCipher** para la caché offline de solo lectura (docs 13)
- **freezed** para modelos inmutables

## Estructura (Clean Architecture)

```
lib/
├── main.dart                 # entrada: inicializa Supabase, arranca la app
├── app.dart                  # widget raíz (MaterialApp.router)
├── core/                     # transversal, sin lógica de negocio
│   ├── config/               # env (--dart-define), configuración
│   ├── providers/            # providers base (SupabaseClient, auth)
│   ├── router/               # go_router + guard de sesión
│   ├── theme/                # tema (docs 08)
│   └── error/                # failures (domain) y exceptions (data)
└── features/                 # una carpeta por feature, con 3 capas cada una
    ├── auth/
    │   └── presentation/     # (data/ y domain/ se añaden al implementar)
    ├── dashboard/
    │   └── presentation/
    └── ...                   # entities, search, incidents, credentials...

  Cada feature sigue:
    data/         → datasources (Supabase/Drift) + repositorios (impl)
    domain/       → entidades, contratos de repositorio, casos de uso
    presentation/ → providers (ViewModel), screens, widgets
```

## Cómo ejecutar

Las claves NUNCA se hardcodean; se inyectan por `--dart-define` (docs 10 §8):

```bash
flutter pub get

flutter run \
  --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=TU_ANON_KEY
```

Para web: `flutter run -d chrome --dart-define=...`

Generación de código (freezed/riverpod/drift), cuando se añadan modelos:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Estado

Scaffolding inicial (tarea T-013). Corre y muestra login → dashboard placeholder.
Las features se construyen siguiendo la secuencia de [docs/14-alcance-mvp.md §5](../docs/14-alcance-mvp.md).
