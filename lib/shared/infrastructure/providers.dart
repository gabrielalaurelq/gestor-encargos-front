import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth/almacen_tokens.dart';
import 'auth/aviso_sesion.dart';
import 'conectividad.dart';
import 'config/ambiente.dart';
import 'db/base_datos.dart';
import 'dictado.dart';
import 'enlaces.dart';
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
AvisoSesion avisoSesion(Ref ref) {
  final aviso = AvisoSesion();
  ref.onDispose(aviso.cerrar);
  return aviso;
}

@Riverpod(keepAlive: true)
Conectividad conectividad(Ref ref) => ConectividadDispositivo();

@Riverpod(keepAlive: true)
BaseDatos baseDatos(Ref ref) {
  final base = BaseDatos();
  ref.onDispose(base.close);
  return base;
}

@Riverpod(keepAlive: true)
ClienteApi clienteApi(Ref ref) {
  final aviso = ref.watch(avisoSesionProvider);
  return ClienteApi(
    ambiente: ref.watch(ambienteProvider),
    tokens: ref.watch(almacenTokensProvider),
    alExpirarSesion: aviso.sesionExpirada,
  );
}

/// Deep links fuera de la app (WhatsApp, S5c).
@Riverpod(keepAlive: true)
AbridorEnlaces abridorEnlaces(Ref ref) => const AbridorEnlacesSistema();

/// Dictado por voz nativo (S5d). Uno para toda la app: el reconocedor se
/// prepara una sola vez.
@Riverpod(keepAlive: true)
Dictado dictado(Ref ref) => DictadoNativo();
