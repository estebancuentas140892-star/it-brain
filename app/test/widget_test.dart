// Smoke test del scaffolding.
//
// Un test completo de ItBrainApp requeriría Supabase.initialize() (red o
// mocks), que se añade junto con la infraestructura de testing en una tarea
// posterior. Por ahora se verifica que la pantalla de login (que no llama a
// Supabase en build(), solo al enviar el formulario) renderiza sin errores.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_brain/features/auth/presentation/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen renderiza correo, contraseña y botón de entrar',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text('IT Brain'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Correo'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Contraseña'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
  });
}
