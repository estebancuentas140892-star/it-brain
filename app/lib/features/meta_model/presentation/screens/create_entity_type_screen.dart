import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/providers/active_org_provider.dart';
import '../../domain/archetype.dart';
import '../../domain/field_data_type.dart';
import '../../domain/field_definition.dart';
import '../providers/meta_model_providers.dart';

/// Crea un tipo de entidad custom y sus campos (UC-05, pasos 2–3). El resultado
/// es utilizable de inmediato: al volver, la lista se refresca y ya se pueden
/// crear entidades del tipo con formulario dinámico, sin desplegar código.
class CreateEntityTypeScreen extends ConsumerStatefulWidget {
  const CreateEntityTypeScreen({super.key});

  @override
  ConsumerState<CreateEntityTypeScreen> createState() =>
      _CreateEntityTypeScreenState();
}

class _CreateEntityTypeScreenState
    extends ConsumerState<CreateEntityTypeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _key = TextEditingController();
  Archetype _archetype = Archetype.device;
  final List<_FieldDraft> _fields = [];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  void _addField() => setState(() => _fields.add(_FieldDraft()));

  void _removeField(_FieldDraft f) {
    setState(() => _fields.remove(f));
    f.dispose();
  }

  /// Deriva una `key` a partir del texto (minúsculas, sin espacios) si el Admin
  /// no la escribió — reduce fricción sin ocultar el concepto.
  String _slug(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Validación de campos (fuera del Form: la lista es dinámica).
    for (final f in _fields) {
      if (f.label.text.trim().isEmpty) {
        setState(() => _error = 'Cada campo necesita una etiqueta.');
        return;
      }
      if (f.dataType == FieldDataType.enumeration && f.optionList.isEmpty) {
        setState(() => _error =
            'El campo "${f.label.text.trim()}" es una lista: añade opciones separadas por comas.',);
        return;
      }
    }

    final org = ref.read(activeOrgProvider).valueOrNull;
    if (org == null) {
      setState(() => _error = 'No hay organización activa.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final typeKey =
          _key.text.trim().isNotEmpty ? _slug(_key.text) : _slug(_name.text);
      final fields = <FieldDefinition>[
        for (final f in _fields)
          FieldDefinition(
            key: f.key.text.trim().isNotEmpty
                ? _slug(f.key.text)
                : _slug(f.label.text),
            label: f.label.text.trim(),
            dataType: f.dataType,
            isRequired: f.isRequired,
            isSearchable: f.isSearchable,
            options: f.dataType == FieldDataType.enumeration ? f.optionList : null,
          ),
      ];

      await ref.read(metaModelRepositoryProvider).createEntityTypeWithFields(
            orgId: org.orgId,
            key: typeKey,
            name: _name.text.trim(),
            archetype: _archetype,
            fields: fields,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tipo creado')),
      );
      Navigator.of(context).pop(true);
    } on Failure catch (f) {
      setState(() => _error = f.message);
    } catch (_) {
      setState(() => _error = 'No se pudo crear el tipo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo tipo de entidad')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                helperText: 'Ej. "Balanza de caja", "Cámara térmica"',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'El nombre es obligatorio' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _key,
              decoration: const InputDecoration(
                labelText: 'Clave (key)',
                helperText: 'Opcional: se deriva del nombre si se deja vacía',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<Archetype>(
              initialValue: _archetype,
              decoration: const InputDecoration(labelText: 'Arquetipo'),
              items: [
                for (final a in Archetype.values)
                  DropdownMenuItem(value: a, child: Text(a.label)),
              ],
              onChanged: (a) => setState(() => _archetype = a ?? _archetype),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Campos', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: _addField,
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir campo'),
                ),
              ],
            ),
            if (_fields.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Un tipo puede no tener campos personalizados.'),
              ),
            for (final f in _fields)
              _FieldEditor(
                key: ObjectKey(f),
                draft: f,
                onChanged: () => setState(() {}),
                onRemove: () => _removeField(f),
              ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Crear tipo'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado mutable de un campo en definición (posee sus controllers).
class _FieldDraft {
  final label = TextEditingController();
  final key = TextEditingController();
  final options = TextEditingController();
  FieldDataType dataType = FieldDataType.text;
  bool isRequired = false;
  bool isSearchable = false;

  List<String> get optionList => options.text
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  void dispose() {
    label.dispose();
    key.dispose();
    options.dispose();
  }
}

class _FieldEditor extends StatelessWidget {
  const _FieldEditor({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });

  final _FieldDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: draft.label,
                    decoration: const InputDecoration(labelText: 'Etiqueta *'),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar campo',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRemove,
                ),
              ],
            ),
            TextFormField(
              controller: draft.key,
              decoration: const InputDecoration(
                labelText: 'Clave',
                helperText: 'Opcional: se deriva de la etiqueta',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<FieldDataType>(
              initialValue: draft.dataType,
              decoration: const InputDecoration(labelText: 'Tipo de dato'),
              items: [
                for (final t in FieldDataType.selectableInForm)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) {
                draft.dataType = t ?? draft.dataType;
                onChanged();
              },
            ),
            if (draft.dataType == FieldDataType.enumeration)
              TextFormField(
                controller: draft.options,
                decoration: const InputDecoration(
                  labelText: 'Opciones',
                  helperText: 'Separadas por comas: baja, media, alta',
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Obligatorio'),
                    value: draft.isRequired,
                    onChanged: (v) {
                      draft.isRequired = v;
                      onChanged();
                    },
                  ),
                ),
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Buscable'),
                    value: draft.isSearchable,
                    onChanged: (v) {
                      draft.isSearchable = v;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
