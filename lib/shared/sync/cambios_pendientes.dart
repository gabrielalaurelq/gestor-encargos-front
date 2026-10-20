import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cambios_pendientes.g.dart';

/// Cuántas operaciones esperan en la cola Outbox para subir al servidor.
///
/// Lo consume el cierre de sesión: con cambios sin enviar, **no se deja
/// cerrar** (decisión del usuario, Sprint 0 F2) — cerrar sesión borra la base
/// local, y con ella esos cambios.
///
/// Hasta que exista la Outbox (bloque F3) no hay nada pendiente; F3 reemplaza
/// el cuerpo por la cuenta reactiva de `outbox_operations`.
@Riverpod(keepAlive: true)
Stream<int> cambiosPendientes(Ref ref) => Stream.value(0);
