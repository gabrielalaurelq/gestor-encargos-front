import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/sesion/domain/estado_sesion.dart';
import 'package:gestor_encargos/router/router.dart';
import 'package:gestor_encargos/router/rutas.dart';

/// Doc 7, Bloque 2: sin sesión, `/login` antes de renderizar cualquier ruta.
void main() {
  test('mientras se leen los tokens, pantalla de arranque (no asoma el Dashboard)', () {
    expect(redirigir(EstadoSesion.verificando, Rutas.dashboard), Rutas.arranque);
    expect(redirigir(EstadoSesion.verificando, Rutas.arranque), isNull);
  });

  test('sin sesión, toda ruta lleva a /login — también las profundas', () {
    for (final ruta in [Rutas.dashboard, Rutas.encargo('e1'), Rutas.ajustes, Rutas.arranque]) {
      expect(redirigir(EstadoSesion.anonima, ruta), Rutas.login, reason: ruta);
    }
    expect(redirigir(EstadoSesion.anonima, Rutas.login), isNull);
  });

  test('con sesión, /login y el arranque llevan al Dashboard; lo demás se respeta', () {
    expect(redirigir(EstadoSesion.iniciada, Rutas.login), Rutas.dashboard);
    expect(redirigir(EstadoSesion.iniciada, Rutas.arranque), Rutas.dashboard);
    expect(redirigir(EstadoSesion.iniciada, Rutas.encargo('e1')), isNull);
  });
}
