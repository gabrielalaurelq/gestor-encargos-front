import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/infrastructure/providers.dart';
import '../../../shared/sync/providers.dart';
import '../data/repositorio_clientes.dart';
import '../domain/cliente.dart';
import '../domain/historial_cliente.dart';

part 'clientes.g.dart';

@Riverpod(keepAlive: true)
RepositorioClientes repositorioClientes(Ref ref) =>
    RepositorioClientes(base: ref.watch(baseDatosProvider), outbox: ref.watch(outboxProvider));

/// La lista de la pestaña Clientes para lo que se lleva escrito en la
/// búsqueda; reactiva, también ante lo que baja el sync.
@riverpod
Stream<List<Cliente>> busquedaClientes(Ref ref, String texto) =>
    ref.watch(repositorioClientesProvider).buscar(texto);

/// Un cliente para su ficha; `null` si no está en el teléfono.
@riverpod
Stream<Cliente?> cliente(Ref ref, String id) => ref.watch(repositorioClientesProvider).observar(id);

/// Los encargos de la ficha, con lo pagado de cada uno.
@riverpod
Stream<List<EncargoDeCliente>> encargosDeCliente(Ref ref, String clienteId) =>
    ref.watch(repositorioClientesProvider).encargosDe(clienteId);
