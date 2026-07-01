/// Configuración de entorno.
///
/// Los valores se inyectan en tiempo de compilación con `--dart-define` (o
/// `--dart-define-from-file`), NUNCA se hardcodean. Esto respeta la estrategia
/// de seguridad (docs/10-seguridad.md §8): las claves no viven en el repo.
///
/// Ejemplo de ejecución:
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Valida que el entorno esté completo antes de arrancar la app.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
