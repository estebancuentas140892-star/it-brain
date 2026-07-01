import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/supabase_providers.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/entities/domain/entity.dart';
import '../../features/entities/presentation/screens/create_entity_screen.dart';
import '../../features/entities/presentation/screens/entities_by_type_screen.dart';
import '../../features/entities/presentation/screens/entity_detail_screen.dart';
import '../../features/meta_model/presentation/screens/create_entity_type_screen.dart';
import '../../features/meta_model/presentation/screens/entity_types_screen.dart';

/// Router de la app (go_router).
///
/// Soporta el shell de navegación (docs/07-navegacion.md) y deep links
/// `itbrain://entity/{id}` (docs 07 §6). El guard redirige a login si no hay
/// sesión activa.
final routerProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseClientProvider);
  // Imprescindible: sin refreshListenable, go_router NO re-evalúa el guard
  // cuando cambia la sesión, así que tras iniciar sesión la navegación se queda
  // en /login. Este puente re-dispara el redirect en cada cambio de auth.
  final refresh = GoRouterRefreshStream(client.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = client.auth.currentSession != null;
      final loggingIn = state.matchedLocation == '/login';

      if (!loggedIn) return loggingIn ? null : '/login';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
        // Rutas hijas (buscador, ficha de entidad, incidentes...) se añaden
        // al implementar cada feature.
      ),

      // Meta-modelo (UC-05): tipos de entidad + creación de tipo/campos.
      GoRoute(
        path: '/config/types',
        name: 'entity-types',
        builder: (context, state) => const EntityTypesScreen(),
        routes: [
          GoRoute(
            path: 'new',
            name: 'create-entity-type',
            builder: (context, state) => const CreateEntityTypeScreen(),
          ),
        ],
      ),

      // Listado de entidades de un tipo (una categoría). `extra` = nombre del tipo.
      GoRoute(
        path: '/types/:typeId/entities',
        name: 'entities-by-type',
        builder: (context, state) => EntitiesByTypeScreen(
          entityTypeId: state.pathParameters['typeId']!,
          typeName: state.extra as String? ?? 'Categoría',
        ),
      ),

      // Ficha de una entidad. `extra` = la Entity ya cargada de la lista.
      GoRoute(
        path: '/entities/:id',
        name: 'entity-detail',
        builder: (context, state) {
          final entity = state.extra as Entity?;
          if (entity == null) {
            return const Scaffold(
              body: Center(child: Text('Entidad no encontrada.')),
            );
          }
          return EntityDetailScreen(entity: entity);
        },
      ),

      // Creación de una entidad de un tipo (formulario dinámico). `extra` = nombre.
      GoRoute(
        path: '/entities/new/:typeId',
        name: 'create-entity',
        builder: (context, state) => CreateEntityScreen(
          entityTypeId: state.pathParameters['typeId']!,
          typeName: state.extra as String? ?? 'Entidad',
        ),
      ),
    ],
  );
});

/// Puente entre un `Stream` (el estado de auth de Supabase) y el
/// `refreshListenable` de go_router: cada emisión re-evalúa el `redirect`, de
/// modo que iniciar/cerrar sesión actualiza la navegación automáticamente.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
