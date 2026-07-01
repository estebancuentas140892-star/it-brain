import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'supabase_providers.dart';

/// Organización activa del usuario + su rol en ella.
///
/// `roleRank` replica `public.role_rank()` (migración 0002) en el cliente para
/// **gate de UI** (mostrar/ocultar acciones). No es una frontera de seguridad:
/// la frontera real es la RLS en el servidor (docs 04 §3, defensa en profundidad).
class ActiveOrg {
  const ActiveOrg({required this.orgId, required this.role});

  final String orgId;
  final String role;

  int get roleRank => switch (role) {
        'admin' => 4,
        'supervisor' => 3,
        'tecnico' => 2,
        'consulta' => 1,
        _ => 0,
      };

  /// Puede gestionar el esquema (crear tipos/campos) — UC-05, rank ≥ 4.
  bool get canManageSchema => roleRank >= 4;

  /// Puede crear/editar entidades — rank ≥ 2 (técnico+).
  bool get canCreateEntities => roleRank >= 2;
}

/// Resuelve la org activa del usuario.
///
/// Fuente preferente: los claims `active_org_id`/`active_role` del JWT, que
/// inyecta el access token hook (migración 0011, T-017). Es la **misma** fuente
/// que usa la RLS (`public.org_id()` lee ese claim), así que no hay divergencia
/// cliente/servidor. El `active_role` puede quedar obsoleto tras un cambio de rol
/// hasta el siguiente refresh del token, pero solo se usa para gate de UI.
///
/// Degradación (hook aún no desplegado): primera membresía activa vía
/// `memberships` — funciona gracias a la policy `memberships_select_self` (0009).
final activeOrgProvider = FutureProvider<ActiveOrg?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  // Se recomputa al cambiar la sesión (login/logout/refresh).
  ref.watch(authStateProvider);

  final session = client.auth.currentSession;
  if (session == null) return null;

  final claims = _decodeJwtPayload(session.accessToken);
  final claimOrg = claims?['active_org_id'] as String?;
  if (claimOrg != null) {
    final claimRole = claims?['active_role'] as String?;
    return ActiveOrg(orgId: claimOrg, role: claimRole ?? 'consulta');
  }

  // Fallback: consultar la primera membresía activa.
  final user = client.auth.currentUser;
  if (user == null) return null;
  final rows = await client
      .from('memberships')
      .select('org_id, role')
      .eq('user_id', user.id)
      .eq('status', 'active')
      .limit(1);
  if (rows.isEmpty) return null;
  final m = rows.first;
  return ActiveOrg(orgId: m['org_id'] as String, role: m['role'] as String);
});

/// Decodifica el payload (claims) de un JWT sin verificar la firma — solo para
/// LEER claims propios ya emitidos por Supabase (la verificación es del servidor).
Map<String, dynamic>? _decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final normalized = base64.normalize(parts[1]);
    final decoded = utf8.decode(base64.decode(normalized));
    final json = jsonDecode(decoded);
    return json is Map<String, dynamic> ? json : null;
  } catch (_) {
    return null;
  }
}
