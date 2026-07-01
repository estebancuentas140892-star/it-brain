/// Una entidad concreta (fila de `entities`, docs 03 §3). Es una instancia de un
/// `entity_type`: sus campos personalizados viven en `data` (JSONB), validados
/// contra las `field_definitions` del tipo.
class Entity {
  const Entity({
    required this.id,
    required this.entityTypeId,
    required this.name,
    this.description,
    this.status,
    this.data = const {},
    this.updatedAt,
  });

  final String id;
  final String entityTypeId;
  final String name;
  final String? description;
  final String? status;
  final Map<String, dynamic> data;
  final DateTime? updatedAt;

  factory Entity.fromJson(Map<String, dynamic> json) => Entity(
        id: json['id'] as String,
        entityTypeId: json['entity_type_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        status: json['status'] as String?,
        data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'] as String)
            : null,
      );
}
