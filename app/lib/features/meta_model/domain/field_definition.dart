import 'field_data_type.dart';

/// Definición de un campo personalizado de un tipo (fila de `field_definitions`,
/// docs 03 §4). Es lo que permite el **formulario dinámico**: la UI de creación
/// de una entidad se construye leyendo estas filas, sin desplegar código (UC-05).
class FieldDefinition {
  const FieldDefinition({
    required this.key,
    required this.label,
    required this.dataType,
    this.id,
    this.entityTypeId,
    this.helpText,
    this.isRequired = false,
    this.isUnique = false,
    this.isSearchable = false,
    this.sensitivity = 'normal',
    this.minRoleRead = 'consulta',
    this.minRoleWrite = 'tecnico',
    this.options,
    this.referenceType,
    this.fieldGroup,
    this.sortOrder = 0,
  });

  /// `null` mientras el campo aún no se ha persistido (se está definiendo en la UI).
  final String? id;
  final String? entityTypeId;
  final String key;
  final String label;
  final String? helpText;
  final FieldDataType dataType;
  final bool isRequired;
  final bool isUnique;
  final bool isSearchable;

  /// 'normal' | 'sensitive' | 'secret' (enum `field_sensitivity`, migración 0003).
  final String sensitivity;
  final String minRoleRead;
  final String minRoleWrite;

  /// Opciones para `data_type = enum`.
  final List<String>? options;

  /// Tipo destino si `data_type = reference` (id de otro `entity_type`).
  final String? referenceType;
  final String? fieldGroup;
  final int sortOrder;

  factory FieldDefinition.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    return FieldDefinition(
      id: json['id'] as String?,
      entityTypeId: json['entity_type_id'] as String?,
      key: json['key'] as String,
      label: json['label'] as String,
      helpText: json['help_text'] as String?,
      dataType: FieldDataType.fromWire(json['data_type'] as String),
      isRequired: json['is_required'] as bool? ?? false,
      isUnique: json['is_unique'] as bool? ?? false,
      isSearchable: json['is_searchable'] as bool? ?? false,
      sensitivity: json['sensitivity'] as String? ?? 'normal',
      minRoleRead: json['min_role_read'] as String? ?? 'consulta',
      minRoleWrite: json['min_role_write'] as String? ?? 'tecnico',
      options: rawOptions is List
          ? rawOptions.map((e) => e.toString()).toList()
          : null,
      referenceType: json['reference_type'] as String?,
      fieldGroup: json['field_group'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  /// Payload de inserción para `field_definitions`. `entityTypeId`/`sortOrder`
  /// se inyectan al persistir (el tipo aún no existía cuando se definió el campo).
  Map<String, dynamic> toInsert({
    required String entityTypeId,
    required int sortOrder,
  }) =>
      {
        'entity_type_id': entityTypeId,
        'key': key,
        'label': label,
        'data_type': dataType.wire,
        'is_required': isRequired,
        'is_unique': isUnique,
        'is_searchable': isSearchable,
        'sensitivity': sensitivity,
        'min_role_read': minRoleRead,
        'min_role_write': minRoleWrite,
        if (options != null) 'options': options,
        if (referenceType != null) 'reference_type': referenceType,
        if (helpText != null) 'help_text': helpText,
        'sort_order': sortOrder,
      };

  FieldDefinition copyWith({
    String? key,
    String? label,
    FieldDataType? dataType,
    bool? isRequired,
    bool? isSearchable,
    List<String>? options,
  }) =>
      FieldDefinition(
        key: key ?? this.key,
        label: label ?? this.label,
        dataType: dataType ?? this.dataType,
        id: id,
        entityTypeId: entityTypeId,
        helpText: helpText,
        isRequired: isRequired ?? this.isRequired,
        isUnique: isUnique,
        isSearchable: isSearchable ?? this.isSearchable,
        sensitivity: sensitivity,
        minRoleRead: minRoleRead,
        minRoleWrite: minRoleWrite,
        options: options ?? this.options,
        referenceType: referenceType,
        fieldGroup: fieldGroup,
        sortOrder: sortOrder,
      );
}
