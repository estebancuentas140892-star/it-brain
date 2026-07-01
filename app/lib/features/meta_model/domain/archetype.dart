/// Arquetipos del modelo (docs/03-modelo-entidades-relaciones.md §2).
///
/// Conjunto **cerrado y versionado**: lo define IT Brain, no el cliente. El
/// cliente crea *tipos* libremente dentro de un arquetipo (Constitución, regla 7:
/// no rediseñar cuando aparece un activo nuevo). Los valores `wire` coinciden
/// exactamente con el enum `archetype` de Postgres (migración 0003).
enum Archetype {
  device('device', 'Dispositivo'),
  network('network', 'Red'),
  software('software', 'Software'),
  license('license', 'Licencia'),
  credential('credential', 'Credencial'),
  identity('identity', 'Identidad'),
  location('location', 'Ubicación'),
  party('party', 'Tercero'),
  knowledge('knowledge', 'Conocimiento'),
  caseType('case', 'Caso');

  const Archetype(this.wire, this.label);

  /// Valor tal cual se almacena/serializa en Postgres.
  final String wire;

  /// Etiqueta legible para la UI (es).
  final String label;

  static Archetype fromWire(String wire) => Archetype.values.firstWhere(
        (a) => a.wire == wire,
        orElse: () => Archetype.device,
      );
}
