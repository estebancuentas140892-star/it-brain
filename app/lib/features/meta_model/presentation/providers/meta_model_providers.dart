import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/supabase_providers.dart';
import '../../data/meta_model_remote_data_source.dart';
import '../../data/meta_model_repository_impl.dart';
import '../../domain/entity_type.dart';
import '../../domain/field_definition.dart';
import '../../domain/meta_model_repository.dart';

/// Cableado de dependencias del meta-modelo (Clean Architecture): cliente →
/// datasource → repositorio. La presentación solo conoce `MetaModelRepository`.
final metaModelRepositoryProvider = Provider<MetaModelRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MetaModelRepositoryImpl(MetaModelRemoteDataSource(client));
});

/// Lista de tipos de entidad visibles (sistema + los de la org). Se invalida tras
/// crear un tipo nuevo para refrescar la lista.
final entityTypesProvider = FutureProvider<List<EntityType>>((ref) {
  return ref.watch(metaModelRepositoryProvider).getEntityTypes();
});

/// Definiciones de campo de un tipo — la fuente del formulario dinámico.
final fieldDefinitionsProvider =
    FutureProvider.family<List<FieldDefinition>, String>((ref, entityTypeId) {
  return ref
      .watch(metaModelRepositoryProvider)
      .getFieldDefinitions(entityTypeId);
});
