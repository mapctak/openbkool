# Detección de rodillos ANT en OpenBkool

## Punto de partida y alcance

El usuario ha confirmado en su Samsung Galaxy S20 **SM-G980F**, Android 13,
ANTLib 4.16.0, ANT Radio Service 4.18.00 y ANT+ Plugins Service 3.9.0:
hardware ANT integrado, ocho canales libres y reserva/liberación correcta sin
errores. Esa prueba física de capacidad ya está completada; **todavía no demuestra
que se haya detectado el rodillo con esta nueva pantalla**.

Se añade «Buscar rodillos ANT», manteniendo el diagnóstico BLE y el diagnóstico
ANT de capacidades. Las observaciones se basan en
[protocolo_bkool.md](protocolo_bkool.md), las clases descompiladas de Bkool Mobile
1.12.0 y los SDK oficiales. No se implementan pendiente, resistencia, ERG,
bloqueo, actualizaciones de firmware ni páginas de control.

## Funcionamiento de la pantalla

Hay tres opciones: búsqueda secuencial, solo FE-C o solo Bkool V1 público.
Navegar a la pantalla no inicia acceso a radio. Al pulsar iniciar:

1. **FE-C / Fitness Equipment:** `MultiDeviceSearch` busca durante 30 segundos,
   exclusivamente con `DeviceType.FITNESS_EQUIPMENT` (17 / `0x11`).
2. Cierra esa búsqueda antes de escuchar información de los equipos encontrados.
   Para cada ID, uno cada vez, usa `AntPlusFitnessEquipmentPcc.requestNewOpenAccess`
   por número de dispositivo. Hay hasta 8 segundos para obtener acceso y, si lo
   obtiene, hasta 20 segundos adicionales de suscripción informativa.
   Una desconexión o error queda registrado y pasa al siguiente ID.
3. Cierra cada `PccReleaseHandle` antes de comenzar el siguiente. Se suscribe a
   fabricante/modelo y producto, sin llamar a `requestCommonDataPage`, métodos
   `requestSet…`, calibración ni acceso de sesión personal.
4. **Bkool V1:** al finalizar todos los equipos FE-C, enlaza con Radio Service y
   abre un canal público de recepción en segundo plano durante 40 segundos.
   No empieza esta fase si no puede confirmar la limpieza de la anterior.
5. Finaliza y libera los recursos. Si no se ha recibido información de fabricante
   o modelo, el equipo queda identificado por su ID/tipo, sin inventar un modelo.

Con N equipos FE-C, la duración secuencial puede llegar aproximadamente a
30 + N×(8+20) + 40 segundos, más inicialización y cierre. Se puede detener en
cualquier momento. La opción solo V1 permite investigarlo sin esperar al perfil
FE-C; la opción solo FE-C no abre una búsqueda propietaria después.

La vista muestra estado/fase, ID, tipo, protocolo, tipo de transmisión cuando se
conoce, fabricante, modelo, hardware/software y serial si se reciben. Destaca
Smart Pro v1/v2 con el grado de confirmación correspondiente.

## Fuentes y procedencia verificables

Rutas Java relativas a `research/jadx/sources/` (salida local excluida de Git):

| Evidencia | Ruta y método |
|---|---|
| Alternancia ANT+ / V1 / V2 | `com/bkool/sensors/tech/ant/BkoolSensorAntPlus.java`, `startProcedureScanning()` |
| Búsqueda oficial ANT+ | `com/bkool/sensors/tech/ant/BkoolSensorAntWrapper.java`, `startScanningAntPlus()` |
| Canales público/privado y background scan | mismo archivo, `assignChannel()` |
| Extracción de ID extendido | mismo archivo, `ScanningChannelEventHandler.onReceiveMessage()` |
| Modelos 22 y 24, páginas recibidas | `com/bkool/sensors/tech/ant/devices/TrainerBkoolPro1.java`, `onReceiveMessage()` |
| FE-C abierto y suscripciones | `com/bkool/sensors/tech/ant/devices/TrainerFEC.java`, `connectImpl()`, `subscribe()` |
| Constante de red V2 y parámetros | `com/bkool/sensors/beans/ConstantesSensors.java`, incluido inicializador de `ANT_BKOOL2_NETWORK_PRIVATE` |
| V2 independiente de modelo físico | `TrainerBkoolPro2.java` y `crearSensorDeviceAnt()` del wrapper |

