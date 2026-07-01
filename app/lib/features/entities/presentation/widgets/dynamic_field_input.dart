import 'package:flutter/material.dart';

import '../../../meta_model/domain/field_data_type.dart';
import '../../../meta_model/domain/field_definition.dart';

/// Renderiza el input adecuado para una `FieldDefinition` y reporta el valor
/// **ya tipado** (para `entities.data` JSONB) vía [onChanged]:
///  - text/ip/mac/url/email → `String?`
///  - number               → `num?`
///  - bool                 → `bool`
///  - date                 → `String?`  ('yyyy-MM-dd')
///  - datetime             → `String?`  (ISO-8601)
///  - enum                 → `String?`  (opción elegida)
///
/// Es la pieza que hace real el "formulario dirigido por datos" (UC-05): la app
/// no conoce los campos en tiempo de compilación, los descubre en runtime.
class DynamicFieldInput extends StatefulWidget {
  const DynamicFieldInput({
    super.key,
    required this.field,
    required this.onChanged,
  });

  final FieldDefinition field;
  final ValueChanged<dynamic> onChanged;

  @override
  State<DynamicFieldInput> createState() => _DynamicFieldInputState();
}

class _DynamicFieldInputState extends State<DynamicFieldInput> {
  TextEditingController? _text;
  bool _bool = false;
  String? _enumValue;
  DateTime? _dateValue;

  FieldDefinition get _f => widget.field;

  @override
  void initState() {
    super.initState();
    final type = _f.dataType;
    final needsTextController = type == FieldDataType.text ||
        type == FieldDataType.number ||
        type == FieldDataType.ip ||
        type == FieldDataType.mac ||
        type == FieldDataType.url ||
        type == FieldDataType.email;
    if (needsTextController) _text = TextEditingController();
  }

  @override
  void dispose() {
    _text?.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? v) {
    if (_f.isRequired && (v == null || v.trim().isEmpty)) {
      return 'Campo obligatorio';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    switch (_f.dataType) {
      case FieldDataType.boolean:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_label()),
          subtitle: _f.helpText != null ? Text(_f.helpText!) : null,
          value: _bool,
          onChanged: (v) {
            setState(() => _bool = v);
            widget.onChanged(v);
          },
        );

      case FieldDataType.enumeration:
        final options = _f.options ?? const <String>[];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: DropdownButtonFormField<String>(
            initialValue: _enumValue,
            isExpanded: true,
            decoration: _decoration(),
            items: [
              for (final o in options)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            validator: (v) => _requiredValidator(v),
            onChanged: (v) {
              setState(() => _enumValue = v);
              widget.onChanged(v);
            },
          ),
        );

      case FieldDataType.date:
      case FieldDataType.datetime:
        return _DatePickerField(
          label: _label(),
          helpText: _f.helpText,
          withTime: _f.dataType == FieldDataType.datetime,
          isRequired: _f.isRequired,
          value: _dateValue,
          onPicked: (dt) {
            setState(() => _dateValue = dt);
            widget.onChanged(dt == null ? null : _serializeDate(dt));
          },
        );

      // text / number / ip / mac / url / email → campo de texto tipado.
      default:
        final isNumber = _f.dataType == FieldDataType.number;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextFormField(
            controller: _text,
            decoration: _decoration(),
            keyboardType: _keyboardType(),
            validator: (raw) {
              final req = _requiredValidator(raw);
              if (req != null) return req;
              if (isNumber &&
                  raw != null &&
                  raw.trim().isNotEmpty &&
                  num.tryParse(raw.trim()) == null) {
                return 'Debe ser un número';
              }
              return null;
            },
            onChanged: (raw) {
              final trimmed = raw.trim();
              if (isNumber) {
                widget.onChanged(trimmed.isEmpty ? null : num.tryParse(trimmed));
              } else {
                widget.onChanged(trimmed.isEmpty ? null : trimmed);
              }
            },
          ),
        );
    }
  }

  String _label() => _f.isRequired ? '${_f.label} *' : _f.label;

  InputDecoration _decoration() => InputDecoration(
        labelText: _label(),
        helperText: _f.helpText,
      );

  TextInputType? _keyboardType() => switch (_f.dataType) {
        FieldDataType.number => const TextInputType.numberWithOptions(decimal: true),
        FieldDataType.email => TextInputType.emailAddress,
        FieldDataType.url => TextInputType.url,
        _ => null,
      };

  /// 'yyyy-MM-dd' para date; ISO-8601 completo para datetime.
  String _serializeDate(DateTime dt) => _f.dataType == FieldDataType.date
      ? '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}'
      : dt.toIso8601String();
}

/// Selector de fecha (y opcionalmente hora) con presentación de campo de formulario.
class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.helpText,
    required this.withTime,
    required this.isRequired,
    required this.value,
    required this.onPicked,
  });

  final String label;
  final String? helpText;
  final bool withTime;
  final bool isRequired;
  final DateTime? value;
  final ValueChanged<DateTime?> onPicked;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Sin definir'
        : withTime
            ? value!.toLocal().toString()
            : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, helperText: helpText),
        child: Row(
          children: [
            Expanded(child: Text(text)),
            TextButton(
              onPressed: () => _pick(context),
              child: const Text('Elegir'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null) return;
    if (!withTime) {
      onPicked(date);
      return;
    }
    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value ?? now),
    );
    onPicked(DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    ),);
  }
}
