import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/infrastructure/providers.dart';
import '../../encargos/domain/fila_encargo.dart';
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

@riverpod
Stream<List<FilaEncargo>> listaEncargos(Ref ref, FiltroEncargos filtro) =>
    ref.watch(repositorioDashboardProvider).observarLista(filtro);

/// `null` si el negocio no tiene nombre o la sesión es anterior al S5a.
@riverpod
Stream<String?> nombreNegocio(Ref ref) =>
    ref.watch(baseDatosProvider).observarMetadato(claveNombreNegocio);
