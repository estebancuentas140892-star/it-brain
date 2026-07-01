import 'package:flutter/material.dart';

/// Tema de IT Brain.
///
/// Estética definida en docs/08-wireframes-ux.md §0: minimalista, plano, mucho
/// espacio en blanco, tipografía como jerarquía, color con significado (no
/// decorativo). Inspiración: Linear, Notion, Apple, Raycast, Obsidian.
///
/// Los tokens exactos (paleta final, escala tipográfica) se refinan al construir
/// las pantallas; esta es la base coherente Material 3.
class AppTheme {
  const AppTheme._();

  // Acento principal (sobrio). Color con significado se reserva para estados.
  static const Color _seed = Color(0xFF3B6EF6);

  // Colores de estado (docs 08 §0: color = significado).
  static const Color statusActive = Color(0xFF16A34A);
  static const Color statusCritical = Color(0xFFDC2626);
  static const Color statusArchived = Color(0xFF9CA3AF);

  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
