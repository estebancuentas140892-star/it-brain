import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cliente de Supabase compartido en toda la app.
///
/// Se inicializa en `main.dart` (Supabase.initialize) antes de runApp; aquí solo
/// se expone la instancia ya lista a través de Riverpod para respetar la
/// inyección de dependencias de Clean Architecture (nada accede a
/// `Supabase.instance` directamente fuera de este provider).
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Stream del estado de autenticación (sesión activa / cierre de sesión).
///
/// Base para el guard del router (docs/07-navegacion.md) y para resolver la
/// organización activa del usuario (docs/04-multitenancy-permisos.md §2.2).
final authStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

/// Sesión actual (o null si no hay usuario autenticado).
final currentSessionProvider = Provider<Session?>((ref) {
  // Se recomputa cuando cambia el estado de auth.
  ref.watch(authStateProvider);
  return ref.watch(supabaseClientProvider).auth.currentSession;
});
