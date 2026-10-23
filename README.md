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
| **F2** | Sesión: puerto de identidad (Google/Firebase) con doble, login/logout, redirect | ✅ |
| **F3a** | Motor de sync, bajada: tablas espejo de las 9 colecciones, pull (paginación, solape, tombstones, `410`) | ✅ |
| **F3b** | Motor de sync, subida: Outbox con reintentos y apartado de rechazos, numeración Hi/Lo, `syncStatusProvider`, pendientes → cierre de sesión | ✅ |

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

## F2 — Sesión (`lib/features/sesion/`)

- **Login con un solo botón** ("Continuar con Google", Doc 6) → `POST /auth/login` → tokens al almacenamiento seguro → directo al Dashboard, sin tour. Cerrar el selector de cuentas no es un error: no se muestra nada. Cada fallo tiene su mensaje en lenguaje llano; el más importante, **"la primera vez se necesita internet"**, porque el negocio se crea en el servidor.
- **Redirect de GoRouter** (`redirigir()`, función pura con sus tests): sin sesión, toda ruta —también las profundas— lleva a `/login`; con sesión, `/login` lleva al Dashboard. Mientras se leen los tokens al arrancar hay una pantalla en blanco de milisegundos (`/arranque`), para que el Dashboard no asome antes de saber si hay sesión. El router **no se reconstruye** al cambiar la sesión (perdería la pila): la recibe por `refreshListenable`.
- **Dos formas de terminar, con efectos distintos a propósito:**
  - **El usuario cierra sesión** (Ajustes → confirmación) → `POST /auth/logout` y se **borra la base local entera** (`BaseDatos.borrarTodo()`, que recorre todas las tablas: una tabla nueva queda cubierta sola).
  - **La sesión expira** (refresh rechazado: logout desde otro lado, o 90 días) → vuelve al login **conservando datos y Outbox**: si entra la misma cuenta, sus cambios hechos sin conexión siguen ahí y suben. Si entra **otra** cuenta, los datos del negocio anterior se borran al entrar (se compara el `negocio.id` guardado).
- **No se deja cerrar sesión** (decisión del usuario): con **cambios sin enviar** —cerrar los borraría—, ni **sin red** —la sesión seguiría viva en el servidor y el teléfono recibiendo las notificaciones del negocio—. En ambos casos el usuario sigue dentro con todo intacto y un mensaje dice qué hacer. La cuenta de pendientes es `cambiosPendientesProvider` (`shared/sync/`), que hoy devuelve 0 y F3 conecta a la Outbox.
- **El cliente HTTP avisa, la feature decide:** `ClienteApi` emite la expiración por `AvisoSesion` y la sesión la escucha — `shared/` no importa nada de `features/`.
- **Notificaciones (FCM)**: el token se registra (`POST /dispositivos/fcm-token`) al entrar, en cada arranque con sesión (Firebase pudo rotarlo con la app cerrada) y en cada rotación. Es *best effort*: un fallo —sin red, o `409 FCM_TOKEN_EN_USO`— no impide entrar y se reintenta en el próximo arranque. Al cerrar sesión **no** se llama a `DELETE /dispositivos/fcm-token`: `/auth/logout` ya borra la fila del dispositivo, token incluido (Doc 5). El Doc 7 (Bloque 3, punto 4) pedía ambas llamadas; enmendado en el Doc 7 v1.1.

**Deuda técnica — sin proyecto Firebase.** `ProveedorIdentidad` y `TokenNotificaciones` son puertos con implementaciones vacías (`ProveedorIdentidadNoConfigurado`, que hace que el login diga "todavía no está configurado", y `SinNotificaciones`). Las reales (`google_sign_in` + `firebase_auth`, `firebase_messaging`) entran con el `google-services.json`: agregar esos paquetes antes rompería el arranque, porque Firebase falla al inicializarse sin su configuración. Hasta entonces la app no puede entrar contra un backend real; todo el flujo está probado con dobles (`test/helpers/entorno_prueba.dart`).