Las ambigüedades del Java reestructurado de `assignChannel()` se contrastaron
previamente con la salida fallback de JADX; véase el informe de protocolo.
No se copia el código de control de esos dispositivos a OpenBkool.

SDK oficial fijado al commit `0e8cea714a231fb9565170d4ed01eafa868f9798` de
[ANT-Android-SDKs](https://github.com/ant-wireless/ANT-Android-SDKs/tree/0e8cea714a231fb9565170d4ed01eafa868f9798):
ANTLib 4.16.0, ANT+ PluginLib 3.9.0 y FIT 21.105.00. Los artefactos oficiales,
sin modificaciones, y sus SHA-256 se documentan en
[android/app/libs/README.md](../android/app/libs/README.md).
Se consultaron los Javadoc oficiales del mismo commit y se comprobaron las firmas
con `javap`, sin depender de la versión antigua del SDK dentro de la APK Bkool.

## Parámetros V1 implementados

| Parámetro | Valor / motivación |
|---|---|
| Red | `PredefinedNetwork.PUBLIC`, como Bkool V1 |
| RF | 40, argumento de `setRfFrequency()` |
| Período nominal | 32768 unidades de 1/32768 s; no se usa para inferir el ritmo real de todos los anuncios |
| Tipo de canal | `ChannelType.SLAVE_RECEIVE_ONLY`, **no** esclavo bidireccional |
| Asignación extendida | `enableBackgroundScanning()`; requiere esa capacidad de la radio |
| ID | `ChannelId(0,0,0)`: comodines de número, tipo y transmisión |
| Identificador extendido | habilita `LibConfig.enableChannelIdOutput` si hace falta |
| Tipo candidato Bkool | 112 (`0x70`), conservando también los otros tipos públicos observados |
| Ventana de la app | 40 s después de abrir; plazo inicial de enlace/inicialización 8 s |
| Timeouts de radio | No se llama a `setSearchTimeout`: el SDK lo prohíbe en background; ventana propia de 40 s |

La asignación de escaneo del wrapper original es receive-only/background. La
clase de conexión `TrainerBkoolPro1` utiliza también parámetros de control
bidireccional; **no se reproduce esa parte**. El escaneo original no necesita
filtrar por nombre ni por UUID, conceptos de BLE que no identifican un canal ANT.

**Corrección del fallo `INVALID_REQUEST`:** la versión anterior llamaba a
`setSearchTimeout(MAX, DISABLED)` después de asignar background scanning. El
Javadoc de ANTLib 4.16.0 prohíbe las dos sobrecargas de `setSearchTimeout` en ese
modo: el servicio las rechaza con `INVALID_REQUEST`. Se ha retirado esa llamada;
se registra explícitamente como operación omitida con su motivo. Se mantiene el
límite de 40 s de la aplicación y no se sustituye por otro timeout arbitrario.

El período continúa configurándose con **32768**: el ejemplo oficial background
scan también configura ese mismo período. RF sigue en **40**, PUBLIC y el tipo
receive-only no cambian. La comparación exacta y los límites de lo confirmado
figuran en la sección de investigación del fallo al final de este documento.

Si falta soporte de background scan o no hay canales libres, se registra el fallo;
no se cambia silenciosamente a un canal transmisor ni se reclama la interfaz
legacy ocupada. La inicialización del servicio/canales se vuelve a consultar en
intervalos de 500 ms dentro del plazo de enlace, no indefinidamente.

## Mensajes y páginas de identificación

### ANT público V1: bytes recibidos

Se registra ID de mensaje SDK, tipo, contenido hexadecimal y, cuando es posible,
ID del dispositivo y payload de ocho bytes. `messageHex` contiene el ID del
mensaje seguido del contenido entregado por ANTLib; **no** incluye sincronismo ni
checksum de un transporte serie que el SDK no entrega.

El parser admite mensajes broadcast (`0x4E`) y acknowledged recibidos (`0x4F`),
con contenido de al menos 14 bytes y bandera extendida de identidad `0x80`:
canal, payload de ocho bytes, flags y Channel ID extendido. El número se lee
little endian; tipo y transmisión se conservan. Admite datos adicionales de RSSI
o timestamp sin depender de una longitud hexadecimal exacta, a diferencia del
parser antiguo que solo aceptaba ciertas longitudes.

Si faltan identidad extendida o bytes suficientes, el mensaje se conserva en hex
**sin atribuirlo a un dispositivo supuesto**. Otros tipos de mensaje se conservan,
pero no se interpretan como páginas de identificación. No se reconstruyen IDs a
partir de nombres ni se mezcla información de diferentes tipos/transmisiones.

Se interpretan, exclusivamente para payloads de ocho bytes:

| Página | Campos |
|---|---|
| `0x50` / 80, fabricante | hardware en byte 3; fabricante LE16 en 4–5; modelo LE16 en 6–7 |
| `0x51` / 81, producto | software suplementario en 2; principal en 3; serial LE32 en 4–7 |

Los valores desconocidos `FF`/`FFFF`/`FFFFFFFF` se tratan como desconocidos donde
corresponde. Las demás páginas siguen visibles en hexadecimal sin una
interpretación no demostrada por este análisis.

### FE-C: eventos oficiales, sin bytes inventados

`MultiDeviceSearch` expone número/tipo y nombre de presentación; no expone el tipo
de transmisión completo ni las tramas ANT crudas. Las suscripciones
`subscribeManufacturerIdentificationEvent` y `subscribeProductInformationEvent`
entregan los campos interpretados por el servicio. Se conserva la procedencia
`SDK_MANUFACTURER_EVENT`, el timestamp estimado y las flags del evento, que pueden
indicar datos previos/caché. La hora de recepción por la app no se presenta como
hora exacta de radio.

**Limitación explícita:** esta pantalla muestra hexadecimal real para V1; para
FE-C muestra eventos interpretados del SDK. No convierte esos eventos a una
supuesta trama recibida ni utiliza claves de red para sortear esa limitación.
La información común puede tardar más de 20 segundos o no emitirse; una espera
sin modelo no descarta el rodillo. No se solicitan páginas activamente para forzar
una respuesta. El servicio externo puede implementar su propia gestión de radio;
lo confirmado aquí es que OpenBkool no llama a sus APIs de control.

Tipo 17 es Fitness Equipment; por sí solo no certifica que el equipo admita todos
los comandos FE-C. Los eventos de estado pueden aportar el tipo de equipamiento.
No se prueba ninguna capacidad de control en esta fase.

### Reconocimiento Bkool sin falsos positivos evidentes

El FIT SDK oficial define `Manufacturer.BKOOL = 67`, contrastado con
`javap -constants`. Con fabricante 67 y modelo 22 se reconoce Smart Pro v1;
con fabricante 67 y modelo 24, Smart Pro v2. Si hay modelo 22/24 pero falta
fabricante, se muestra una pista compatible, sin `bkoolConfirmed=true`. Si el
fabricante es otro, no se atribuye ese número de modelo a Bkool.

El número de modelo **no identifica la red**. Un Smart Pro v2 (modelo 24) recibido
en PUBLIC no significa que se haya utilizado el protocolo privado Bkool V2.
La clave de resultados V1 incluye número, tipo y transmisión; la clave FE-C usa
el número que expone el SDK. No se fusionan automáticamente dispositivos de
ambos protocolos ni se garantiza resolver colisiones de número en FE-C.

## Serialización de operaciones, parada y limpieza

`AntRadioCoordinator` impide simultanear el diagnóstico de reserva con la nueva
búsqueda. La búsqueda usa un `HandlerThread` serie con `Looper` y tokens de fase: eventos/timers de
una fase terminada se ignoran. PluginLib 3.9.0 construye `Handler()` al pedir
acceso; se verificó su bytecode y se proporciona un Looper real, evitando usar
un ejecutor Java sin Looper que fallaría en el teléfono aunque compilase.
Se cierra MultiDeviceSearch antes de cada acceso
informativo, y cada acceso antes del siguiente o antes de V1.

Al detener, volver de la pantalla, cancelar la suscripción de eventos, pasar la
actividad Android a segundo plano o limpiar el motor, se solicita la finalización.
La vista espera confirmación nativa antes de volver si hay una búsqueda activa.
Una llamada Binder bloqueada puede retrasar la parada; si Dart no recibe
confirmación en 20 s, no afirma que se hayan liberado recursos ni habilita otra
búsqueda como si no quedara nada en uso.

Para V1 se restaura el ajuste de ID extendido si se cambió, preservando las otras
flags actuales. Se solicita cierre y se espera el evento `CHANNEL_CLOSED` hasta
3 s antes de desasignar; el Javadoc explica que `close()` por sí solo no espera
el cierre efectivo. **Siempre** se intenta `release()` y desvincular el servicio,
incluso si falla una acción anterior. Las callbacks ANT pueden señalizar el cierre
mientras el ejecutor espera, sin bloquear el hilo de interfaz.

Errores de limpieza dejan `resourcesReleased=false`, abortan la secuencia y
mantienen bloqueadas las nuevas operaciones ANT en ese proceso. Se muestra el
error en lugar de asegurar una liberación no comprobada; puede ser necesario
forzar la detención/reabrir la app. La recuperación de radio y fallos de servicio
se registran; no hay reconexiones automáticas infinitas.

El permiso/visibilidad de los servicios ANT se conserva mediante los manifiestos
oficiales y las consultas explícitas existentes. Los errores de seguridad,
dependencias, canal ocupado y desconexión se muestran sin pedir permisos Bluetooth
como sustituto de acceso ANT. No se cambian los permisos ni los métodos BLE.

Las librerías pueden modificar ajustes compartidos de la radio. Evita otras apps
ANT simultáneas durante esta prueba; la exclusión garantiza operaciones de
OpenBkool, no un bloqueo global de todas las aplicaciones del teléfono.

## Bkool V2: investigación y propuesta, no implementación

Hechos verificados:

- El código original adquiere canales V2 con
  `acquireChannelOnPrivateNetwork(context, NetworkKey(...), capabilities)`.
- `ConstantesSensors.ANT_BKOOL2_NETWORK_PRIVATE` contiene 16 bytes incorporados
  en la APK; véase el valor y la ruta en el informe estático. No se obtiene de un
  login ni de una descarga en ese controlador.
- El Javadoc **ANTLib 4.16.0 `NetworkKey`** confirma que Radio Service acepta una
  clave larga de **16 bytes**, y valida su longitud al recibirla. Esto resuelve
  la duda del informe inicial sobre si debía reducirse a ocho bytes: no debe.
- El resto de la búsqueda original usa RF 40, comodines, background scanning e
  identidad extendida. Los modelos físicos no sustituyen la selección de red.

Una futura detección V2 puede implementarse **sin instanciar
`TrainerBkoolPro2` ni llamar a `genericRequest`**:

1. Cerrar FE-C/V1 y verificar la limpieza mediante el mismo coordinador.
2. Crear `NetworkKey` con los 16 bytes documentados y adquirir un canal privado
   que soporte background scanning. Registrar `SERVICE_INITIALIZING`,
   `NETWORK_NOT_AVAILABLE`, `NO_ADAPTERS_EXIST` y demás fallos de capacidad/red.
3. Asignar exclusivamente `SLAVE_RECEIVE_ONLY` con background scanning, ID
   comodín, RF 40 y el período nominal documentado, con ventana limitada.
4. Habilitar identidad extendida conservando la configuración anterior; recibir
   y analizar `0x50/0x51` igual que V1, distinguiendo `protocol=BKOOL_V2_PRIVATE`.
5. Restaurar configuración, cerrar/desasignar/liberar y desvincular el servicio.
   No enviar `Block`, `RequestBlocked`, UserConfig, control ni entrada a DFU.

Esto es una propuesta basada en código y documentación, **no una prueba de que
el firmware del rodillo concreto acepte esa red**. No se han validado la clave con
la radio ni las capacidades privadas del S20. No se ha implementado un selector
V2, no se construye `NetworkKey` en el código nuevo y no hay llamadas de adquisición
privada. Una búsqueda V1 vacía no permite descartar una unidad solo V2.

## JSON y límites de almacenamiento

El JSON existente añade `antTrainerSearch`, manteniendo `devices`/GATT BLE y
`antDiagnostics`. Incluye modo, estado, fase, fechas, parámetros efectivos,
dispositivos, eventos, mensajes hex, contadores de descarte y resultado de limpieza.
Exportar desde cualquiera de las pantallas copia el mismo informe combinado al
portapapeles. Exportar no inicia la radio ni envía datos a servidores.

Cada inicio crea una nueva sesión de búsqueda; exporta antes de iniciar otra si
quieres conservar la anterior. Los otros diagnósticos no se borran. Se conserva
un máximo de **2000 mensajes hexadecimales** recientes por sesión, con número
de descartados explícito. Los eventos de diagnóstico y todas las operaciones ANT
se conservan completos durante la sesión, sin el anterior límite de 500 eventos. La pantalla muestra los últimos 100 mensajes; el JSON
incluye todos los conservados. Los dispositivos se acumulan por identidad dentro
de esa sesión. Al cerrar la app no se persisten estos datos automáticamente.

## Resultados, pruebas y comprobación física pendiente

La radio funcional del S20 es un resultado confirmado por el usuario. En esta
sesión de implementación, `adb devices -l` no devuelve teléfonos conectados: no
se ha instalado/ejecutado automáticamente esta APK en el S20 ni se ha observado
el rodillo. No se han enviado páginas de control ni modificado firmware.

Resultados automatizados verificados:

- `flutter analyze`: sin incidencias.
- `flutter test`: once pruebas correctas, incluidas las regresiones de BLE y
  diagnóstico ANT, búsqueda, navegación, exportación y la operación V1 fallida.
- `./gradlew :app:testDebugUnitTest`: quince pruebas Kotlin correctas: cuatro de
  acceso a radio, seis de parser/limpieza/exclusión y cinco de configuración e instrumentación.
- `flutter build apk --debug`: APK final generada correctamente en
  `build/app/outputs/flutter-apk/app-debug.apk`. Se mantienen avisos no bloqueantes
  de Gradle/Kotlin y acceso nativo de Java.

La verificación estática del código Kotlin de la app no encuentra llamadas a
adquisición privada ni a APIs de envío/control (`requestSet…`, `setBroadcastData`,
`startSendAcknowledgedData`, burst ni DFU). El uso de esas clases dentro de los
binarios oficiales no implica que la app las invoque.

Pruebas automatizadas añadidas:

- parser de tramas con ID extendido y datos extra de RSSI;
- rechazo de identidad truncada, ausente, mensajes que no son datos y número 0;
- páginas 80/81, little endian, serial sin signo, fabricante 67 y modelos 22/24;
- rechazo de atribución Bkool si el modelo pertenece a otro fabricante;
- limpieza de todos los recursos aunque falle una acción y exclusión entre dueños;
- navegación, parada al volver, rechazo de operación ocupada y exportación conjunta
  mediante MethodChannel/EventChannel simulados;
- regresiones del diagnóstico BLE y del diagnóstico ANT de capacidades.

Los tests no sustituyen una prueba de radio: el enlace Binder, el soporte real de
background scan, la recepción efectiva y el tiempo de liberación en el S20 siguen
pendientes de ejecutar esta versión en el teléfono.

Para probar: cerrar otras apps ANT, encender el rodillo y usar primero la opción
secuencial. Exportar al finalizar, incluso si no hay dispositivos. Comparar otra
búsqueda con el rodillo apagado ayuda a identificar qué IDs aparecen con él.
Si FE-C no encuentra nada pero V1 sí, conservar ID completo, tipo, fabricante,
modelo y hex. Si ambas quedan vacías, revisar los errores antes de concluir que
el rodillo solo usa V2, está averiado o necesita firmware; no se deduce ninguna de
esas conclusiones de una búsqueda vacía aislada.

Comandos de reproducción:

```sh
flutter analyze
flutter test
cd android
./gradlew :app:testDebugUnitTest
cd ..
flutter build apk --debug
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`.


## Investigación de `INVALID_REQUEST` en V1 (13 de noviembre de 2026)

### Observación del usuario y grado de certeza

En el S20, FE-C inicia y no recibe equipos en 30 s; V1 devuelve
`AntCommandFailedException` / `INVALID_REQUEST` aproximadamente 50 ms después
de empezar. La traza anterior solo indicaba `V1 configure` o `callback`, de modo
que **no permite saber qué llamada fue la primera que falló en ese teléfono**.
En esta sesión no hay teléfono conectado por ADB, por lo que no se ha reproducido
la respuesta real ni se afirma haber detectado ya el rodillo.

**Defecto confirmado por la documentación:** la configuración anterior invocaba
`setSearchTimeout(LowPrioritySearchTimeout.MAX, HighPrioritySearchTimeout.DISABLED)`
en un canal background. El Javadoc de las dos sobrecargas explica que no son
válidas en ese modo y que producen `AntCommandFailureReason.INVALID_REQUEST`.
Es una causa documentada de ese error presente en nuestro código, ahora eliminada.
Si el teléfono rechazaba una operación anterior (por ejemplo asignación o RF),
solo la nueva traza permite confirmar ese primer fallo. La latencia de 50 ms por
sí sola no identifica una operación ni un fallo de firmware.

### Comparación con Bkool y ejemplo oficial

| Aspecto | Bkool Mobile 1.12.0 / SDK oficial | OpenBkool corregido |
|---|---|---|
| Rama de búsqueda | `assignChannel(..., z=true)` del wrapper solicita background scanning | Misma capacidad requerida; consulta número de canales compatibles |
| Tipo de asignación | Bkool: `SLAVE_RECEIVE_ONLY` con `ExtendedAssignment.enableBackgroundScanning()` | Igual; no se sustituye por canal transmisor o bidireccional |
| Ejemplo oficial | El ejemplo usa `BIDIRECTIONAL_SLAVE`; es un ejemplo genérico, no el controlador Bkool | Se conserva el receive-only documentado en Bkool |
| Identidad | Comodines en búsqueda y salida extendida de Channel ID | Comodines `(0,0,0)` y salida extendida preservando otras flags |
| Período | La rama Bkool background no lo configura; la conexión `z=false` sí; el ejemplo oficial background configura **32768** | Se conserva **32768**, sin atribuirle el error sin evidencia |
| RF y red | Bkool V1: **40 / PUBLIC**; el ejemplo genérico usa RF 77 | Se conserva **40 / PUBLIC**; no se copian 77 ni la RF reservada ANT+ 57 |
| Timeouts de búsqueda | La rama Bkool `z=true` no los configura; el ejemplo background tampoco | Se omite `setSearchTimeout`, prohibido por el contrato de la API en este modo |
| Background ya ocupado | El ejemplo consulta `getBackgroundScanState` y evita abrir otro activo | Consulta antes de asignar y antes de abrir; si está activo, informa y aborta |

Evidencias concretas:

- `research/jadx/sources/com/bkool/sensors/tech/ant/BkoolSensorAntWrapper.java`,
  `assignChannel()`: `setPeriod` y `setSearchTimeout` dentro de `if (!z)`;
  la rama de escaneo utiliza asignación extendida. Contraste con el fallback
  indicado en el informe estático para evitar interpretar mal el `return null`.
- `TrainerBkoolPro1.java:connect()`: pasa `false` para `z`, por lo que es la
  conexión del controlador y **no** la receta de búsqueda en segundo plano.
- [ChannelController.java del ejemplo oficial fijado al commit usado](https://github.com/ant-wireless/ANT-Android-SDKs/blob/0e8cea714a231fb9565170d4ed01eafa868f9798/ANT_Android_SDK/Sample_Applications/Sample_BackgroundScan/Source/app/src/main/java/com/dsi/ant/sample/backgroundscan/ChannelController.java):
  constante de período en línea 48; estado background en 75–77;
  `configureBackgroundScanningChannel()` en 85–130 configura asignación, LibConfig,
  ID, período y RF, sin `setSearchTimeout`; apertura en 133–155.
- [Javadoc oficial 4.16.0](https://github.com/ant-wireless/ANT-Android-SDKs/blob/0e8cea714a231fb9565170d4ed01eafa868f9798/ANT_Android_SDK/API/Android_ANTLib_Javadoc_4-16-0.zip),
  `com/dsi/ant/channel/AntChannel.html`, ambas secciones `setSearchTimeout`:
  prohibición de esas llamadas en background y motivo `INVALID_REQUEST`.
  `setRfFrequency` exige verificar el rango de `Capabilities` y reserva RF 57
  para Plugin API; no justifica cambiar nuestra RF 40 por otra.

### Instrumentación y comprobación de capacidades

Cada operación se ejecuta mediante `AntOperationTrace`, con identificador
secuencial, nombre estable, argumentos, timestamp UTC, estado
`started/succeeded/failed/skipped` y duración monotónica en ms. Incluye:

- enlace y creación de la interfaz de servicio;
- acceso a proveedor, interfaz legacy, canales libres y canales con background;
- información de adaptadores: ID, integrado/externo, versión, background scanning,
  extended assign, rango RF, RSSI y otras capacidades;
- reserva PUBLIC y capacidades del canal realmente reservado;
- registro del handler, validación de capacidades, estado background;
- asignación receive-only/extendida, ID, período 32768, RF 40;
- omisión justificada de timeouts, lectura/configuración de LibConfig y apertura;
- restauración, cierre, espera de `CHANNEL_CLOSED`, desasignación, liberación y
  desvinculación, además del cierre de los recursos FE-C entre fases.

Una capacidad anunciada por otro adaptador no se da por disponible en el canal
seleccionado: se valida de nuevo después de reservar. Si falta background scanning,
extended assign, canales compatibles o RF 40 no pertenece al rango real, se
informa y no se intenta la asignación/configuración incompatible. No hay fallback
silencioso a otro tipo, RF o red. El proveedor de adaptadores, si la versión del
servicio no lo soporta, se marca omitido; se mantienen obligatorias las
comprobaciones del canal real. Se sigue respetando la interfaz legacy ocupada.

Las excepciones conservan clase completa, mensaje, causas y stack trace. Para
`AntCommandFailedException` se consultan, cuando el SDK los aporta:
`failureReason`, código, `attemptedMessageType`, ID de mensaje intentado, mensaje
ANT y respuesta de canal en hexadecimal. Para `ChannelNotAvailableException`
se incluyen nombre y código del motivo. Un `INVALID_REQUEST` rechazado por el
servicio puede no llevar respuesta de hardware; esos campos quedan nulos,
no se inventan. Un error al enriquecer el diagnóstico no sustituye la excepción
original.

### Qué revisar en la próxima prueba real

La pantalla presenta «Operación V1 fallida» y una lista desplegable de operaciones.
El JSON `antTrainerSearch` añade:

- `operationEvents`: **todas** las operaciones de la sesión, sin truncamiento,
  incluidas las fallidas y las omitidas;
- `v1Failure.operation` y `v1Failure.operationTrace`: operación causante antes de
  que la limpieza pueda fallar también;
- `v1Failure.error`: detalles originales de esa excepción;
- `adapterCapabilities` y `channelCapabilities`: capacidades observadas;
- `lastOperation` y `firstOperationFailure`: contexto adicional. El primero puede
  corresponder al cierre; un primer fallo puede ser una inicialización recuperada.
- `parameters.v1RadioTimeoutsApplied=false`: confirma que la llamada prohibida
  ya no se ejecuta. La ventana de la app sigue siendo 40 s.

Iniciar la secuencia habitual y exportar **antes de iniciar otra sesión**. Si aún
falla, revisar primero `v1Failure`, después los eventos de esa operación y las
capacidades. El éxito en `v1.open` confirmará la apertura; no recibir tramas tras
ella es un resultado diferente del fallo de configuración. Cero equipos FE-C
no se atribuye a esta llamada, ya que se produce en una fase posterior V1.

### Validación de esta corrección

Validación final de la corrección: `flutter analyze` sin incidencias, once
pruebas Flutter correctas y quince pruebas Kotlin correctas.
`flutter build apk --debug` genera correctamente la APK actualizada en
`build/app/outputs/flutter-apk/app-debug.apk`. Las pruebas nuevas
usan un driver simulado para inyectar fallos en asignación, ID, período, RF y
apertura, verifican operación/argumentos/duración exactos, rechazo de capacidades
insuficientes antes de asignar, ausencia de llamadas de timeout y preservación
del fallo original si la limpieza también falla. La prueba Flutter comprueba
la presentación y exportación de estos datos. **No son una reproducción del
`INVALID_REQUEST` real del S20**.
