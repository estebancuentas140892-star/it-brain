import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/providers/active_org_provider.dart';
import '../../../meta_model/domain/field_definition.dart';
import '../../../meta_model/presentation/providers/meta_model_providers.dart';
import '../widgets/dynamic_field_input.dart';

/// Crea una entidad de un tipo dado con un formulario **generado dinámicamente**
/// desde `field_definitions` (UC-05, paso 4). Es la validación del supuesto
/// central: la app no conoce los campos en compilación, los descubre en runtime.
class CreateEntityScreen extends ConsumerStatefulWidget {
  const CreateEntityScreen({
    super.key,
    required this.entityTypeId,
    required this.typeName,
  });

  final String entityTypeId;
  final String typeName;

  @override
  ConsumerState<CreateEntityScreen> createState() => _CreateEntityScreenState();
}

class _CreateEntityScreenState extends ConsumerState<CreateEntityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final Map<String, dynamic> _values = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
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
      // Solo se envían los valores rellenados (JSONB disperso).
      final data = <String, dynamic>{
        for (final e in _values.entries)
          if (e.value != null) e.key: e.value,
      };
      await ref.read(metaModelRepositoryProvider).createEntity(
            orgId: org.orgId,
            entityTypeId: widget.entityTypeId,
            name: _name.text.trim(),
            data: data,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.typeName} creado')),
      );
      Navigator.of(context).pop(true);
    } on Failure catch (f) {
      setState(() => _error = f.message);
    } catch (_) {
      setState(() => _error = 'No se pudo crear la entidad.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldsAsync = ref.watch(fieldDefinitionsProvider(widget.entityTypeId));

    return Scaffold(
      appBar: AppBar(title: Text('Nuevo: ${widget.typeName}')),
      body: fieldsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          message: e is Failure ? e.message : 'No se pudieron cargar los campos.',
          onRetry: () =>
              ref.invalidate(fieldDefinitionsProvider(widget.entityTypeId)),
        ),
        data: (fields) => _buildForm(context, fields),
      ),
    );
  }

  Widget _buildForm(BuildContext context, List<FieldDefinition> fields) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // `name` es una columna base de toda entidad (docs 03 §3), no un campo
          // del meta-modelo: siempre presente y obligatorio.
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre *'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'El nombre es obligatorio' : null,
          ),
          const SizedBox(height: 8),
          const Divider(),
          for (final f in fields)
            if (f.dataType.supportedInForm)
              DynamicFieldInput(
                key: ValueKey(f.key),
                field: f,
                onChanged: (v) => _values[f.key] = v,
              )
            else
              _UnsupportedField(field: f),
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
                : const Text('Crear'),
          ),
        ],
      ),
    );
  }
}

/// Campo de un tipo aún no soportado por el formulario (reference/secret/json/geo).
/// Se muestra deshabilitado y explicado, nunca como un input plano (crítico para
/// `secret`: su valor jamás debe capturarse aquí — va cifrado a `secrets`).
class _UnsupportedField extends StatelessWidget {
  const _UnsupportedField({required this.field});

  final FieldDefinition field;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: field.label,
          helperText: 'Tipo "${field.dataType.label}" — aún no editable aquí',
          enabled: false,
        ),
        child: const Text('—'),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