## F3a — Motor de sync, bajada (`lib/shared/sync/`, `lib/shared/infrastructure/db/tablas.dart`)

- **Tablas espejo** de las 9 colecciones de `/sync`, con las columnas que el backend proyecta. Dinero en **céntimos**; fechas de hecho como texto `AAAA-MM-DD` (sin hora ni zona: ninguna conversión las corre un día); `creado_en`/`actualizado_en` como el texto ISO del servidor, que se compara como texto sin perder milisegundos. Índices por cada llave padre.
- **Sin llaves foráneas declaradas, a propósito:** `/sync` pagina cada colección por separado, así que la página 1 puede traer un trabajo cuyo encargo llega en la página 2. Una FK rechazaría ese hijo y la sincronización no avanzaría nunca. La integridad es del servidor; al terminar de paginar la copia local queda completa.
- **`Bajada.bajar()`**, con las reglas del Doc 5:
  - El próximo `since` es el `servidor_timestamp`, guardado **en la misma transacción** que los cambios de su página: si la app muere a mitad, o entró la página entera y avanzó la marca, o nada. Una fila inválida descarta su página completa.
  - Las filas repetidas por el solape se aplican sin efecto (upsert por id), y **una versión más vieja nunca pisa una más nueva** (el upsert solo escribe si `actualizado_en` no retrocede).
  - Un tombstone borra la fila local, notificando a los streams de Drift: la UI se refresca sola.
  - `has_more` → página siguiente con la marca recibida. Si la marca no avanza (el límite conocido del backend: 500 filas con el mismo `actualizado_en`), **falla a la vista en vez de girar en vacío**.
  - `410` → descarta lo sincronizado **salvo las filas con cambios pendientes** y rehace todo sin `since`, en una transacción con el borrado de la marca: si la app muere en medio, la próxima bajada arranca de cero igual. Un segundo `410` seguido es un error, no un bucle.
  - Las filas con cambios pendientes en la Outbox **no se tocan** (decisión del usuario); la marca avanza igual. El puerto `IdsProtegidos` hoy devuelve vacío y F3b lo conecta a la Outbox.
  - Dos llamadas simultáneas comparten la misma bajada.
- **Esquema editable hasta el primer release:** como ningún teléfono tiene la app, `schemaVersion` sigue en 1 y las tablas se agregaron en el lugar. Desde el primer build en Google Play, cada cambio es una versión con su paso de migración.

## F3b — Motor de sync, subida (`lib/shared/sync/`)

