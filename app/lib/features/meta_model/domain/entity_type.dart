import 'archetype.dart';

/// Un tipo de entidad (fila de `entity_types`, docs 03 §4).
///
/// Los tipos de **sistema** tienen `orgId == null` y `isSystem == true`: visibles
/// para toda organización pero no editables por el cliente (migración 0010). Un
/// Admin solo puede crear tipos **propios** de su organización (UC-05); la RLS
/// `types_write` (rank ≥ 4, org propia) lo hace cumplir en el servidor.
class EntityType {
  const EntityType({
    required this.id,
    required this.orgId,
    required this.key,
    required this.name,
    required this.archetype,
    required this.isSystem,
    this.icon,
    this.color,
  });

  final String id;

  /// `null` para los tipos de sistema.
  final String? orgId;
  final String key;
  final String name;
  final Archetype archetype;
  final bool isSystem;
  final String? icon;
  final String? color;

  /// `true` si es un tipo custom de la propia organización (editable por Admin).
  bool get isCustom => !isSystem && orgId != null;

  factory EntityType.fromJson(Map<String, dynamic> json) => EntityType(
        id: json['id'] as String,
        orgId: json['org_id'] as String?,
        key: json['key'] as String,
        name: json['name'] as String,
        archetype: Archetype.fromWire(json['archetype'] as String),
        isSystem: json['is_system'] as bool? ?? false,
        icon: json['icon'] as String?,
        color: json['color'] as String?,
      );
}
