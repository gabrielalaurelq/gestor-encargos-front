import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/infrastructure/http/error_api.dart';
import '../../../shared/infrastructure/providers.dart';
import '../../../shared/sync/cambios_pendientes.dart';
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
    // Al arrancar también se re-registra: Firebase pudo rotar el token con la
    // app cerrada, y entonces nadie escuchó la rotación.
    if (tokens != null) unawaited(_registrarNotificaciones());
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
    unawaited(_registrarNotificaciones());
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