- **Outbox** (`outbox_operations`, Doc 7): cada escritura local deja una operación con el método, la ruta y el cuerpo REST que se enviarán, la fila que toca y la raíz de su agregado. **Se encola en la misma transacción que la escritura local** (`Outbox.encolar`): o quedan las dos o ninguna. El orden lo da un id `AUTOINCREMENT`, que nunca retrocede.
- **`Subida.subir()`**, en orden, operación por operación: bien (o `200` de alta repetida) → sale de la cola; **rechazo permanente** → se **aparta** y la cola sigue (decisión del usuario); **transitorio** → se detiene ahí, sin saltarla, y se reintenta desde esa misma; **sesión terminada** → se detiene sin apartar.
- **Protección en el pull:** la bajada no pisa la fila **ni la raíz del agregado** de ninguna operación de la cola —el servidor recalcula los totales del encargo al recibirla—. Cuando la operación sube, la fila deja de estar protegida y se refresca en la misma vuelta, porque **se sube antes de bajar**.
- **Las apartadas también quedan protegidas,** y esto corrige lo anotado al cerrar F3a (volver a pedir la fila al apartar): hacerlo reemplazaría en silencio la versión local que el servidor rechazó, y el usuario nunca sabría qué no se guardó. Se conserva y se lista (`operacionesApartadasProvider`, con el encargo a marcar y el código del Doc 5). **Cómo se resuelve una apartada (descartar o corregir) queda pendiente**: necesita la pantalla que la muestre y una decisión de producto. Mientras no se resuelva, los cambios del servidor sobre esa fila no bajan.
- **Numeración Hi/Lo** (`Numeracion`): rangos de `POST /encargos/reservar-bloque-numeros` guardados en `metadatos`; con 10 o menos restantes se pide otro, y el de reserva convive con el que se gasta. `tomar()` va dentro de la transacción del alta: un número tomado y no usado sería un hueco. **Caso límite del Doc 3** (bloque agotado sin red): el backend no puede numerar un encargo después de crearlo —un alta sin `numero` queda en `null` para siempre—, así que la última oportunidad es **justo antes de subirlo**: la vuelta reserva un bloque primero, con red, y `numerarSiFalta` numera a la vez la operación y la fila local.
- **`MotorSync`** — una vuelta: reservar números → subir → bajar. **Disparadores:** entrar o abrir la app con sesión, volver al primer plano, recuperar la red (`connectivity_plus`, detrás del puerto `Conectividad`) y encolar. Un pedido durante una vuelta produce **una vuelta más al terminar**, nunca dos en paralelo. Si falla, **reintenta solo** a los 5 s, 10 s, 20 s… con tope de 5 min (o el `Retry-After` de un `429`, si es mayor); recuperar la red reintenta en el acto. Sesión terminada → no reintenta. Un rechazo permanente al reservar números no frena la vuelta: sin bloque, los encargos se crean igual.
- **`syncStatusProvider`** (Doc 7): sincronizando, última vuelta completa, último error (`sinConexion` es lo normal offline, no una falla) y próximo reintento — para un ícono discreto, nunca un banner (Doc 6).
- **`cambiosPendientesProvider`** cuenta ahora la Outbox real: el cierre de sesión de F2 ya bloquea con cambios sin enviar. Las apartadas no cuentan —no van a subir—, si no, un rechazo sin resolver impediría cerrar sesión para siempre.

**Documentación:** lo decidido al implementar F2-F3b quedó recogido en el Doc 7 v1.1 (Bloques 2 y 3) y el Doc 11 v1.1 (Sprint 0 partido en bloques, riesgos nuevos).

## Sprint 1 — plan aprobado (2026-10-20)

Clientes y Catálogo de servicios (Doc 11), en tres bloques. El catálogo va primero: es el módulo más simple y estrena el patrón de escritura que repetirán los demás.

| Bloque | Contenido | Estado |
|---|---|---|
| **S1a** | Catálogo de servicios: lista, alta, cambio de precio, desactivar/reactivar | ✅ |
| **S1b** | Clientes: lista con búsqueda local en tiempo real, alta y edición con teléfono peruano o internacional | ✅ |
| **S1c** | Ficha de cliente: datos, resumen del historial y encargos, calculados en local | ✅ |

## S1a — Catálogo de servicios (`lib/features/servicios/`)

- **El patrón de escritura de todas las features:** el repositorio escribe en Drift y encola su operación **en la misma transacción**; la pantalla lee una consulta reactiva y nunca espera a la red.
- **Las escrituras locales no adelantan `actualizado_en`** (`sinVersionDelServidor`, en `tablas.dart`): esa columna es la versión del servidor que tiene el teléfono. Con la hora del teléfono, un reloj adelantado haría que el pull rechace para siempre la versión del servidor. Lo que hace ganar a un cambio local mientras no sube es la Outbox, no la marca.
- Reglas y códigos del backend validados antes de guardar (nombre no vacío; precio ≥ 0, el cero vale), para que un rechazo del servidor —que la Outbox apartaría— no dependa del usuario. El **nombre no se edita** (el `PATCH` del Doc 5 no lo admite): la hoja lo dice y propone desactivar y crear otro.
- **Desactivados aparte, plegados y reactivables** (decisión del usuario). Desactivar no pide confirmación: el aviso ofrece "Deshacer".
- El campo de precio no acepta signo ni coma: la coma es separador de miles en el formato peruano y sería ambigua.
- Tests de pantalla contra Drift en memoria, con `testWidgetsConBase` (`test/helpers/entorno_prueba.dart`): Drift suelta sus consultas reactivas con un timer de 0, así que el test desmonta la app y avanza 1 ms antes de terminar, y la base se cierra en un `tearDown` normal (dentro del tiempo simulado, cerrarla no avanza nunca).

