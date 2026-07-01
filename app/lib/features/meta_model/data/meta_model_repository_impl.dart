import '../../../core/error/exceptions.dart';
import '../../../core/error/failures.dart';
import '../../entities/domain/entity.dart';
import '../domain/archetype.dart';
import '../domain/entity_type.dart';
import '../domain/field_definition.dart';
import '../domain/meta_model_repository.dart';
import 'meta_model_remote_data_source.dart';

/// Implementación del repositorio del meta-modelo sobre Supabase. Su única
/// responsabilidad extra sobre el datasource es traducir las excepciones de
/// infraestructura a `Failure` de dominio (docs 09 §3: 404 en vez de 403 para
/// no filtrar existencia cross-tenant; 42501 → permiso denegado).
class MetaModelRepositoryImpl implements MetaModelRepository {
  MetaModelRepositoryImpl(this._remote);

  final MetaModelRemoteDataSource _remote;

  @override
  Future<List<EntityType>> getEntityTypes() =>
      _guard(() => _remote.getEntityTypes());

  @override
  Future<List<FieldDefinition>> getFieldDefinitions(String entityTypeId) =>
      _guard(() => _remote.getFieldDefinitions(entityTypeId));

  @override
  Future<List<Entity>> getEntities(String entityTypeId) =>
      _guard(() => _remote.getEntities(entityTypeId));

  @override
  Future<EntityType> createEntityTypeWithFields({
    required String orgId,
    required String key,
    required String name,
    required Archetype archetype,
    required List<FieldDefinition> fields,
    String? icon,
    String? color,
  }) =>
      _guard(() async {
        final type = await _remote.insertEntityType(
          orgId: orgId,
          key: key,
          name: name,
          archetype: archetype,
          icon: icon,
          color: color,
        );
        await _remote.insertFieldDefinitions(type.id, fields);
        return type;
      });

  @override
  Future<String> createEntity({
    required String orgId,
    required String entityTypeId,
    required String name,
    required Map<String, dynamic> data,
  }) =>
      _guard(() => _remote.insertEntity(
            orgId: orgId,
            entityTypeId: entityTypeId,
            name: name,
            data: data,
          ),);

  /// Ejecuta [action] traduciendo excepciones de infraestructura a `Failure`.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ServerException catch (e) {
      throw _mapServer(e);
    } on NetworkException catch (e) {
      throw NetworkFailure(e.message);
    }
  }

  Failure _mapServer(ServerException e) {
    switch (e.code) {
      case '42501': // insufficient_privilege → RLS/rol
        return const PermissionFailure();
      case '23505': // unique_violation → key ya usado
        return ValidationFailure('Ya existe un elemento con esa clave: ${e.message}');
      case '23514': // check_violation
      case '22P02': // invalid_text_representation (enum/uuid inválido)
        return ValidationFailure(e.message);
      case 'PGRST116': // 0 filas donde se esperaba 1
        return const NotFoundFailure();
      default:
        return ServerFailure(e.message);
    }
  }
}
