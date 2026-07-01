/// Tipos de dato de un campo personalizado (docs/03 §4; enum `field_data_type`
/// de la migración 0003). `wire` coincide con Postgres.
///
/// `supportedInForm` marca los tipos que el formulario dinámico ya sabe renderizar
/// en este MVP. Los no soportados se difieren **a propósito** (no gold-plating):
///  - `reference` es el puente al grafo: al rellenarse crea una fila en
///    `relationships` (UC-05 paso 5) — cross-cutting que se aborda junto con la
///    feature de relaciones/vecindario (UC-02).
///  - `secret` NUNCA es un input plano: su valor vive cifrado en la tabla
///    `secrets` (docs 03 §7 / 10 §2), jamás en `entities.data`.
///  - `json`/`geo` requieren editores especializados.
enum FieldDataType {
  text('text', 'Texto', supportedInForm: true),
  number('number', 'Número', supportedInForm: true),
  boolean('bool', 'Sí / No', supportedInForm: true),
  date('date', 'Fecha', supportedInForm: true),
  datetime('datetime', 'Fecha y hora', supportedInForm: true),
  enumeration('enum', 'Lista de opciones', supportedInForm: true),
  ip('ip', 'Dirección IP', supportedInForm: true),
  mac('mac', 'Dirección MAC', supportedInForm: true),
  url('url', 'URL', supportedInForm: true),
  email('email', 'Email', supportedInForm: true),
  reference('reference', 'Referencia a otra entidad', supportedInForm: false),
  secret('secret', 'Secreto (cifrado)', supportedInForm: false),
  json('json', 'JSON', supportedInForm: false),
  geo('geo', 'Geolocalización', supportedInForm: false);

  const FieldDataType(this.wire, this.label, {required this.supportedInForm});

  final String wire;
  final String label;

  /// Si el formulario dinámico ya renderiza un input para este tipo.
  final bool supportedInForm;

  /// Tipos que el Admin puede elegir al definir un campo en este MVP.
  static List<FieldDataType> get selectableInForm =>
      FieldDataType.values.where((t) => t.supportedInForm).toList();

  static FieldDataType fromWire(String wire) => FieldDataType.values.firstWhere(
        (t) => t.wire == wire,
        orElse: () => FieldDataType.text,
      );
}
