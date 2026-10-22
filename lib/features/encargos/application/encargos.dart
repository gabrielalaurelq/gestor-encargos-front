import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/infrastructure/providers.dart';
import '../../../shared/sync/providers.dart';
import '../data/repositorio_encargos.dart';

part 'encargos.g.dart';

@Riverpod(keepAlive: true)
RepositorioEncargos repositorioEncargos(Ref ref) => RepositorioEncargos(
  base: ref.watch(baseDatosProvider),
  outbox: ref.watch(outboxProvider),
  numeracion: ref.watch(numeracionProvider),
);
