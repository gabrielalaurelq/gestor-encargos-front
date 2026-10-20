# Frontend — Flutter

App Android del Gestor de Encargos. Sigue el **Doc 7** (Flutter) y el **Doc 6** (UX/UI); el contrato con el backend es el **Doc 5 v1.5**.

## Stack

- Flutter 3.44.4 / Dart 3.12 — **solo Android** en el MVP (Doc 0); `applicationId` **`pe.gestorencargos.app`** (permanente en Google Play).
- Estado e inyección de dependencias: **Riverpod** con `riverpod_generator` (Doc 7 Bloque 1-2; sin `get_it`).
- Navegación: **GoRouter** (Doc 7 Bloque 2).
- Base local: **Drift** (offline-first, Doc 3) — llega en el bloque F1.

## Puesta en marcha

```bash
flutter pub get
dart run build_runner build -d     # genera los *.g.dart (no se versionan)
flutter analyze
flutter test
```

Para un teléfono o emulador hace falta el **Android SDK** (Android Studio). La máquina donde se escribió el Sprint 0 no lo tenía: todo se verificó con `flutter test`, que no lo necesita.

## Sprint 0 — plan aprobado (2026-10-20)

Se adelanta el motor de sincronización al Sprint 0, respecto del Doc 11: es la base de todas las pantallas y la pieza de más riesgo. Cada bloque cierra con tests y su commit.

| Bloque | Contenido | Estado |
|---|---|---|
| **F0** | Esqueleto: proyecto Android, lints, Riverpod, GoRouter con el shell de 4 destinos, tema del Doc 6, CI | ✅ |
| **F1** | Infraestructura compartida: ambiente, cliente HTTP con el formato de error del Doc 5 y refresh de token, almacenamiento seguro, Drift base, VOs `Monto` y `Telefono` | ⏳ |
| **F2** | Sesión: puerto de identidad (Google/Firebase) con doble, login/logout, redirect | ⏳ |
| **F3** | Motor de sync: tablas espejo + Outbox, pull (paginación, solape, tombstones, `410`), push con reintentos, numeración Hi/Lo | ⏳ |

**Decisiones del usuario para el motor de sync** (huecos del Doc 7):
- Una operación de la Outbox con **error permanente** (`422`/`409`/`404`) se **aparta** a una lista de "no sincronizadas" y la cola sigue; la app marca el encargo afectado.
- Una fila con operaciones **pendientes** en la Outbox **no se pisa** con lo que trae `/sync`: se aplica cuando su Outbox se vacía. El Last-Write-Wins real lo decide el servidor al recibir el push.

## F0 — Esqueleto

- **Árbol de rutas del Doc 7** completo (`lib/router/`), con pantallas provisionales (`PantallaPendiente`) que dicen en qué sprint llegan: así la navegación se recorre y se prueba desde ya. `StatefulShellRoute` conserva el estado de cada pestaña; las pantallas de profundidad 2 (ficha de cliente, nuevo/detalle de encargo) se apilan en el navegador raíz, **sin** barra inferior.
- **Tema** (`lib/shared/presentation/tema/`): la paleta sale de los **wireframes aprobados** del Doc 6, no inventada — acento `#8A5A00`, verde `#2E7D32`, rojo `#C62828`, ámbar `#8A5A00` sobre `#FDF1DE`, texto `#1C1C1A` sobre `#F4F3F1`. Texto de cuerpo 18sp, toque mínimo 56dp, radio 12.
- **Una corrección a los wireframes:** el gris de los textos de ejemplo (`#8A8A86`) da 3.5:1 sobre blanco y no llega al AA que exige el Doc 6; se usa `#6B6B68`. `colores_test.dart` verifica el contraste de **cada par texto/fondo** de la paleta: un color nuevo entra con su test.
- **Accesibilidad verificada por tests**, no por revisión: áreas táctiles ≥ 56dp, las guías de Flutter (`androidTapTargetGuideline`, `textContrastGuideline`, `labeledTapTargetGuideline`) y la app al **200% de letra del sistema** sin desbordes — nunca se limita el escalado (Doc 6).
- Localización `es-PE` para los textos y selectores del sistema.
- Lints: `flutter_lints` estándar (Doc 7) más `strict-casts`/`strict-raw-types` y tres reglas que evitan errores reales. `riverpod_lint` se dejó fuera: es incompatible con las versiones actuales de Riverpod 3. Ancho de línea 100, como Prettier en el backend.
