import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/domain/origen_pago.dart';
import '../../../shared/infrastructure/providers.dart';
import '../../../shared/sync/providers.dart';
import '../data/repositorio_encargos.dart';
import '../data/repositorio_objetos.dart';
import '../data/repositorio_pagos.dart';
import '../data/repositorio_trabajos.dart';
import '../domain/encargo.dart';
import '../domain/objeto_recibido.dart';
import '../domain/pago.dart';
import '../domain/trabajo.dart';

part 'encargos.g.dart';

@Riverpod(keepAlive: true)
RepositorioEncargos repositorioEncargos(Ref ref) => RepositorioEncargos(
  base: ref.watch(baseDatosProvider),
  outbox: ref.watch(outboxProvider),
  numeracion: ref.watch(numeracionProvider),
);

/// Un encargo para su detalle; `null` si no está en el teléfono.
@riverpod
Stream<Encargo?> encargo(Ref ref, String id) => ref.watch(repositorioEncargosProvider).observar(id);

@Riverpod(keepAlive: true)
RepositorioTrabajos repositorioTrabajos(Ref ref) =>
    RepositorioTrabajos(base: ref.watch(baseDatosProvider), outbox: ref.watch(outboxProvider));

/// Los trabajos de un encargo, en el orden en que se agregaron.
@riverpod
Stream<List<Trabajo>> trabajos(Ref ref, String encargoId) =>
    ref.watch(repositorioTrabajosProvider).observar(encargoId);

@Riverpod(keepAlive: true)
RepositorioPagos repositorioPagos(Ref ref) =>
    RepositorioPagos(base: ref.watch(baseDatosProvider), outbox: ref.watch(outboxProvider));

/// Los pagos de un encargo, en el orden en que se hicieron.
@riverpod
Stream<List<Pago>> pagos(Ref ref, String encargoId) =>
    ref.watch(repositorioPagosProvider).observar(encargoId);

/// Los medios de pago que se ofrecen al registrar uno.
@riverpod
Stream<List<OrigenPago>> origenesActivos(Ref ref) =>
    ref.watch(repositorioPagosProvider).observarOrigenesActivos();

@Riverpod(keepAlive: true)
RepositorioObjetos repositorioObjetos(Ref ref) =>
    RepositorioObjetos(base: ref.watch(baseDatosProvider), outbox: ref.watch(outboxProvider));

/// Los objetos recibidos de un encargo, en el orden en que se agregaron.
@riverpod
Stream<List<ObjetoRecibido>> objetos(Ref ref, String encargoId) =>
    ref.watch(repositorioObjetosProvider).observar(encargoId);