## S1b — Clientes (`lib/features/clientes/`)

- **Búsqueda en tiempo real sobre la base local** (PRD módulo 1, Caso 8): parte del nombre sin importar mayúsculas ni tildes ("nunez" encuentra "Núñez", también en medio de una palabra) o dígitos del teléfono ("987 65", con o sin `+51`). SQLite no ignora tildes, así que `clientes.nombre_busqueda` guarda `normalizarBusqueda(nombre)` (`shared/domain/texto_busqueda.dart`), calculada al escribir en local y al bajar; también da el orden alfabético. `%` y `_` se buscan como texto, igual que el backend.
- **Sin resultados → "Crear cliente «texto»"** con lo buscado prellenado: en el nombre, o en el celular si lo buscado es un número.
- **Teléfono** (PRD): celular peruano de 9 dígitos por defecto, con el `+51` visible pero sin escribirlo; "Número de otro país" cambia el campo al número completo. Opcional; al editar, vaciarlo lo borra (`PATCH` con `telefono: null` explícito: ausente sería "no tocar"). El `PATCH` lleva solo lo que cambió.
- **Teléfono repetido: aviso que no bloquea** (decisión del usuario). "Ya tienes a X con este número" con "Ver a X" (no crea nada) o "Guardar igual".
- `HojaCliente` devuelve el cliente creado o el existente elegido: Crear Encargo (Sprint 2) la reutiliza para crear un cliente sin salir del flujo. La edición se abre desde la ficha (S1c).
- **Bug corregido de paso:** el shell mantiene vivas las pestañas, y dos botones (+) con el `heroTag` por defecto chocaban al abrir una pantalla de profundidad 2. Los botones flotantes van sin Hero.

## S1c — Ficha de cliente (`lib/features/clientes/presentation/pantalla_ficha_cliente.dart`)

- **Datos, resumen y encargos, todo de la base local** (PRD módulos 1 y 18). Una sola consulta reactiva (`RepositorioClientes.encargosDe`) trae los encargos del cliente con lo pagado en cada uno; el resumen se calcula sobre esa misma lista (`ResumenCliente.de`), así que no pueden contradecirse, y se actualiza solo cuando entra un pago o baja un cambio.
- **Mismas reglas que `GET /clientes/{id}`:** cuenta todos los encargos (también cancelados), suma todos sus pagos (también de cancelados, como la Caja diaria), y "Última visita" es el alta más reciente en el día de Lima (UTC-5, `shared/domain/dia.dart`). Orden de la lista: alta más reciente primero, como `GET /clientes/{id}/encargos`. Sin encargos dice "Aún no tiene encargos." en vez de ceros.
- Cada encargo: descripción, número ("Sin número aún" si no tiene), estado escrito con color de apoyo (`EtiquetaEstado`), fecha de entrega si sigue abierto o de entrega real si se entregó, y "Debe S/ X" si tiene saldo (un cancelado no debe). Tocarlo abre el Detalle de Encargo (aún pendiente).
- **Editar** abre la `HojaCliente` del S1b. **"Nuevo encargo"** (decisión del usuario) abre Crear Encargo con `?cliente=<id>`: Crear Encargo (Sprint 2) debe leerlo y dejar al cliente ya elegido.
- `EstadoEncargo` (`features/encargos/domain/`) queda creado para Dashboard, Calendario y Detalle. `EncargoDeCliente` es un modelo de solo lectura para esta lista: **deuda menor**, revisar si se unifica con el agregado Encargo del Sprint 2.
- `testWidgetsConBase` ahora desmonta también si el test falla: antes, un fallo dejaba colgados los tests siguientes del archivo.

