import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/dashboard/presentation/pantalla_dashboard.dart';
import '../features/clientes/presentation/pantalla_clientes.dart';
import '../features/clientes/presentation/pantalla_ficha_cliente.dart';
import '../features/encargos/presentation/pantalla_detalle_encargo.dart';
import '../features/encargos/presentation/pantalla_nuevo_encargo.dart';
import '../features/servicios/presentation/pantalla_catalogo.dart';
import '../features/sincronizacion/presentation/pantalla_cambios_no_guardados.dart';
import '../features/sesion/application/sesion.dart';
import '../features/sesion/domain/estado_sesion.dart';
import '../features/sesion/presentation/pantalla_ajustes.dart';
import '../features/sesion/presentation/pantalla_login.dart';
import '../shared/presentation/widgets/pantalla_pendiente.dart';
import 'menu_mas.dart';
import 'rutas.dart';
import 'shell_principal.dart';

part 'router.g.dart';

/// Navegador raíz: las pantallas de profundidad 2 se apilan acá, encima del
/// shell, para que no muestren la barra inferior (Doc 7, Bloque 2).
final navegadorRaiz = GlobalKey<NavigatorState>(debugLabel: 'raiz');

/// A dónde manda el router según la sesión (Doc 7, Bloque 2: sin sesión,
/// `/login` antes de renderizar cualquier otra ruta). `null` = se queda.
String? redirigir(EstadoSesion sesion, String ubicacion) {
  return switch (sesion) {
    EstadoSesion.verificando => ubicacion == Rutas.arranque ? null : Rutas.arranque,
    EstadoSesion.anonima => ubicacion == Rutas.login ? null : Rutas.login,
    EstadoSesion.iniciada =>
      ubicacion == Rutas.login || ubicacion == Rutas.arranque ? Rutas.dashboard : null,
  };
}

/// GoRouter como provider de Riverpod (Doc 7: Riverpod es también la DI).
///
/// No se reconstruye al cambiar la sesión —perdería la pila de navegación—:
/// la sesión llega por `refreshListenable`, que solo vuelve a evaluar el
/// `redirect`.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final sesion = ValueNotifier(ref.read(sesionProvider));
  ref.listen(sesionProvider, (_, nuevo) => sesion.value = nuevo);
  ref.onDispose(sesion.dispose);

  return GoRouter(
    navigatorKey: navegadorRaiz,
    initialLocation: Rutas.dashboard,
    refreshListenable: sesion,
    redirect: (_, estado) => redirigir(sesion.value, estado.matchedLocation),
    routes: [
      GoRoute(path: Rutas.arranque, builder: (_, _) => const Scaffold()),
      GoRoute(path: Rutas.login, builder: (_, _) => const PantallaLogin()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, navegacion) => ShellPrincipal(navegacion: navegacion),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Rutas.dashboard, builder: (_, _) => const PantallaDashboard())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.clientes,
                builder: (_, _) => const PantallaClientes(),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: navegadorRaiz,
                    builder: (_, estado) =>
                        PantallaFichaCliente(clienteId: estado.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.calendario,
                builder: (_, _) => const PantallaPendiente(
                  titulo: 'Calendario',
                  icono: Icons.calendar_month_outlined,
                  sprint: 'Sprint 6',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.mas,
                builder: (_, _) => const MenuMas(),
                routes: [
                  GoRoute(
                    path: 'balance-carga',
                    builder: (_, _) => const PantallaPendiente(
                      titulo: 'Balance de carga',
                      icono: Icons.bar_chart,
                      sprint: 'Sprint 6',
                    ),
                  ),
                  GoRoute(
                    path: 'caja-diaria',
                    builder: (_, _) => const PantallaPendiente(
                      titulo: 'Caja diaria',
                      icono: Icons.payments_outlined,
                      sprint: 'Sprint 6',
                    ),
                  ),
                  GoRoute(path: 'catalogo-servicios', builder: (_, _) => const PantallaCatalogo()),
                  GoRoute(path: 'ajustes', builder: (_, _) => const PantallaAjustes()),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Rutas.cambiosNoGuardados,
        builder: (_, _) => const PantallaCambiosNoGuardados(),
      ),
      // `nuevo` va antes que `:id` para que no se tome como un id.
      GoRoute(
        path: Rutas.nuevoEncargo,
        builder: (_, estado) =>
            PantallaNuevoEncargo(clienteInicialId: estado.uri.queryParameters['cliente']),
      ),
      GoRoute(
        path: '/encargos/:id',
        builder: (_, estado) => PantallaDetalleEncargo(encargoId: estado.pathParameters['id']!),
      ),
    ],
  );
}
