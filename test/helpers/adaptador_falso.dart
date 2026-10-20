import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Respuesta simulada del backend.
class Respuesta {
  const Respuesta(this.status, [this.cuerpo, this.headers = const {}]);

  /// Error con el formato uniforme del Doc 5, Bloque 3.
  factory Respuesta.error(int status, String codigo, {Map<String, Object?>? detalles}) =>
      Respuesta(status, {
        'error': {'codigo': codigo, 'mensaje': 'Mensaje de $codigo', 'detalles': ?detalles},
      });

  final int status;
  final Object? cuerpo;
  final Map<String, List<String>> headers;
}

/// Lo que se le pidió al backend falso, para afirmar sobre ello.
class PeticionRegistrada {
  PeticionRegistrada(this.metodo, this.ruta, this.headers, this.cuerpo, this.query);

  final String metodo;
  final String ruta;
  final Map<String, dynamic> query;
  final Map<String, dynamic> headers;
  final Object? cuerpo;

  String? get autorizacion => headers['Authorization'] as String?;
}

typedef Manejador = Respuesta Function(PeticionRegistrada peticion);

/// `HttpClientAdapter` de Dio que no toca la red: cada petición la resuelve un
/// [Manejador] registrado por "MÉTODO /ruta". Sin manejador, falla el test.
class AdaptadorFalso implements HttpClientAdapter {
  final _manejadores = <String, Manejador>{};
  final peticiones = <PeticionRegistrada>[];

  /// Si es true, toda petición falla como si no hubiera red.
  bool sinRed = false;

  void cuando(String metodoYRuta, Manejador manejador) => _manejadores[metodoYRuta] = manejador;

  int contar(String metodoYRuta) =>
      peticiones.where((p) => '${p.metodo} ${p.ruta}' == metodoYRuta).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions opciones,
    Stream<Uint8List>? cuerpoStream,
    Future<void>? cancelacion,
  ) async {
    if (sinRed) {
      throw DioException.connectionError(requestOptions: opciones, reason: 'sin red (simulado)');
    }

    final peticion = PeticionRegistrada(
      opciones.method,
      opciones.path,
      Map.of(opciones.headers),
      opciones.data,
      Map.of(opciones.queryParameters),
    );
    peticiones.add(peticion);

    final clave = '${opciones.method} ${opciones.path}';
    final manejador = _manejadores[clave];
    if (manejador == null) {
      throw StateError('El backend falso no sabe responder a $clave');
    }
    final r = manejador(peticion);
    return ResponseBody.fromString(
      r.cuerpo == null ? '' : jsonEncode(r.cuerpo),
      r.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...r.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
