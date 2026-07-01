import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../meta_model/presentation/providers/meta_model_providers.dart';
import '../../domain/entity.dart';

/// Entidades de un tipo dado (la lista que se ve al abrir una categoría).
/// Se invalida tras crear una entidad para refrescar la lista.
final entitiesByTypeProvider =
    FutureProvider.family<List<Entity>, String>((ref, entityTypeId) {
  return ref.watch(metaModelRepositoryProvider).getEntities(entityTypeId);
});
