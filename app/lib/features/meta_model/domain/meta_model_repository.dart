import '../../entities/domain/entity.dart';
import 'archetype.dart';
import 'entity_type.dart';
import 'field_definition.dart';

/// Contrato de la capa de dominio para el meta-modelo (UC-05) y la creación de
/// entidades dirigida por datos. La presentación depende solo de esta interfaz;
/// la implementación (Supabase) vive en `data/`.
abstract interface class MetaModelRepository {
  /// Tipos visibles para el usuario: los de sistema (org_id null) + los de su org.
  Future<List<EntityType>> getEntityTypes();

  /// Definiciones de campo de un tipo, ordenadas por `sort_order`. Son la fuente
  /// del formulario dinámico.
  Future<List<FieldDefinition>> getFieldDefinitions(String entityTypeId);

  /// Entidades de un tipo (el listado al abrir una categoría). RLS lo acota a la org.
  Future<List<Entity>> getEntities(String entityTypeId);

  /// Crea un tipo custom + sus campos (UC-05). Devuelve el tipo creado.
  ///
  /// Nota: son dos escrituras (PostgREST no da transacción cliente); si el
  /// segundo paso fallara, el tipo quedaría sin campos. Atomizar esto es trabajo
  /// de una RPC `security definer` futura (que además sumaría su test de
  /// aislamiento al gate T-015).
  Future<EntityType> createEntityTypeWithFields({
    required String orgId,
    required String key,
    required String name,
    required Archetype archetype,
    required List<FieldDefinition> fields,
    String? icon,
    String? color,
  });

  /// Crea una entidad del tipo dado con los valores del formulario dinámico en
  /// `data` (JSONB). Devuelve el id de la entidad creada.
  Future<String> createEntity({
    required String orgId,
    required String entityTypeId,
    required String name,
    required Map<String, dynamic> data,
  });
}
