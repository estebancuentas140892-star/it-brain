import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failures.dart';
import '../../../meta_model/domain/field_definition.dart';
import '../../../meta_model/presentation/providers/meta_model_providers.dart';
import '../../domain/entity.dart';

/// Ficha de una entidad: "al seleccionar uno se mostrará toda su información".
/// Los campos se leen de las `field_definitions` del tipo y se cruzan con los
/// valores en `entity.data`. Historial y adjuntos se añaden en un paso posterior.
class EntityDetailScreen extends ConsumerWidget {
  const EntityDetailScreen({super.key, required this.entity});

  final Entity entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(fieldDefinitionsProvider(entity.entityTypeId));

    return Scaffold(
      appBar: AppBar(title: Text(entity.name)),
      body: fieldsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            e is Failure ? e.message : 'No se pudieron cargar los campos.',
          ),
        ),
        data: (fields) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (entity.status != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Chip(label: Text(entity.status!)),
              ),
            if (entity.description != null) ...[
              Text(entity.description!,
                  style: Theme.of(context).textTheme.bodyMedium,),
              const SizedBox(height: 16),
            ],
            for (final f in fields) _FieldRow(field: f, value: entity.data[f.key]),
            if (fields.isEmpty)
              Text('Este tipo no tiene campos personalizados.',
                  style: Theme.of(context).textTheme.bodySmall,),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field, required this.value});

  final FieldDefinition field;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              field.label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(_format(value))),
        ],
      ),
    );
  }

  String _format(dynamic v) {
    if (v == null) return '—';
    if (v is bool) return v ? 'Sí' : 'No';
    return v.toString();
  }
}
