import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/infrastructure/http/error_api.dart';
import '../../../shared/infrastructure/providers.dart';
import '../../../shared/sync/providers.dart';
import '../data/proveedor_identidad.dart';
import '../data/sesion_remota.dart';
import '../data/token_notificaciones.dart';
import '../domain/estado_sesion.dart';

part 'sesion.g.dart';

@Riverpod(keepAlive: true)
ProveedorIdentidad proveedorIdentidad(Ref ref) => const ProveedorIdentidadNoConfigurado();

@Riverpod(keepAlive: true)
TokenNotificaciones tokenNotificaciones(Ref ref) => const SinNotificaciones();

@Riverpod(keepAlive: true)
SesionRemota sesionRemota(Ref ref) => SesionRemota(ref.watch(clienteApiProvider));

/// Negocio dueño de los datos de la base local. Si entra otra cuenta, esos
/// datos no son suyos y se borran antes de mostrar nada.
const _claveNegocio = 'sesion.negocio_id';

/// El nombre del negocio, para la cabecera del Dashboard (S5a). Se guarda en
/// cada login; una sesión abierta antes del S5a no lo tiene hasta el próximo.
const claveNombreNegocio = 'negocio.nombre';

/// La sesión del dispositivo: login, logout y fin de sesión forzado.
///
/// Dos formas de terminar, con efectos distintos a propósito:
/// - **El usuario cierra sesión** → se borra la base local entera.
/// - **La sesión expira** (refresh rechazado) → se conservan los datos y la
///   Outbox: si vuelve a entrar con la misma cuenta, sus cambios hechos sin
///   conexión siguen ahí y suben. Si entra otra cuenta, se borran al entrar.
@Riverpod(keepAlive: true)
class Sesion extends _$Sesion {
  @override
  EstadoSesion build() {
    final expiradas = ref
        .watch(avisoSesionProvider)
        .expiradas
        .listen((_) => state = EstadoSesion.anonima);
    final rotaciones = ref.watch(tokenNotificacionesProvider).rotaciones.listen((token) {
      if (state == EstadoSesion.iniciada) unawaited(_registrarToken(token));
    });
    ref.onDispose(() {
      unawaited(expiradas.cancel());
      unawaited(rotaciones.cancel());
    });

    unawaited(_cargar());
    return EstadoSesion.verificando;
  }

  Future<void> _cargar() async {
    final tokens = await ref.read(almacenTokensProvider).leer();
    if (!ref.mounted) return;
    state = tokens == null ? EstadoSesion.anonima : EstadoSesion.iniciada;
    if (tokens != null) _alIniciar();
  }

  /// `null` si entró, o si el usuario cerró el selector de cuentas.
  Future<FalloLogin?> iniciarSesion() async {
    final String? idToken;
    try {
      idToken = await ref.read(proveedorIdentidadProvider).obtenerIdToken();
    } on IdentidadNoDisponible {
      return FalloLogin.noDisponible;
    }
    if (idToken == null) return null;

    try {
      final nueva = await ref.read(sesionRemotaProvider).iniciar(idToken);
      final base = ref.read(baseDatosProvider);
      final anterior = await base.leerMetadato(_claveNegocio);
      if (anterior != null && anterior != nueva.negocioId) await base.borrarTodo();
      await base.guardarMetadato(_claveNegocio, nueva.negocioId);
      final nombre = nueva.nombreNegocio?.trim() ?? '';
      if (nombre.isEmpty) {
        await base.borrarMetadato(claveNombreNegocio);
      } else {
        await base.guardarMetadato(claveNombreNegocio, nombre);
      }
      await ref.read(almacenTokensProvider).guardar(nueva.tokens);
    } on SinConexion {
      return FalloLogin.sinConexion;
    } on NoAutenticado {
      return FalloLogin.rechazado;
    } on LimiteExcedido {
      return FalloLogin.demasiadosIntentos;
    } on ErrorApi {
      return FalloLogin.servidor;
    }

    state = EstadoSesion.iniciada;
    _alIniciar();
    return null;
  }

  /// `null` si cerró. Con cambios sin enviar o sin red, **no** cierra: el
  /// usuario sigue dentro con todo intacto.
  Future<FalloCierre?> cerrarSesion() async {
    // `listen`, no `read`: Riverpod 3 pausa los providers sin oyentes, y un
    // stream pausado nunca entregaría su primer valor.
    final suscripcion = ref.listen(cambiosPendientesProvider.future, (_, _) {});
    final int pendientes;
    try {
      pendientes = await suscripcion.read();
    } finally {
      suscripcion.close();
    }
    if (pendientes > 0) return CierreConPendientes(pendientes);

    try {
      await ref.read(sesionRemotaProvider).cerrar();
    } on NoAutenticado {
      // La sesión ya no existía en el servidor: no hay nada que avisarle, se
      // termina de cerrar en el teléfono.
    } on SinConexion {
      return const CierreSinConexion();
    } on ErrorApi {
      return const CierreFallido();
    }

    await ref.read(almacenTokensProvider).borrar();
    await ref.read(baseDatosProvider).borrarTodo();
    try {
      await ref.read(proveedorIdentidadProvider).cerrar();
    } on Object {
      // Olvidar la cuenta de Google es cortesía para el próximo ingreso; si
      // falla, la sesión de la app ya está cerrada igual.
    }
    state = EstadoSesion.anonima;
    return null;
  }

  /// Al entrar y al abrir la app con sesión: sincronizar (Doc 7: al iniciar
  /// sesión se reserva el bloque de números y se trae lo del servidor) y
  /// registrar el token de notificaciones — también al abrir, porque Firebase
  /// pudo rotarlo con la app cerrada y nadie escuchó la rotación.
  void _alIniciar() {
    unawaited(ref.read(motorSyncProvider).sincronizar());
    unawaited(_registrarNotificaciones());
  }

  Future<void> _registrarNotificaciones() async {
    final token = await ref.read(tokenNotificacionesProvider).obtener();
    if (token != null) await _registrarToken(token);
  }

  /// Sin reintento propio: si falla (sin red, o `409 FCM_TOKEN_EN_USO` porque
  /// el dueño anterior del teléfono no cerró sesión), se vuelve a intentar en
  /// el próximo arranque. Perder un recordatorio no justifica molestar.
  Future<void> _registrarToken(String token) async {
    try {
      await ref.read(sesionRemotaProvider).registrarTokenNotificaciones(token);
    } on ErrorApi {
      return;
    }
  }
}
