/// Excepciones de infraestructura (capa data).
///
/// Se lanzan en los datasources y las traducen los repositorios a `Failure`
/// (ver `failures.dart`). No deben propagarse a la capa de presentación.
class ServerException implements Exception {
  ServerException(this.message, {this.code});
  final String message;
  final String? code;
}

class NetworkException implements Exception {
  NetworkException([this.message = 'Sin conexión']);
  final String message;
}

class CacheException implements Exception {
  CacheException([this.message = 'Error en la caché local']);
  final String message;
}
