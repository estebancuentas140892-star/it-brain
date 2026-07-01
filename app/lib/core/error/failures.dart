/// Fallos de dominio (capa domain de Clean Architecture).
///
/// Los repositorios traducen las excepciones de infraestructura (ver
/// `exceptions.dart`) a estos `Failure`, de modo que la capa de presentación
/// nunca depende de detalles de Supabase/Postgres.
///
/// El modelo de códigos se alinea con el contrato de API (docs/09-api.md §3):
/// FORBIDDEN_ROLE, SECRET_ACCESS_DENIED, ENTITY_NOT_FOUND, VALIDATION_ERROR...
sealed class Failure {
  const Failure(this.message, {this.code});

  final String message;
  final String? code;
}

/// Error de red / sin conexión. Dispara el modo offline (docs/13-offline-sync.md).
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Sin conexión']);
}

/// El usuario no tiene permiso para la acción (RLS / rol insuficiente).
class PermissionFailure extends Failure {
  const PermissionFailure([super.message = 'No tienes permiso para esta acción'])
      : super(code: 'FORBIDDEN_ROLE');
}

/// Recurso no encontrado (o fuera de la organización — 404, no 403; docs 09 §3).
class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'No encontrado'])
      : super(code: 'ENTITY_NOT_FOUND');
}

/// Error de validación de datos (campos personalizados, etc.).
class ValidationFailure extends Failure {
  const ValidationFailure(super.message) : super(code: 'VALIDATION_ERROR');
}

/// Fallo inesperado del servidor.
class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Error del servidor']);
}