## Sprint 2 — plan aprobado (2026-10-22)

| Bloque | Contenido | Estado |
|---|---|---|
| **S2a** | Crear Encargo: cliente, descripción y fecha de entrega (Caso 7) | ✅ |
| **S2b** | Detalle de Encargo: cabecera (las secciones llegan en Sprints 3-4) | ✅ |
| **S2c** | Editar datos generales: descripción, reprogramar, ubicación, notas (el descuento va con Trabajos, Sprint 3) | ✅ |

## S2a — Crear Encargo (`lib/features/encargos/`)

- **Solo 3 campos** (Doc 6, PRD módulo 2): cliente, "¿Qué hay que hacer?" y fecha de entrega. Desde la ficha llega con `?cliente=<id>` y el cliente ya elegido; desde el (+) del Inicio, sin elegir.
- **Elegir cliente** abre `HojaElegirCliente`: la misma búsqueda de la pestaña Clientes (`BuscadorClientes`, extraído y compartido) y, si no está, "Crear cliente «texto»" con la `HojaCliente` del S1b, sin salir del flujo. El cliente nuevo sube antes que su encargo (la cola respeta el orden).
- **Fecha** con atajos de un toque (Hoy, Mañana, En 3 días, En 1 semana) y "Otra fecha…"; sin fecha marcada de entrada. `SelectorFechaEntrega` se reutiliza al reprogramar (S2c). Una **fecha pasada se acepta con aviso** "Esa fecha ya pasó. ¿Es correcta?" y "Guardar igual" (decisión del usuario: pasar encargos del cuaderno). "Hoy" es el día de Lima según el reloj del teléfono.
- **Al guardar**, en una transacción: número del bloque Hi/Lo (sin red; si se agotó, sin número y se numera al subir), fila INGRESADO en cero con prometida = acordada, y el `POST /encargos` en la cola. Luego **reemplaza** la pantalla por el Detalle (decisión del usuario; "atrás" no vuelve al formulario) con "Encargo #N creado".
- **Salir con algo escrito pide confirmación** ("¿Descartar este encargo?"); vacío sale directo. El botón Guardar va fijo abajo, siempre visible.
- `Aviso` (advertencia ámbar que no bloquea) queda compartido con el teléfono repetido.

## S2b — Detalle de Encargo, cabecera (`lib/features/encargos/presentation/pantalla_detalle_encargo.dart`)

- **Como el wireframe del Doc 6:** "Encargo #47" (o "sin número aún") con la etiqueta de estado; cliente con su celular (tocarlo abre su ficha); descripción; Entrega, Ubicación ("Sin ubicación" si no hay), Precio total y Saldo pendiente (**rojo si > S/ 0**, "A favor del cliente" si es negativo). Descuento, "Listo el" / "Entregado el" y Notas generales solo si existen. Si se reprogramó, "Prometido: …".
- **Atrasado** (decisión del usuario): fecha acordada anterior a hoy y sin `fecha_listo` (Doc 2, regla 6) → la fecha en rojo con "Atrasado". **Un cancelado no se marca.** La regla vive en `Encargo.atrasadoEl(hoy)` para el Dashboard (Sprint 5).
- Una sola consulta reactiva (`RepositorioEncargos.observar`, encargo + cliente con `LEFT JOIN`). Sin botones aún: "Cambiar estado" y las secciones llegan en Sprints 3-4, WhatsApp en el 5, Editar en el S2c.
- **Deuda menor:** `Encargo` (detalle) y `EncargoDeCliente` (fila de la ficha) son dos modelos de lectura; unificarlos en el Sprint 3, cuando `Encargo` sume trabajos y pagos.

