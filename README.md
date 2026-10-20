# Frontend — Flutter

App Android del Gestor de Encargos. Sigue el **Doc 7** (Flutter) y el **Doc 6** (UX/UI); el contrato con el backend es el **Doc 5 v1.5**.

## Stack

- Flutter 3.44.4 / Dart 3.12 — **solo Android** en el MVP (Doc 0); `applicationId` **`pe.gestorencargos.app`** (permanente en Google Play).
- Estado e inyección de dependencias: **Riverpod** con `riverpod_generator` (Doc 7 Bloque 1-2; sin `get_it`).
- Navegación: **GoRouter** (Doc 7 Bloque 2).
- Base local: **Drift** (offline-first, Doc 3). HTTP: **Dio**. Sesión: **flutter_secure_storage**.

## Puesta en marcha

```bash
flutter pub get
dart run build_runner build -d     # genera los *.g.dart (no se versionan)
flutter analyze
flutter test

# Contra otro backend que el local del emulador (http://10.0.2.2:3000/api/v1):
flutter run --dart-define=API_URL=https://staging.ejemplo.pe/api/v1
```

Para un teléfono o emulador hace falta el **Android SDK** (Android Studio). La máquina donde se escribió el Sprint 0 no lo tenía: todo se verificó con `flutter test`, que no lo necesita.

## Sprint 0 — plan aprobado (2026-10-20)

Se adelanta el motor de sincronización al Sprint 0, respecto del Doc 11: es la base de todas las pantallas y la pieza de más riesgo. Cada bloque cierra con tests y su commit.

| Bloque | Contenido | Estado |
|---|---|---|
| **F0** | Esqueleto: proyecto Android, lints, Riverpod, GoRouter con el shell de 4 destinos, tema del Doc 6, CI | ✅ |
| **F1** | Infraestructura compartida: ambiente, cliente HTTP con el formato de error del Doc 5 y refresh de token, almacenamiento seguro, Drift base, VOs `Monto` y `Telefono` | ✅ |
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

## F1 — Infraestructura compartida (`lib/shared/`)

- **`ClienteApi`** (`infrastructure/http/`): las capas de arriba nunca ven Dio, reciben JSON o un `ErrorApi`. Pone el access token y, ante un `401`, **renueva solo** con `POST /auth/refresh` y repite la petición.
  - **Un solo refresh aunque fallen varias peticiones a la vez**: un `QueuedInterceptor` atiende los `401` de a uno, y los que llegan después ven que el token ya cambió y solo reintentan.
  - Refresh rechazado (`401`) → la sesión terminó de verdad: se borran los tokens y se avisa (la navegación a `/login` la conecta F2). **Sin red al renovar → no se borra nada**: la sesión no terminó, solo no se pudo comprobar.
  - El refresh y el reintento van por un Dio sin interceptores: con el mismo, un `401` dentro del manejo de otro quedaría esperando en la cola del propio interceptor (bloqueo).
- **`ErrorApi`**, jerarquía cerrada traducida del formato del Doc 5. Pensada para lo que necesita decidir la cola Outbox de F3, no solo para mostrar texto: `esTransitorio` (sin red, 5xx, 429 con su `Retry-After`) se reintenta; `esPermanente` (400/404/409/422, `ErrorRechazado` con el código del catálogo) se aparta; `NoAutenticado` y `SyncDemasiadoAntiguo` (`410`) tienen su propio tratamiento.
- **Tokens en `flutter_secure_storage`** (Keystore de Android), nunca en `SharedPreferences` ni en Drift: el refresh token es una credencial de 90 días. Puerto `AlmacenTokens` con una implementación en memoria para los tests.
- **`BaseDatos`** (Drift) con la tabla `metadatos` (clave-valor del dispositivo, para la marca `since` y el bloque Hi/Lo de F3), `PRAGMA foreign_keys = ON` (SQLite las trae apagadas) y la estrategia de migraciones: pasos encadenados desde la versión que tenga el teléfono, generados con `drift_dev make-migrations`. SQLite nativo funciona en los tests de Windows sin configuración extra.
- **VOs `Monto` y `Telefono`** (`domain/`), con **las mismas reglas que el backend**: `Monto` en céntimos enteros (un `double` sumaría distinto que el servidor y el saldo "saltaría" al sincronizar), tercer decimal rechazado, formato peruano `S/ 1,234.50`. `Telefono` normaliza en la app —el backend exige E.164 y no adivina el país—: `Telefono.peruano('987654321')` para el modo por defecto del PRD y `Telefono.e164()` para el internacional. Los errores llevan el mismo código que el catálogo del Doc 5 (`MONTO_INVALIDO`, `TELEFONO_INVALIDO`).
- **Configuración por ambiente** con `--dart-define=API_URL=...`, nunca en un archivo dentro del APK.

**Dos fallas de Android que ningún test detecta, corregidas al revisar los manifiestos:** el permiso `INTERNET` solo existía en los manifiestos de debug/profile —**el APK de release no habría tenido red**—, y Android bloquea `http://` en claro desde la API 28, que es como se sirve el backend local; el tráfico en claro se habilita **solo en debug**.
