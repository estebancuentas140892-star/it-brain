import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/providers/active_org_provider.dart';
import '../../domain/entity_type.dart';
import '../providers/meta_model_providers.dart';

/// Configuración → Tipos de entidad (UC-05). Lista los tipos disponibles (sistema
/// + los de la org). Desde un tipo se crea una entidad (formulario dinámico); el
/// Admin puede además crear un tipo nuevo. La acción de crear tipo se oculta a
/// quien no es Admin (gate de UI; la RLS es la frontera real).
class EntityTypesScreen extends ConsumerWidget {
  const EntityTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(entityTypesProvider);
    final canManage =
        ref.watch(activeOrgProvider).valueOrNull?.canManageSchema ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Tipos de entidad')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await context.pushNamed<bool>('create-entity-type');
                if (created == true) ref.invalidate(entityTypesProvider);
              },
              icon: const Icon(Icons.add),
              label: const Text('Nuevo tipo'),
            )
          : null,
      body: typesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(e is Failure ? e.message : 'No se pudieron cargar los tipos.'),
        ),
        data: (types) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(entityTypesProvider),
          child: types.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('No hay tipos todavía.')),
                  ],
                )
              : ListView.separated(
                  itemCount: types.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _TypeTile(type: types[i]),
                ),
        ),
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.type});

  final EntityType type;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(type.name),
      subtitle: Text(type.archetype.label),
      trailing: type.isSystem
          ? const Chip(label: Text('Sistema'))
          : const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(
        'entities-by-type',
        pathParameters: {'typeId': type.id},
        extra: type.name,
      ),
    );
  }
}
