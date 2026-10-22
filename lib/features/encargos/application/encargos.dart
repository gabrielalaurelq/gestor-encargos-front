import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/infrastructure/providers.dart';
import '../../../shared/sync/providers.dart';
import '../data/repositorio_encargos.dart';
import '../domain/encargo.dart';

part 'encargos.g.dart';

@Riverpod(keepAlive: true)
RepositorioEncargos repositorioEncargos(Ref ref) => RepositorioEncargos(
  base: ref.watch(baseDatosProvider),
  outbox: ref.watch(outboxProvider),
  numeracion: ref.watch(numeracionProvider),
);

/// Un encargo para su detalle; `null` si no está en el teléfono.
@riverpod
Stream<Encargo?> encargo(Ref ref, String id) => ref.watch(repositorioEncargosProvider).observar(id);
