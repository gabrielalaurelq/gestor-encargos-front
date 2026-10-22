import 'dart:async';
import 'dart:math';

import '../infrastructure/auth/almacen_tokens.dart';
import '../infrastructure/http/error_api.dart';
import 'bajada.dart';
import 'numeracion.dart';
import 'origenes_pago.dart';
import 'subida.dart';

/// Lo que la UI puede mostrar de la sincronización: un ícono discreto, nunca
/// un banner (Doc 6, "offline invisible"; Doc 7, `syncStatusProvider`).
class EstadoSync {
  const EstadoSync({
    this.sincronizando = false,
    this.ultimaCompleta,
    this.ultimoError,
    this.proximoIntento,
  });

  final bool sincronizando;

  /// Última vuelta que terminó entera (subida y bajada).
  final DateTime? ultimaCompleta;

  /// Error de la última vuelta; `null` si salió bien. Sin red es lo normal en
  /// una app offline-first, no una falla.
  final Object? ultimoError;

  /// Cuándo se reintenta sola, si la última vuelta falló.
  final DateTime? proximoIntento;

  bool get sinConexion => ultimoError is SinConexion;
}

/// Espera entre reintentos tras `fallos` vueltas fallidas seguidas: 5 s, 10 s,
/// 20 s… hasta 5 min. Creciente para no gastar batería ni datos insistiendo
/// sin red; con tope para que, al volver la red sin aviso, no tarde mucho.
Duration esperaPorDefecto(int fallos) =>
    Duration(seconds: min(5 * pow(2, fallos - 1).toInt(), 300));

/// Orquesta el motor: cuándo sincronizar y en qué orden.
///
/// **Una vuelta:** reservar números si hacen falta → subir la Outbox → bajar
/// de `/sync` → el catálogo de orígenes de pago, si hace falta. Primero se sube: así lo que baja ya incluye los cambios
/// propios ya aceptados, y las filas que dejaron de estar protegidas se
/// refrescan en esa misma vuelta.
///
/// **Disparadores:** al entrar o abrir la app con sesión, al volver al primer
/// plano, al recuperar la red y al encolar una operación (los conecta quien
/// crea el motor). Si llega uno durante una vuelta, se hace **otra vuelta al
/// terminar** —no se pierde— y nunca dos a la vez.
class MotorSync {
  MotorSync({
    required this._bajada,
    required this._subida,
    required this._numeracion,
    required this._tokens,
    this._origenes,
    Duration Function(int fallos)? espera,
    DateTime Function()? reloj,
  }) : _espera = espera ?? esperaPorDefecto,
       _reloj = reloj ?? DateTime.now;

  final Bajada _bajada;
  final Subida _subida;
  final Numeracion _numeracion;
  final AlmacenTokens _tokens;
  final OrigenesPagoRemotos? _origenes;
  final Duration Function(int fallos) _espera;
  final DateTime Function() _reloj;

  final _estados = StreamController<EstadoSync>.broadcast();
  EstadoSync _estado = const EstadoSync();
  Future<void>? _enCurso;
  bool _otraVuelta = false;
  int _fallos = 0;
  Timer? _reintento;

  EstadoSync get estado => _estado;
  Stream<EstadoSync> get estados => _estados.stream;

  void _emitir(EstadoSync nuevo) {
    _estado = nuevo;
    if (!_estados.isClosed) _estados.add(nuevo);
  }

  /// Pide una sincronización. Nunca lanza: el resultado queda en [estado].
  Future<void> sincronizar() {
    final enCurso = _enCurso;
    if (enCurso != null) {
      _otraVuelta = true;
      return enCurso;
    }
    _reintento?.cancel();
    return _enCurso = _vueltas().whenComplete(() => _enCurso = null);
  }

  Future<void> _vueltas() async {
    do {
      _otraVuelta = false;
      await _vuelta();
    } while (_otraVuelta);
  }

  Future<void> _vuelta() async {
    // Sin sesión no hay a quién sincronizar (cerró sesión o nunca entró).
    if (await _tokens.leer() == null) return;

    _emitir(
      EstadoSync(
        sincronizando: true,
        ultimaCompleta: _estado.ultimaCompleta,
        ultimoError: _estado.ultimoError,
      ),
    );
    try {
      await _reservarNumeros();
      await _subida.subir();
      await _bajada.bajar();
      await _actualizarOrigenes();
      _fallos = 0;
      _emitir(EstadoSync(ultimaCompleta: _reloj()));
    } on NoAutenticado catch (error) {
      // La sesión terminó: la feature de sesión ya lleva al login. Reintentar
      // no serviría; el próximo login dispara una vuelta nueva.
      _emitir(EstadoSync(ultimaCompleta: _estado.ultimaCompleta, ultimoError: error));
    } on Object catch (error) {
      _fallos++;
      var espera = _espera(_fallos);
      if (error is LimiteExcedido && error.reintentarEn != null) {
        espera = _mayor(espera, error.reintentarEn!);
      }
      _reintento = Timer(espera, () => unawaited(sincronizar()));
      _emitir(
        EstadoSync(
          ultimaCompleta: _estado.ultimaCompleta,
          ultimoError: error,
          proximoIntento: _reloj().add(espera),
        ),
      );
    }
  }

  /// Un fallo **permanente** al reservar no detiene la vuelta: sin bloque, los
  /// encargos se crean igual (Doc 3, caso límite) y la Outbox no puede
  /// quedarse esperando a la numeración. Uno transitorio sí: sin red tampoco
  /// subiría ni bajaría nada.
  Future<void> _reservarNumeros() async {
    try {
      await _numeracion.reservarSiHaceFalta();
    } on ErrorApi catch (error) {
      if (!error.esPermanente) rethrow;
    }
  }

  /// Un fallo aquí no detiene la vuelta ni la marca como fallida (Doc 7
  /// v1.3): los datos del negocio ya están al día, y sin catálogo solo falta
  /// poder registrar pagos. Se reintenta en la próxima vuelta.
  Future<void> _actualizarOrigenes() async {
    try {
      await _origenes?.actualizarSiHaceFalta();
    } on ErrorApi {
      // Sin red o un backend sin el endpoint: la próxima vuelta lo intenta.
    }
  }

  static Duration _mayor(Duration a, Duration b) => a > b ? a : b;

  void cerrar() {
    _reintento?.cancel();
    unawaited(_estados.close());
  }
}
