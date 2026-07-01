import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/providers/active_org_provider.dart';
import '../../domain/entity.dart';
import '../providers/entities_providers.dart';

/// Lista de entidades de una categoría (tipo). Es el "al abrir POS, aparece el
/// listado de todos los POS" de la visión. Desde aquí se crea una nueva entidad
/// o se abre la ficha de una existente.
class EntitiesByTypeScreen extends ConsumerWidget {
  const EntitiesByTypeScreen({
    super.key,
    required this.entityTypeId,
    required this.typeName,
  });

  final String entityTypeId;
  final String typeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitiesAsync = ref.watch(entitiesByTypeProvider(entityTypeId));
    final canCreate =
        ref.watch(activeOrgProvider).valueOrNull?.canCreateEntities ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(typeName)),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await context.pushNamed<bool>(
                  'create-entity',
                  pathParameters: {'typeId': entityTypeId},
                  extra: typeName,
                );
                if (created == true) {
                  ref.invalidate(entitiesByTypeProvider(entityTypeId));
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            )
          : null,
      body: entitiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            e is Failure ? e.message : 'No se pudieron cargar las entidades.',
          ),
        ),
        data: (entities) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(entitiesByTypeProvider(entityTypeId)),
          child: entities.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(
                      child: Text('Aún no hay $typeName registrados.'),
                    ),
                  ],
                )
              : ListView.separated(
                  itemCount: entities.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _EntityTile(entity: entities[i]),
                ),
        ),
      ),
    );
  }
}

class _EntityTile extends StatelessWidget {
  const _EntityTile({required this.entity});

  final Entity entity;

  @override
  Widget build(BuildContext context) {
    final subtitle = entity.status ?? entity.description;
    return ListTile(
      title: Text(entity.name),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(
        'entity-detail',
        pathParameters: {'id': entity.id},
        extra: entity,
      ),
    );
  }
}
