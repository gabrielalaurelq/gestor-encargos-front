import 'package:dio/dio.dart';

import '../auth/almacen_tokens.dart';
import '../config/ambiente.dart';
import 'error_api.dart';

/// Rutas que no llevan access token (Doc 5, Bloque 1): son las que lo emiten.
const _rutasPublicas = {'/auth/login', '/auth/refresh'};

/// Cliente de la API del Doc 5. Las capas de arriba nunca ven Dio: reciben el
/// JSON ya decodificado o un [ErrorApi].
///
/// Se encarga de dos cosas transversales:
/// 1. **Poner el access token** en cada petición autenticada.
/// 2. **Renovarlo solo** cuando vence (`401`), con `POST /auth/refresh`, y
///    repetir la petición — el usuario nunca ve un "sesión expirada" mientras
///    su refresh token siga vigente (90 días).
class ClienteApi {
  ClienteApi({
    required Ambiente ambiente,
    required AlmacenTokens tokens,
    void Function()? alExpirarSesion,
    HttpClientAdapter? adaptador,
  }) : _dio = _crearDio(ambiente, adaptador) {
    // Dio "crudo", sin interceptores, para el refresh y el reintento: si se
    // usara el mismo, un 401 dentro del manejo de otro 401 quedaría en la cola
    // del interceptor esperando a que este termine — un bloqueo.
    final crudo = _crearDio(ambiente, adaptador);
    _dio.interceptors.add(
      _InterceptorSesion(tokens: tokens, crudo: crudo, alExpirarSesion: alExpirarSesion),
    );
  }

  final Dio _dio;

  static Dio _crearDio(Ambiente ambiente, HttpClientAdapter? adaptador) {
    final dio = Dio(
      BaseOptions(
        baseUrl: ambiente.apiUrl,
        // Conexiones móviles lentas (Doc 3): generoso al recibir, corto al
        // conectar — si no hay red, mejor enterarse rápido y dejarlo en la
        // cola Outbox.
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    if (adaptador != null) dio.httpClientAdapter = adaptador;
    return dio;
  }

  Future<Object?> get(String ruta, {Map<String, Object?>? query}) =>
      _ejecutar(() => _dio.get<Object?>(ruta, queryParameters: _sinNulos(query)));

  Future<Object?> post(String ruta, {Object? cuerpo}) =>
      _ejecutar(() => _dio.post<Object?>(ruta, data: cuerpo));

  Future<Object?> patch(String ruta, {Object? cuerpo}) =>
      _ejecutar(() => _dio.patch<Object?>(ruta, data: cuerpo));

  Future<Object?> delete(String ruta) => _ejecutar(() => _dio.delete<Object?>(ruta));

  Future<Object?> _ejecutar(Future<Response<Object?>> Function() peticion) async {
    try {
      final respuesta = await peticion();
      return respuesta.data;
    } on DioException catch (e) {
      final interno = e.error;
      throw interno is ErrorApi ? interno : ErrorApi.desde(e);
    }
  }

  static Map<String, Object?>? _sinNulos(Map<String, Object?>? query) =>
      query == null ? null : (Map.of(query)..removeWhere((_, v) => v == null));
}

/// `QueuedInterceptor`: atiende los errores **de a uno**. Si cinco peticiones
/// reciben `401` a la vez, la primera renueva el token y las otras cuatro, al
/// llegar su turno, ven que el token ya cambió y solo reintentan — un único
/// `POST /auth/refresh`, no cinco.
class _InterceptorSesion extends QueuedInterceptor {
  _InterceptorSesion({required this.tokens, required this.crudo, this.alExpirarSesion});

  final AlmacenTokens tokens;
  final Dio crudo;
  final void Function()? alExpirarSesion;

  static bool _esPublica(RequestOptions opciones) => _rutasPublicas.contains(opciones.path);

  @override
  Future<void> onRequest(RequestOptions opciones, RequestInterceptorHandler handler) async {
    if (!_esPublica(opciones)) {
      final sesion = await tokens.leer();
      if (sesion != null) {
        opciones.headers['Authorization'] = 'Bearer ${sesion.access}';
      }
    }
    handler.next(opciones);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final opciones = err.requestOptions;
    if (err.response?.statusCode != 401 || _esPublica(opciones)) {
      return handler.next(err);
    }

    final sesion = await tokens.leer();
    if (sesion == null) {
      return handler.next(err);
    }

    // ¿Otra petición ya renovó el token mientras esta esperaba su turno?
    final usado = opciones.headers['Authorization'];
    var access = sesion.access;
    if (usado == 'Bearer $access') {
      try {
        final respuesta = await crudo.post<Map<String, dynamic>>(
          '/auth/refresh',
          data: {'refresh_token': sesion.refresh},
        );
        access = respuesta.data!['access_token'] as String;
        await tokens.guardar(sesion.conAccess(access));
      } on DioException catch (fallo) {
        if (fallo.response?.statusCode == 401) {
          // El refresh token ya no sirve (logout en otro lado, o vencido):
          // la sesión terminó de verdad. Se limpia y se avisa a la app.
          await tokens.borrar();
          alExpirarSesion?.call();
          return handler.next(err);
        }
        // Sin red al renovar: la sesión **no** terminó, solo no se pudo
        // comprobar. No se borra nada; la operación queda para después.
        return handler.reject(fallo);
      }
    }

    try {
      opciones.headers['Authorization'] = 'Bearer $access';
      handler.resolve(await crudo.fetch<Object?>(opciones));
    } on DioException catch (fallo) {
      handler.next(fallo);
    }
  }
}
