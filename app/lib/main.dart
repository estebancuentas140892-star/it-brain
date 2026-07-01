import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';

/// Punto de entrada de IT Brain.
///
/// Inicializa Supabase (Auth/Postgres/Storage) antes de arrancar la UI.
/// Las claves se inyectan por `--dart-define` (ver core/config/env.dart), nunca
/// se hardcodean (docs/10-seguridad.md §8).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const _MisconfiguredApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(
    const ProviderScope(
      child: ItBrainApp(),
    ),
  );
}

/// Pantalla de arranque cuando faltan las variables de entorno, para dar un
/// mensaje claro en vez de un crash opaco.
class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Faltan las variables de entorno SUPABASE_URL y SUPABASE_ANON_KEY.\n\n'
              'Ejecuta con:\n'
              'flutter run --dart-define=SUPABASE_URL=... '
              '--dart-define=SUPABASE_ANON_KEY=...',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
