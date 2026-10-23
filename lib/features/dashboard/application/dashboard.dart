import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/infrastructure/providers.dart';
import '../../sesion/application/sesion.dart';
import '../data/repositorio_dashboard.dart';
import '../domain/dashboard.dart';

part 'dashboard.g.dart';

@Riverpod(keepAlive: true)
RepositorioDashboard repositorioDashboard(Ref ref) =>
    RepositorioDashboard(base: ref.watch(baseDatosProvider));

@riverpod
Stream<ResumenDashboard> resumenDashboard(Ref ref) =>
    ref.watch(repositorioDashboardProvider).observarResumen();

/// [hoy] es parte de la llave: al cambiar de día, la pantalla pide otra.
@riverpod
Stream<PendientesDelDia> pendientesDelDia(Ref ref, DateTime hoy) =>
    ref.watch(repositorioDashboardProvider).observarPendientes(hoy);

/// `null` si el negocio no tiene nombre o la sesión es anterior al S5a.
@riverpod
Stream<String?> nombreNegocio(Ref ref) =>
    ref.watch(baseDatosProvider).observarMetadato(claveNombreNegocio);
