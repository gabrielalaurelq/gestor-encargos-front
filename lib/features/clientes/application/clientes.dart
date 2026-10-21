import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/infrastructure/providers.dart';
import '../../../shared/sync/providers.dart';
import '../data/repositorio_clientes.dart';
import '../domain/cliente.dart';

part 'clientes.g.dart';

@Riverpod(keepAlive: true)
RepositorioClientes repositorioClientes(Ref ref) =>
    RepositorioClientes(base: ref.watch(baseDatosProvider), outbox: ref.watch(outboxProvider));

/// La lista de la pestaña Clientes para lo que se lleva escrito en la
/// búsqueda; reactiva, también ante lo que baja el sync.
@riverpod
Stream<List<Cliente>> busquedaClientes(Ref ref, String texto) =>
    ref.watch(repositorioClientesProvider).buscar(texto);
