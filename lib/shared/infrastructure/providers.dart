import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth/almacen_tokens.dart';
import 'config/ambiente.dart';
import 'db/base_datos.dart';
import 'http/cliente_api.dart';

part 'providers.g.dart';

// Grafo de dependencias de la infraestructura compartida (Doc 7, Bloque 2:
// Riverpod es la inyección de dependencias). Los tests sobreescriben las
// hojas —ambiente, tokens, base— con `ProviderScope(overrides: ...)`.

@Riverpod(keepAlive: true)
Ambiente ambiente(Ref ref) => Ambiente.desdeCompilacion();

@Riverpod(keepAlive: true)
AlmacenTokens almacenTokens(Ref ref) => AlmacenTokensSeguro();

@Riverpod(keepAlive: true)
BaseDatos baseDatos(Ref ref) {
  final base = BaseDatos();
  ref.onDispose(base.close);
  return base;
}

@Riverpod(keepAlive: true)
ClienteApi clienteApi(Ref ref) => ClienteApi(
  ambiente: ref.watch(ambienteProvider),
  tokens: ref.watch(almacenTokensProvider),
  // La reacción a la sesión expirada (volver a /login) la conecta F2.
);
