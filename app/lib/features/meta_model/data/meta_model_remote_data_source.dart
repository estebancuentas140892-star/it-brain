import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/exceptions.dart';
import '../../entities/domain/entity.dart';
import '../domain/archetype.dart';
import '../domain/entity_type.dart';
import '../domain/field_definition.dart';

/// Acceso directo a Supabase/PostgREST para el meta-modelo. Todas las escrituras
/// pasan por RLS (docs 04/05); este datasource **no** usa `service_role`. Traduce
/// los `PostgrestException` en `ServerException` con el código PostgREST, que el
/// repositorio mapea a `Failure` (p. ej. 42501 → `PermissionFailure`).
class MetaModelRemoteDataSource {
  MetaModelRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<List<EntityType>> getEntityTypes() async {
    try {
      final rows = await _client
          .from('entity_types')
          .select()
          .order('is_system', ascending: false)
          .order('name');
      return rows
          .map((r) => EntityType.fromJson(r))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(e.message, code: e.code);
    }
  }

  Future<List<FieldDefinition>> getFieldDefinitions(String entityTypeId) async {
    try {
      final rows = await _client
          .from('field_definitions')
          .select()
          .eq('entity_type_id', entityTypeId)
          .order('sort_order');
      return rows
          .map((r) => FieldDefinition.fromJson(r))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(e.message, code: e.code);
    }
  }

  Future<EntityType> insertEntityType({
    required String orgId,
    required String key,
    required String name,
    required Archetype archetype,
    String? icon,
    String? color,
  }) async {
    try {
      // org_id es obligatorio: la policy `types_write` exige org_id = public.org_id().
      final row = await _client
          .from('entity_types')
          .insert({
            'org_id': orgId,
            'key': key,
            'name': name,
            'archetype': archetype.wire,
            if (icon != null) 'icon': icon,
            if (color != null) 'color': color,
          })
          .select()
          .single();
      return EntityType.fromJson(row);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, code: e.code);
    }
  }

  Future<void> insertFieldDefinitions(
    String entityTypeId,
    List<FieldDefinition> fields,
  ) async {
    if (fields.isEmpty) return;
    try {
      final payload = <Map<String, dynamic>>[
        for (var i = 0; i < fields.length; i++)
          fields[i].toInsert(entityTypeId: entityTypeId, sortOrder: i + 1),
      ];
      await _client.from('field_definitions').insert(payload);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, code: e.code);
    }
  }

  Future<List<Entity>> getEntities(String entityTypeId) async {
    try {
      final rows = await _client
          .from('entities')
          .select()
          .eq('entity_type_id', entityTypeId)
          .order('name');
      return rows.map((r) => Entity.fromJson(r)).toList();
    } on PostgrestException catch (e) {
      throw ServerException(e.message, code: e.code);
    }
  }

  Future<String> insertEntity({
    required String orgId,
    required String entityTypeId,
    required String name,
    required Map<String, dynamic> data,
  }) async {
    try {
      final row = await _client
          .from('entities')
          .insert({
            'org_id': orgId,
            'entity_type_id': entityTypeId,
            'name': name,
            'data': data,
          })
          .select('id')
          .single();
      return row['id'] as String;
    } on PostgrestException catch (e) {
      throw ServerException(e.message, code: e.code);
    }
  }
}
