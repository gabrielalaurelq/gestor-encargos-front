import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/infrastructure/providers.dart';
import '../../../shared/sync/providers.dart';
import '../data/cambios_no_guardados.dart';

part 'cambios.g.dart';

@riverpod
Stream<List<CambioNoGuardado>> cambiosNoGuardados(Ref ref) => CambiosNoGuardados(
  base: ref.watch(baseDatosProvider),
  outbox: ref.watch(outboxProvider),
).observar();
