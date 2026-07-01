// Verifica el supuesto CENTRAL de T-016 (UC-05): el formulario se genera desde
// las `field_definitions` en runtime y produce valores YA TIPADOS para el JSONB
// `entities.data`. No requiere Supabase: DynamicFieldInput es una pieza pura de UI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_brain/features/entities/presentation/widgets/dynamic_field_input.dart';
import 'package:it_brain/features/meta_model/domain/field_data_type.dart';
import 'package:it_brain/features/meta_model/domain/field_definition.dart';

void main() {
  testWidgets(
      'El formulario dinámico renderiza el input por tipo y produce data tipada',
      (tester) async {
    final values = <String, dynamic>{};
    const fields = [
      FieldDefinition(key: 'serial', label: 'Serial', dataType: FieldDataType.text),
      FieldDefinition(key: 'puertos', label: 'Puertos', dataType: FieldDataType.number),
      FieldDefinition(key: 'atex', label: 'ATEX', dataType: FieldDataType.boolean),
      FieldDefinition(
        key: 'prioridad',
        label: 'Prioridad',
        dataType: FieldDataType.enumeration,
        options: ['baja', 'alta'],
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            for (final f in fields)
              DynamicFieldInput(
                key: ValueKey(f.key),
                field: f,
                onChanged: (v) => values[f.key] = v,
              ),
          ],
        ),
      ),
    ),);

    // text → String
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('serial')),
        matching: find.byType(TextField),
      ),
      'ABC-123',
    );
    // number → num
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('puertos')),
        matching: find.byType(TextField),
      ),
      '8',
    );
    // bool → toggle
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('atex')),
      matching: find.byType(SwitchListTile),
    ),);
    await tester.pump();
    // enum → seleccionar 'alta'
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('prioridad')),
      matching: find.byType(DropdownButtonFormField<String>),
    ),);
    await tester.pumpAndSettle();
    await tester.tap(find.text('alta').last);
    await tester.pumpAndSettle();

    expect(values['serial'], 'ABC-123');
    expect(values['puertos'], 8);
    expect(values['atex'], true);
    expect(values['prioridad'], 'alta');
  });

  test('Los tipos sensibles/complejos no son editables como input plano', () {
    // secret jamás debe capturarse en el formulario (va cifrado a `secrets`);
    // reference/json/geo se difieren. El formulario los omite por esta bandera.
    expect(FieldDataType.secret.supportedInForm, isFalse);
    expect(FieldDataType.reference.supportedInForm, isFalse);
    expect(FieldDataType.json.supportedInForm, isFalse);
    expect(FieldDataType.geo.supportedInForm, isFalse);
    expect(FieldDataType.text.supportedInForm, isTrue);
    expect(FieldDataType.enumeration.supportedInForm, isTrue);
  });
}