## S2c — Editar encargo (`hoja_editar_encargo.dart`)

- **Una sola hoja** (decisión del usuario), desde el lápiz del Detalle: descripción, fecha de entrega (el mismo `SelectorFechaEntrega`), ubicación y notas generales. El cliente no se cambia (el contrato no lo acepta); el descuento llega con Trabajos (Sprint 3).
- **Reprogramar** mueve solo la acordada; la hoja avisa "La primera promesa (…) queda guardada" y la cabecera muestra "Prometido: …". Fecha pasada: el mismo aviso con "Guardar igual".
- **Entregado o cancelado no se reprograma** (decisión del usuario; el backend lo permitiría): la fecha se ve con el motivo, el resto sí se edita. El repositorio también lo impide (`ENCARGO_CERRADO`).
- `PATCH` solo con lo que cambió; ubicación o notas vacías viajan como `null` (se borran); sin cambios no encola nada. "Cambios guardados" al guardar.
- La etiqueta de estado pasó de la barra superior al inicio del cuerpo: con el lápiz al lado, el número del encargo quedaba sin espacio en 360dp (lo detectó el test de contraste).

## Sprint 3

| Bloque | Contenido | Estado |
|---|---|---|
| **S3a** | Cambios no guardados: resolver operaciones apartadas con "Descartar" (Doc 7 v1.2) | ✅ |
| **S3b1** | Trabajos (catálogo / personalizado) con recálculo local de total y saldo | ✅ |
| **S3b2** | Descuento en "Editar encargo", validado contra la suma de trabajos | ✅ |
| **S3c** | Pagos (S3c1 backend `GET /origenes-pago` + Docs 5/7; S3c2 app) | ✅ |
| **S3d1** | Objetos recibidos (sin foto: llega con Fotografías, Doc 11 v1.3) | ✅ |
| **S3d2** | Vínculo trabajo → objeto y Trabajos agrupados por objeto | ✅ |

Estado del encargo ("Cambiar estado") va en el Sprint 4.

## S3a — Cambios no guardados (`lib/shared/sync/descarte.dart`, `lib/features/sincronizacion/`)

- **Decisión del usuario: solo "Descartar"** (reevaluable tras la beta; "Corregir" sería Fase 2). Lo rechazado por el servidor aparece en **Más → "Cambios no guardados (n)"** (solo si hay alguno, nunca un banner) y como `Aviso` en el Detalle del encargo afectado. Cada uno dice qué se intentó ("Editar encargo · #47 · Ana García") y el motivo del servidor.
- **"Descartar"** (con confirmación) pide **primero** la versión actual al servidor y después, en una transacción, borra la operación y las posteriores sobre la misma fila (y las de sus hijos si era un alta) y deja la fila como en el servidor. Hace falta pedirla: la bajada delta no volvería a traer una fila que no cambió. `404` = alta que nunca existió → se borra la fila local. **Sin conexión no toca nada** y lo explica.
- Cómo se recupera cada recurso: `GET /clientes/{id}`; servicios recorre `GET /servicios?incluir_inactivos=true` (no hay GET por id); `GET /encargos/{id}` trae el agregado entero: encargo e hijos quedan como en el servidor (se le inyecta el `encargo_id` que el detalle omite), y los hijos locales que el servidor ya no tiene se borran. **Las filas con otras operaciones aún en cola no se pisan** (lo local pendiente gana).
- **Cada módulo nuevo registra sus tipos en `tiposDeOperacion`** (texto humano + recurso + si es alta); un test verifica que coincidan con los que encolan las features.
- `flujo_sesion_test` pasó a `testWidgetsConBase`: el menú "Más" ahora lee la base.

## S3b1 — Trabajos (`lib/features/encargos/`, `lib/shared/sync/recalculo.dart`)

