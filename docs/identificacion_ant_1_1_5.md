# Espera de identificación ANT — OpenBkool 1.1.5+8

Rama `feature/control-ant`. Se conserva el trabajo 1.1.4 existente. La validación
física aportada de 1.1.4 cubre segundo plano, parada, temporizador e indicador en
S20; esta versión de instrumentación aún necesita prueba en el teléfono.

## Resultado: solicitud explícita no habilitada

**No se ha encontrado evidencia suficiente de que BKOOL_V1_PUBLIC/modelo 22
admita solicitar la página 0x50.** Se conserva la recepción pasiva y no se añade
ninguna transmisión. Esto no prueba que el firmware sea incapaz de responder;
indica que no hay un procedimiento V1 suficientemente justificado para activarlo
bajo la restricción de no enviar comandos experimentales. No se promete una
reducción de 25–60 s con esta versión.

Existe el mecanismo ANT+ Common Page 70, número decimal 70/hexadecimal **0x46**,
«Request Data Page». La respuesta del administrador de THIS IS ANT documenta
su uso mediante mensajes acknowledged y advierte que el soporte depende del
fabricante. Esa documentación general no demuestra soporte del rodillo
propietario tipo 112 sobre PUBLIC. Véase [Requesting Data Pages, respuestas del
administrador del 17 y 18 de septiembre de 2012](https://www.thisisant.com/forum/viewthread/3593).
No se extrapola a este canal la restricción de número de canal expuesta allí
para el caso particular de escaneo continuo.

### Evidencias locales verificables

Consultar también [protocolo_bkool.md](protocolo_bkool.md).
Fuentes JADX originales excluidas de Git:

- `research/jadx/sources/com/bkool/sensors/tech/ant/devices/TrainerBkoolPro1.java`:
  `connect()`, líneas 179–197, asigna y abre el canal. No solicita una página
  de fabricante después de abrir. `onReceiveMessage()`, líneas 75–174, reconoce
  páginas 0x10/0x19/0x50 y extrae el modelo de esta última. No hay un caso de
  identificación 0x51 en ese controlador. El caso de modelo 22 lo llama
  «Bkool Smart Pro v1».
- En el mismo Pro1, `genericRequest()`, líneas 238–243, `Block` y
  `RequestBlocked` solo registran que no es necesaria esa petición; no construyen
  una trama de solicitud 0x50.
- `TrainerBkoolPro2.java`, líneas 252–253, sí construye una página 0x46 para
  `RequestBlocked`, con destino **0xF0**, no 0x50. Es otro controlador y red;
  no justifica reutilizarla cambiando bytes para Pro1.
- `BkoolSensorAntWrapper.java`, líneas 509–527, `openChannel()` llama `open()`;
  no añade una solicitud de información. `sendBroadcast()`, líneas 547–553,
  entrega los bytes recibidos a `setBroadcastData()`.
- `com/dsi/ant/channel/AntChannel.java`, líneas 195–219, `requestMessage()` y
  `requestChannelId()` consultan mensajes del adaptador. **No son peticiones de
  una página de datos 0x50 al rodillo.** La consulta actual de identidad de canal
  permanece; no sustituye fabricante/modelo.

Esta evidencia confirma el mecanismo general y la ausencia de una petición V1
en las rutas inspeccionadas, no la imposibilidad absoluta en todas las versiones
de firmware. Haría falta documentación del fabricante para Pro1 o una captura
verificable de una aplicación compatible que solicite 0x50 a ese modelo y obtenga
su respuesta. Con esa evidencia se podría diseñar una petición acotada y una
prueba física separada; no se deja un paquete candidato ni un interruptor oculto.

## Recepción y requisitos conservados

`decodeAntFrame` procesa broadcast/acknowledged con identidad extendida y ocho
bytes de datos. Se filtran el número, tipo y transmisión del dispositivo
seleccionado antes de procesar la información en entrenamiento.

`manufacturerPage()` en `AntSearchData.kt` mantiene:

| Página | Datos |
|---|---|
| 0x50 | Revisión HW en byte 3, fabricante little endian en 4–5, modelo en 6–7. |
| 0x51 | Revisión software en 2–3 y número de serie en 4–7; no certifica fabricante/modelo. |

Ejemplo 0x50 real previo: `50 FF FF FF 43 00 16 00`, fabricante 67, modelo 22.
La página 0x51 del S20 no sustituye esa información. Los campos 0x51 se agregan
al dispositivo sin borrar los campos 0x50 de la misma conexión.

`manualLink()` sigue leyendo fabricante y modelo de los dispositivos recibidos
en la **sesión actual**, además de verificar identidad exacta 30064/112/5,
canal abierto/dedicado, radio, señal y métricas recientes. Ningún hito temporal
ni perfil guardado se usa para conceder elegibilidad. Los tiempos no son una
nueva fuente de identificación.

La publicación habitual se agrupa unos 200 ms y el latido es de 1 s; no se añade
ninguna espera nueva antes de permitir activar. Sin una captura temporal actual
no se atribuye el intervalo observado de 25–60 s a un período fijo del firmware.
Que las páginas comunes sean menos frecuentes o se pierda una por radio es una
**hipótesis**, que los hitos/hexadecimales permitirán contrastar.

## Cambios de instrumentación

Nuevo `AntIdentificationTiming.kt`: componente pasivo por conexión, reloj
`SystemClock.elapsedRealtime`, sin transporte, persistencia ni capacidad de
habilitar el control. Cada hito se registra una sola vez en `events` con
`event=identification_milestone`, `details.milestone`, `elapsedMs` e identidad.
La sesión añade la hora UTC; el UUID está en el snapshot exportado.

Nuevo objeto JSON `identificationTiming` (`controlDiagnosticsVersion=4`):

| Campo | Significado |
|---|---|
| `elapsedMs` | Tiempo desde crear esta conexión; queda congelado al finalizar. |
| `milestonesMs.channelOpen` | Retorno correcto de apertura del canal. |
| `channelOpenApiDurationMs` | Duración de la llamada `open()` solamente, sin vinculación/configuración. |
| `milestonesMs.firstIdentityFrame` | Primera trama con la identidad seleccionada. |
| `milestonesMs.firstTelemetry` | Primera 0x10/0x19 que aporta alguna métrica válida, no necesariamente las tres. |
| `milestonesMs.firstPage50` / `firstPage51` | Primera recepción de cada página; 0x50 incorrecta no equivale a identificación válida. |
| `milestonesMs.identificationComplete` | 0x50 con fabricante 67 y modelo 22 de la identidad seleccionada. |
| `milestonesMs.controlAvailable` | Primera publicación donde todas las barreras nativas están cumplidas. No implica activación ni envío. |
| `durationsMs.startToChannelOpen` | Tiempo total de preparación hasta abrir. |
| `durationsMs.channelOpenToFirstTelemetry` | Espera de primera métrica tras abrir. |
| `durationsMs.channelOpenToIdentification` | Espera de la 0x50 válida tras abrir. |
| `durationsMs.channelOpenToControlAvailable` | Tiempo hasta elegibilidad completa. |
| `durationsMs.identificationToControlAvailable` | Otras condiciones/publicación pendientes tras identificar. |
| `waitingReason` | Primera barrera nativa pendiente; todas siguen en `manualControl.blockingReasons`. |
| `waitingForConditionMs` | Espera desde observar esta barrera; se reinicia si cambia la primera barrera. |
| `waitingSinceChannelOpenMs` | Espera actual desde apertura; nulo si aún no abrió o no está esperando. |
| `pageRequest` | `enabled=false`, `attempts=0`, `maxAttempts=0`, motivo `bkool_v1_page70_support_unverified`. |

Las marcas son **offsets en ms desde inicio de sesión**, no fechas ni tiempos
transcurridos desde la última telemetría. Una diferencia se deja nula si falta
alguno de sus hitos; no se fabrica cero. La primera elegibilidad se mide al
publicar el snapshot, con la resolución indicada; no mide el instante de pintado
de Flutter. Si el control vuelve a bloquearse, los primeros hitos se conservan y
el motivo/tiempo actual de bloqueo se actualiza. Se reinicia todo al reconectar.

`IdentificationProgress` se muestra bajo la activación, tanto en entrenamiento
simple como detallado: condición pendiente, espera de esa condición, tiempo desde
apertura y cuatro hitos principales. Se aclara la necesidad de 0x50 y que 0x51
no la sustituye. Los datos siguen el flujo normal de snapshots con orden de
secuencia; no hay temporizadores de interfaz independientes ni habilitación local.

## Cómo medir en Galaxy S20

1. Instalar **1.1.5+8**, finalizar cualquier sesión anterior y conectar directamente
   con 30064/112/5. No hace falta activar resistencia para medir identificación.
2. Durante la espera observar el código del bloqueo y su contador. Anotar si
   cambia de `manufacturer_model_not_verified` a señal, telemetría o identidad.
3. Esperar a que el control figure disponible. No confundir «disponible» con
   «activo»: sigue siendo obligatoria la confirmación expresa por sesión.
4. Finalizar y exportar JSON desde diagnóstico de entrenamiento. Localizar
   `identificationTiming` en el reporte de esa sesión, junto con `sessionId`,
   `manualControl`, `channelIdentity`, `events` y `messages`.
5. Comparar `channelOpenToIdentification` con `channelOpenToControlAvailable`.
   Si ambos rondan 25–60 s y su diferencia es pequeña, el cuello es recibir la
   identidad válida; contrastar `firstPage50`, página 0x51 y frames hexadecimales.
   Si la diferencia es grande, revisar `manual_availability` y sus barreras: el
   problema no es solo esperar 0x50. `startToChannelOpen` separa radio/configuración.
6. Repetir varias conexiones completas (por ejemplo cinco), sin usar identidad
   previa para autorizar. Comparar mediana y máximo de cada fase. Esta versión
   aporta la línea base; no se considera una mejora de latencia hasta medir una
   intervención futura que realmente la reduzca sin relajar las comprobaciones.

## Verificación técnica

- `flutter analyze`: sin incidencias.
- `flutter test`: **49 pruebas correctas**; espera visible creciente y finalización
  de identificación, compatibilidad con capturas antiguas y regresiones existentes.
- `./gradlew :app:testDebugUnitTest`: **57 pruebas correctas**; hitos independientes,
  0x51 insuficiente, rechazo de identidad ajena/modelo/fabricante incorrectos,
  primera recepción única, cambio de barrera y reinicio por conexión.
- `flutter build apk --debug`: correcto, **1.1.5+8**. APK:
  `build/app/outputs/flutter-apk/openbkool-1.1.5-8-debug.apk`.

Se mantienen +1 %, 30 segundos, activación expresa, parada, segundo plano,
desconexión, BLE, búsqueda, CSV y JSON. Sin modificaciones de firmware, nuevas
tramas de control o peticiones de página. No se ha realizado una prueba física
ni medido una reducción de espera en el S20 durante este trabajo.
