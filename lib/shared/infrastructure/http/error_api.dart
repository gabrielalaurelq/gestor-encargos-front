import 'package:dio/dio.dart';

/// Todo error de la API, traducido del formato uniforme del Doc 5 (Bloque 3):
/// `{"error": {"codigo", "mensaje", "detalles"}}`.
///
/// Es una jerarquía cerrada porque quien la consume —sobre todo la cola
/// Outbox del motor de sync— necesita decidir **qué hacer** con cada caso, no
/// solo mostrar un texto:
/// - [esTransitorio]: reintentar más tarde (sin red, 5xx, 429).
/// - [esPermanente]: reintentar no cambiará nada; la operación se aparta
///   (decisión del usuario para la Outbox, Sprint 0).
/// - [NoAutenticado]: la sesión terminó; ni reintentar ni apartar.
sealed class ErrorApi implements Exception {
  const ErrorApi({required this.codigo, required this.mensaje, this.detalles, this.status});

  final String codigo;
  final String mensaje;
  final Map<String, dynamic>? detalles;

  /// `null` cuando la petición ni siquiera llegó al servidor.
  final int? status;

  bool get esTransitorio => false;
  bool get esPermanente => false;

  /// Traduce lo que sea que haya lanzado Dio.
  factory ErrorApi.desde(DioException e) {
    final respuesta = e.response;
    if (respuesta == null) {
      return const SinConexion();
    }

    final status = respuesta.statusCode ?? 0;
    final cuerpo = _leerCuerpo(respuesta.data);
    final codigo = cuerpo?['codigo'] as String? ?? 'HTTP_$status';
    final mensaje = cuerpo?['mensaje'] as String? ?? 'El servidor respondió $status.';
    final detalles = cuerpo?['detalles'] as Map<String, dynamic>?;

    return switch (status) {
      401 => NoAutenticado(codigo: codigo, mensaje: mensaje),
      410 => SyncDemasiadoAntiguo(mensaje: mensaje, detalles: detalles),
      429 => LimiteExcedido(
        mensaje: mensaje,
        reintentarEn: _segundos(respuesta.headers.value('retry-after')),
      ),
      >= 500 => ErrorServidor(codigo: codigo, mensaje: mensaje, status: status),
      _ => ErrorRechazado(codigo: codigo, mensaje: mensaje, detalles: detalles, status: status),
    };
  }

  static Map<String, dynamic>? _leerCuerpo(Object? data) {
    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      return data['error'] as Map<String, dynamic>;
    }
    return null;
  }

  static Duration? _segundos(String? valor) {
    final n = int.tryParse(valor ?? '');
    return n == null ? null : Duration(seconds: n);
  }

  @override
  String toString() => '$runtimeType($codigo, status: $status): $mensaje';
}

/// La petición no llegó al servidor, o no volvió la respuesta. En una app
/// offline-first es el caso **normal**, no una excepción rara (Doc 6:
/// "offline invisible").
final class SinConexion extends ErrorApi {
  const SinConexion() : super(codigo: 'SIN_CONEXION', mensaje: 'No hay conexión con el servidor.');

  @override
  bool get esTransitorio => true;
}

/// 401 que no se pudo resolver renovando el access token: la sesión se cerró
/// o el refresh token venció. Hay que volver a iniciar sesión.
final class NoAutenticado extends ErrorApi {
  const NoAutenticado({required super.codigo, required super.mensaje}) : super(status: 401);
}

/// `410 SYNC_DEMASIADO_ANTIGUO` (Doc 5 v1.5): el dispositivo quedó atrás de
/// la purga de tombstones y debe resincronizar de cero.
final class SyncDemasiadoAntiguo extends ErrorApi {
  const SyncDemasiadoAntiguo({required super.mensaje, super.detalles})
    : super(codigo: 'SYNC_DEMASIADO_ANTIGUO', status: 410);
}

/// 429: el backend pide esperar (Doc 5, Bloque 4).
final class LimiteExcedido extends ErrorApi {
  const LimiteExcedido({required super.mensaje, this.reintentarEn})
    : super(codigo: 'LIMITE_EXCEDIDO', status: 429);

  /// Del header `Retry-After`, si vino.
  final Duration? reintentarEn;

  @override
  bool get esTransitorio => true;
}

/// 5xx: falla del servidor, no de la petición. Reintentar puede funcionar.
final class ErrorServidor extends ErrorApi {
  const ErrorServidor({required super.codigo, required super.mensaje, required super.status});

  @override
  bool get esTransitorio => true;
}

/// 400/404/409/422: el servidor entendió y **dijo que no**. Reintentar lo
/// mismo dará el mismo resultado. El [codigo] es el del catálogo del Doc 5
/// (p. ej. `DESCUENTO_INVALIDO`), y [detalles] trae lo necesario para
/// explicarlo.
final class ErrorRechazado extends ErrorApi {
  const ErrorRechazado({
    required super.codigo,
    required super.mensaje,
    required super.status,
    super.detalles,
  });

  @override
  bool get esPermanente => true;
}