- Sección **"Trabajos"** en el Detalle (apilada, Doc 6), con el chip "Catálogo". **"Agregar trabajo"** abre una hoja con dos vías: **Del catálogo** (por defecto si hay servicios activos; buscador y un toque agrega) o **Personalizado** (descripción + precio; S/ 0 vale). Tocar una fila abre "Editar trabajo": en uno del catálogo el **precio queda fijo** y la descripción sí se edita (decisión del usuario); "Eliminar trabajo" con confirmación.
- **Entregado o cancelado: los trabajos se ven pero no se cambian** (decisión del usuario; el backend lo permitiría). El repositorio lo comprueba contra la fila (`ENCARGO_CERRADO`), no solo la UI.
- **Recálculo local** en la misma transacción que la escritura y el Outbox: `TotalesEncargo.calcular` replica `Encargo.recalcular()` del backend (descuento ajustado a la suma, total = suma − descuento, saldo = total − pagos, en céntimos). Al catálogo viaja solo `{id, servicio_id}`; el servidor copia igual.
- Eliminar borra también los materiales del trabajo (la cascada del backend). Tipos `crear_trabajo` / `editar_trabajo` / `eliminar_trabajo` registrados en `tiposDeOperacion`; el **Descarte recalcula** los totales del encargo después de restaurar el agregado (cuenta los hijos propios aún sin subir).
- **Subida: un `DELETE` con `404` sale de la cola como hecho** (ya no existe, por ejemplo lo borró otro teléfono), en vez de quedar en "Cambios no guardados".
- `CampoPrecio` y `textoEditable` pasan a `shared/presentation/widgets/` (los usa también la hoja del catálogo).
- **Deuda menor:** si llega por `/sync` un trabajo de otro teléfono mientras este encargo tiene una operación propia en cola, el total local no lo cuenta hasta la siguiente sincronización tras subir.

## S3b2 — Descuento (`hoja_editar_encargo.dart`, `RepositorioEncargos.editar`)

- Campo **"Descuento (opcional)"** en "Editar encargo", con "Suma de trabajos: S/ 33.00 · Total: S/ 30.00" al ritmo de lo que se escribe. Mayor que la suma → se marca al instante con el mensaje del backend (`DESCUENTO_INVALIDO`) y no se guarda. Vacío = S/ 0 (quita el descuento; viaja `descuento: 0`).
- **Entregado o cancelado: el descuento se ve fijo con el motivo** (decisión del usuario, igual que la fecha). **Sin trabajos** no hay campo: "Agrega trabajos para poder aplicar un descuento." (decisión del usuario).
- El repositorio **vuelve a validar contra la suma de trabajos en Drift dentro de la transacción** (no contra lo que mostraba la pantalla), escribe el descuento y llama a `recalcularTotales`; viaja en el mismo `PATCH` que lo demás, solo si cambió.
- `CampoPrecio` acepta etiqueta, ayuda y `alCambiar`.

## S3c — Pagos (`lib/features/encargos/`, `lib/shared/sync/origenes_pago.dart`)

