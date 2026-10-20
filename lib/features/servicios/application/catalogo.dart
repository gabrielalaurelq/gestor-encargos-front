import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/infrastructure/providers.dart';
import '../../../shared/sync/providers.dart';
import '../data/repositorio_servicios.dart';
import '../domain/servicio.dart';

part 'catalogo.g.dart';

@Riverpod(keepAlive: true)
RepositorioServicios repositorioServicios(Ref ref) =>
    RepositorioServicios(base: ref.watch(baseDatosProvider), outbox: ref.watch(outboxProvider));

/// El catálogo completo, reactivo: se actualiza solo al escribir en local y
/// cuando el sync baja cambios de otro dispositivo (Doc 7, Bloque 3).
@riverpod
Stream<List<Servicio>> catalogo(Ref ref) => ref.watch(repositorioServiciosProvider).observar();
