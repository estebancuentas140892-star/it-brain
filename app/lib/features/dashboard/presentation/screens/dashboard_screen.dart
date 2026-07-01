import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/providers/supabase_providers.dart';
import '../../../meta_model/domain/archetype.dart';
import '../../../meta_model/domain/entity_type.dart';
import '../../../meta_model/presentation/providers/meta_model_providers.dart';

/// Dashboard (Inicio).
///
/// Refleja la jerarquía de docs/08-wireframes-ux.md §1: el buscador arriba, y
/// debajo las **categorías** (tipos de entidad) para explorar el inventario —
/// además del buscador/grafo (decisión "ambas", visión ampliada 2026-07).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IT Brain'),
        actions: [
          IconButton(
            tooltip: 'Tipos de entidad',
            icon: const Icon(Icons.category_outlined),
            onPressed: () => context.pushNamed('entity-types'),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(supabaseClientProvider).auth.signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Buscador — el centro gravitacional (docs 07 §1). Se activa en el
          // siguiente paso (docs 11).
          const _SearchBarPlaceholder(),
          const SizedBox(height: 24),
          const _CategoriesSection(),
          const SizedBox(height: 8),
          _Section(
            title: 'Incidentes abiertos',
            child: _emptyHint(context, 'Sin incidentes abiertos'),
          ),
          _Section(
            title: 'Favoritos',
            child: _emptyHint(context, 'Marca entidades como favoritas'),
          ),
          _Section(
            title: 'Recientes',
            child: _emptyHint(context, 'Aquí aparecerá lo último que consultes'),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}

/// Rejilla de categorías = tipos de entidad visibles (sistema + de la org).
/// Tocar una categoría abre el listado de sus entidades.
class _CategoriesSection extends ConsumerWidget {
  const _CategoriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(entityTypesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Categorías', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        typesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              e is Failure ? e.message : 'No se pudieron cargar las categorías.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          data: (types) => types.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Aún no hay categorías. Aplica el esquema para ver los tipos.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final t in types) _CategoryCard(type: t)],
                ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.type});

  final EntityType type;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 96,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushNamed(
            'entities-by-type',
            pathParameters: {'typeId': type.id},
            extra: type.name,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_iconFor(type.archetype), size: 28),
                const SizedBox(height: 8),
                Text(
                  type.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(Archetype a) => switch (a) {
        Archetype.device => Icons.devices_other,
        Archetype.network => Icons.lan,
        Archetype.software => Icons.apps,
        Archetype.license => Icons.workspace_premium,
        Archetype.credential => Icons.lock,
        Archetype.identity => Icons.person,
        Archetype.location => Icons.place,
        Archetype.party => Icons.handshake,
        Archetype.knowledge => Icons.menu_book,
        Archetype.caseType => Icons.assignment,
      };
}

class _SearchBarPlaceholder extends StatelessWidget {
  const _SearchBarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return TextField(
      readOnly: true,
      decoration: const InputDecoration(
        hintText: 'Buscar cualquier cosa…',
        prefixIcon: Icon(Icons.search),
      ),
      onTap: () {
        // TODO: abrir el buscador (command palette en desktop, docs 08 §2).
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        child,
        const SizedBox(height: 16),
      ],
    );
  }
}