- **Orígenes de pago** (decisión del usuario: endpoint, no ids fijos): tabla Drift `origenes_pago` fuera de `/sync`, bajada de `GET /origenes-pago` (backend, Doc 5 v1.6) al final de la **primera vuelta con éxito de cada arranque** y en cualquier vuelta mientras esté vacía. Se reemplaza entera; guarda los desactivados para nombrar pagos viejos. Si falla, la vuelta cuenta como completa (Doc 7 v1.3). Se conserva en el `410` y se borra al cerrar sesión.
- **Esquema editado en el lugar**: aún no hay release publicado, así que `schemaVersion` sigue en 1 (ver `base_datos.dart`). Desde el primer build en Google Play, una tabla nueva es una migración.
- Sección **"Pagos"** en el Detalle, debajo de Trabajos: "22 oct · Yape · Adelanto  S/ 100.00". Un pago no se edita (sin `PATCH`): **tocarlo ofrece eliminarlo**, con confirmación; el saldo vuelve a subir.
- Hoja **"Registrar pago"**: monto con atajo **"Saldo completo (S/ X)"**, medio de pago en chips **sin ninguno marcado** (un valor por defecto se aceptaría sin mirar y ensuciaría la Caja), tipo Adelanto/Pago **propuesto según el estado** (Adelanto antes de LISTO, Pago desde LISTO; decisión del usuario) y la fecha del teléfono solo mostrada ("Hoy, 22 oct"). Sin catálogo bajado: "Necesitas conexión una vez para cargar los medios de pago."
- **Entregado: sí se cobra** (se entrega fiado, Doc 2 invariante 10); **cancelado: los pagos solo se ven** (decisión del usuario). El repositorio lo comprueba contra la fila (`ENCARGO_CERRADO`), y también el origen activo (`ORIGEN_PAGO_INVALIDO`) y el monto > 0 (`PAGO_MONTO_INVALIDO`). Un pago mayor que el saldo **se registra** y queda a favor del cliente (PRD 5).
- `fecha` = día en Lima del reloj del teléfono, enviada en el `POST` (Doc 5 v1.4). Tipos `registrar_pago` / `eliminar_pago` registrados en `tiposDeOperacion`; el Descarte ya restauraba los pagos con `GET /encargos/{id}`.

## S3d1 — Objetos recibidos (`lib/features/encargos/`)

- Sección **"Objetos recibidos"** en el Detalle, **antes de Trabajos** (orden del Doc 6). Cada fila dice cuántos trabajos tiene ("2 trabajos", "sin trabajos"). Sin objetos: "Ningún objeto registrado.", sin tono de error (Caso 3).
- Una sola hoja (`HojaObjeto`) para **agregar** (solo descripción) y para **editar/eliminar**. Eliminar avisa: "Sus 2 trabajos se quedan, sin objeto."
- **Cascada local igual a la del backend**: eliminar un objeto borra sus fotos y desvincula sus trabajos (no los borra), en la misma transacción. Sin recálculo: un objeto no tiene precio.
- **Entregado o cancelado: los objetos se ven pero no se cambian** (decisión del usuario, misma regla que Trabajos), comprobado en el repositorio (`ENCARGO_CERRADO`).
- **Sin foto** (decisión del usuario): la foto del objeto llega con Fotografías en el Sprint 7 (Doc 11 v1.3).
- Tipos `crear_objeto` / `editar_objeto` / `eliminar_objeto` en `tiposDeOperacion`. `Trabajo` ahora lleva `objetoRecibidoId` (lo usa el conteo; el vínculo editable es el S3d2). `leerEstadoLocal` (`data/estado_local.dart`) reemplaza la consulta repetida en Trabajos, Pagos y Objetos.

## S3d2 — Vínculo trabajo → objeto (`selector_objeto.dart`, `seccion_trabajos.dart`)

- **"¿Para qué objeto?"** (`SelectorObjeto`: "Ninguno" + los objetos) en Agregar trabajo y en Editar trabajo, **solo si el encargo tiene objetos**. Al agregar, "Ninguno" por defecto; al editar, el objeto actual.
- `RepositorioTrabajos`: `objeto_recibido_id` viaja en el `POST` solo si hay objeto, y en el `PATCH` solo si cambió (`null` lo quita). En `editar`, omitir `objetoId` deja el vínculo como está. El objeto debe estar en el mismo encargo (`OBJETO_NO_EN_ENCARGO`, como el backend). El dinero no cambia.
- **Trabajos agrupados por objeto** (`agruparPorObjeto`): un subtítulo por objeto con trabajos, en el orden de Objetos recibidos, y **"Sin objeto"** al final. Sin vínculos, la lista se ve igual que antes.
- **Un vínculo a un objeto que ya no está cuenta como "Sin objeto"** (opción a, decisión del usuario): es lo que hará el servidor al sincronizar.
