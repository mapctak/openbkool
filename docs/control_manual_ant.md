# Primer control manual ANT — Smart Pro v1

La nueva versión permite una **prueba explícita y limitada** de pendiente real.
El usuario ha confirmado físicamente la telemetría durante 20 s en el canal
específico del Smart Pro v1, modelo 22, 30064/112/5. Esto valida la recepción,
**no** el envío, la aplicación de pendientes ni una parada segura del rodillo.
No se ha enviado ningún comando a hardware durante este desarrollo o sus tests.

## Formato justificado por el controlador original

Revisados [protocolo_bkool.md](protocolo_bkool.md),
[control_ant_preparacion.md](control_ant_preparacion.md) y las fuentes de JADX
(locales, excluidas de Git):

- `research/jadx/sources/com/bkool/sensors/tech/ant/devices/TrainerBkoolPro1.java`,
  `genericRequest()` → caso `TrackResist`, líneas 213–220: página decimal 51
  (`0x33`), cuatro FF, pendiente LE16 y segundo argumento convertido a byte.
- `research/jadx/sources/com/bkool/sensors/tech/ant/BkoolSensorAntPlus.java`,
  `changeBKOOLTraineSlope()`, líneas 215–219: segundo argumento `255.0f`.
- `research/jadx/sources/com/bkool/sensors/tech/ant/BkoolSensorAntWrapper.java`,
  `sendBroadcast()`, líneas 547–553: `antChannel.setBroadcastData(bArr)`.
- El controlador Pro1 reconoce modelo decimal 22 en página `0x50`; el informe
  anterior documenta esa asociación y la identidad ha sido probada físicamente.

La fórmula literal original es `(int)((pendiente + 200.0f) * 100.0f)`.
Para los **únicos** tres valores permitidos, su resultado es exacto y equivalente
a `20000 + (pendiente*100)`:

| Pendiente porcentual | LE16 decimal | Payload completo |
|---|---:|---|
| 0 % | 20000 | `33 FF FF FF FF 20 4E FF` |
| 0,5 % | 20050 | `33 FF FF FF FF 52 4E FF` |
| 1 % | 20100 | `33 FF FF FF FF 84 4E FF` |

Se reutiliza PUBLIC, RF 40, período 32768, canal normal `BIDIRECTIONAL_SLAVE`
con ID completo **30064/112/5**. No se transmite en el canal de búsqueda ni en
el entrenamiento de background. El método real es exclusivamente
`AntChannel.setBroadcastData(payload)`, sin acknowledged, burst ni FE-C.
El [SDK oficial](https://www.thisisant.com/APIassets/Android_ANT_API/com/dsi/ant/channel/AntChannel.html)
especifica que en un canal esclavo se ofrece el mensaje en la siguiente ventana
inversa y que broadcast no proporciona confirmación de recepción.

**Suficientemente justificado para esta prueba acotada:** los ocho bytes y el
método de transmisión coinciden con Pro1, sin extrapolar el formato Pro2 ni
escribir UserConfig. Los tests no sustituyen una captura de transmisión real.

**Incertidumbres que permanecen:** significado completo de los FF, efecto de la
configuración/peso existente, aceptación de este firmware, repetición necesaria,
retención de la última pendiente, bloqueo y tiempo de respuesta. No se envían
otras páginas para intentar resolverlas. Si la prueba no produce el efecto
esperado, detener y analizar registros; no añadir repetición o configuración
por ensayo automático. Esta versión no asegura que una orden sea efectiva.

## Uso y activación

1. Conectar con «Iniciar entrenamiento» (canal específico). Abrir la pantalla o el canal
   no activa el control y no transmite pendiente 0 % por defecto.
2. Esperar identidad extendida **exacta**, fabricante 67 y modelo 22 recibidos en
   esta sesión, además de telemetría válida. El sistema exige última página del
   equipo hace menos de 3 s y velocidad/potencia/cadencia aún disponibles según
   el control de antigüedad del decodificador (10 s).
3. Marcar «Habilitar prueba de resistencia» y aceptar el diálogo «Habilitar prueba».
   La activación solo arma la prueba: **no envía** una pendiente inicial.
4. Los botones `−`, `0 %` y `+` solicitan solamente 0 %, 0,5 % o 1 %. `+` y `−`
   se basan en la última pendiente cuyo envío retornó de la API, no en una carga
   confirmada del rodillo. El primer `+` solicita 0,5 %. Para empezar por 0 %,
   pulsar expresamente `0 %` después de habilitar.
5. «Detener prueba», fijo en la parte inferior durante la activación, inicia la
   parada descrita abajo. Finalizar entrenamiento, volver atrás, desmarcar la
   casilla o pasar a segundo plano también cancelan la prueba y cierran el canal.

La autorización es temporal, no se guarda en preferencias y no se restaura al
reconectar. Cada petición lleva un UUID de sesión; una confirmación antigua no
puede habilitar una sesión nueva. Solo el canal asociado al objetivo permitido
puede llegar al transporte. Otros dispositivos seleccionados mantienen su
telemetría, con el control manual rechazado.

## Máquina de estados y límites

`ManualAntControl.kt` contiene codificación y estado sin Android. Recibe reloj,
consulta de enlace, transporte y registro mediante funciones inyectadas.
Kotlin integra un único transporte real en la cola serial ANT existente;
Flutter utiliza `enableManualTest`, `setManualSlope` y `stopManualTest` por
MethodChannel. `prepareSlope` y `controlPreparation.mode=dry_run_only` conservan
el preparador offline anterior: no habilitan ni transmiten nada. El estado real
de esta prueba está en `manualControl`.

- Estados: inactivo → habilitado → parada o fallo → sesión cerrada.
- Límite duro de valores: **exactamente 0 / 0,5 / 1 %**. Se rechazan negativos,
  superiores a 1, otras fracciones, NaN e infinito, aunque se eluda la interfaz.
- Comprobación de ID, modelo, canal y frescura en cada solicitud y de nuevo
  inmediatamente antes de entrar a la API. No hay cola de pendientes
  de replay, ni escritura por eventos RX o TX.
- Duplicados de la última pendiente retornada por la API se omiten. Cambios
  distintos se limitan a uno por segundo. La UI serializa solicitudes normales.
- Un error de la API deshabilita la prueba, registra la excepción y cierra sin
  reintentos automáticos. Un retorno `void` nunca se etiqueta como «aplicado».
- **30 s desde la activación**, sin prolongarse al volver a pulsar habilitar.
  Se rechazan cambios al alcanzar el plazo. Un watchdog de un segundo solicita
  la parada; se añade el margen de drenaje y limpieza al cierre. No es un
  temporizador de tiempo real: un Binder bloqueado o un proceso eliminado por
  Android puede impedir cumplir el plazo o efectuar la parada.
- Durante la prueba, señal de 3 s o más, telemetría inválida/antigua o identidad
  incompatible abortan la prueba. Se cierra, sin replay al recuperar la señal.
  Para continuar se requiere conexión y activación nuevas. El entrenamiento sin
  control conserva sus umbrales anteriores de 5/15 s.

## Parada, desconexión y sus límites

Se bloquean nuevas solicitudes antes de procesar la parada. «Detener prueba»
permanece accesible aunque otra solicitud esté ocupada; no puede deshacer una
llamada que ya haya entrado en Binder o una trama ya entregada a la radio.

Si la prueba llegó a habilitarse y el canal/identidad/modelo/señal/telemetría
siguen utilizables, se intenta **una** solicitud de 0 %. Es una excepción
intencionada a la deduplicación y al límite de frecuencia: se solicita incluso
si el último retorno de la API fue para 0 %, porque ese retorno no confirmó
recepción. Una prueba nunca habilitada no envía ni siquiera ese 0 % al cerrar.

Tras el retorno de esa solicitud se espera **1,5 s**, sin bloquear el worker,
antes de cerrar, esperar `CHANNEL_CLOSED`, desasignar/liberar, restaurar la
configuración de identidad extendida y desenlazar servicio. Ese margen supera
un período configurado de 1 s, pero **no demuestra que haya habido ventana TX ni
que el rodillo recibiera la página**. La telemetría permanece activa durante la
prueba; desde el inicio de parada se descartan callbacks para evitar trabajo y
órdenes nuevas, mientras la radio dispone del margen de drenaje.

Si no hay enlace utilizable, se perdió la radio o falló la API, no se intenta
recuperar el canal para reenviar 0 %: se registra el motivo y se liberan los
recursos disponibles. No hay reintentos a ciegas. Errores de limpieza siguen
bloqueando reservas nuevas hasta reiniciar el proceso, como antes.

**Ni 0 % ni cerrar significan resistencia cero o segura.** En una reacción
inesperada, dejar de pedalear, esperar a que se pare la rueda y desmontar sin
confiar en el reset remoto. La retención de resistencia y el comportamiento al
cortar alimentación no están validados por este código. No hay control ERG,
firmware, GPX ni control fuera de este experimento.

## Diagnóstico JSON y CSV

«Exportar diagnóstico JSON» en Entrenamiento copia el snapshot con:

- `sessionId`, identidad seleccionada, parámetros y operaciones de canal.
- `manualControl`: activación, plazo restante, última pendiente entregada a API,
  intentos, fallo, parada y `physicalApplication=unconfirmed`.
- `manualControlEvents`: cada solicitud, rechazo, duplicado, intento de API,
  bytes `payloadHex`, propósito normal/parada, retorno `void` o excepción con
  clase, mensaje, causas y detalles ANT cuando los aporta el SDK.
- Los eventos tienen secuencia, fecha UTC, reloj monótono y destino. `payloadHex`
  representa bytes ofrecidos al transporte; no es una captura de radio.
  `api_attempt` significa intento y `api_returned` solo retorno correcto de la API.
- Motivos de omitir el 0 % y resultado `zero_api_returned_unconfirmed` o error.

El diagnóstico general también incluye lo anterior dentro de `antTraining`.
Los registros completos de control se conservan en memoria para la sesión,
independientemente del búfer circular de mensajes RX; exportar antes de iniciar
otra sesión o cerrar el proceso. **No hay journal persistente de órdenes ni
recuperación de un reset pendiente tras muerte del proceso.** El CSV de
telemetría existente se mantiene y no se presenta como confirmación del control.

## Validación automatizada y prueba física pendiente

Los tests de `ManualAntControlTest.kt` usan exclusivamente un transporte falso:
valores exactos 0/0,5/1, límites, activación y ausencia de envíos iniciales,
identidad/modelo/canal/frescura, deduplicación, frecuencia, timeout, pérdida de
señal, parada única, errores y no reactivación. Los de Flutter simulan los
MethodChannel: comprueban confirmación, botones, límites visuales, UUID, parada
y JSON. Se mantienen las pruebas BLE/ANT/telemetría originales.

**Pendiente de campo:** instalar la APK, recibir modelo e identidad, habilitar
expresamente y observar primero 0 % y después 0,5 %/1 % dentro del plazo. Guardar
JSON y CSV y contrastar la respuesta del rodillo; no interpretar el mensaje de
retorno de API como confirmación. No se ha conectado ni instalado esta versión
en un teléfono durante el desarrollo y no se ha ejecutado el transporte real.

Resultados locales del 2026-11-13:

- `flutter analyze`: sin incidencias.
- `flutter test`: 16 pruebas correctas. Incluye la parada con una solicitud
  pendiente y protección para que una respuesta tardía no reactive el estado.
- `cd android` y `./gradlew :app:testDebugUnitTest`: 38 pruebas correctas,
  incluidas 9 específicas del nuevo control con transporte falso.
- `flutter build apk --debug`: correcto;
  `build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: correcto. No se modifican firmware, parámetros RF/período,
  implementación BLE ni decodificación de telemetría.
- Los avisos de Gradle corresponden a deprecaciones previas de Kotlin/AGP.
  No se instaló la APK, no se abrió una radio y no se ejecutaron comandos reales
  durante las pruebas automatizadas ni durante este desarrollo.

## Corrección del bloqueo de activación (Galaxy S20)

El JSON aportado posteriormente por el usuario (`updatedAt`:
`2026-11-13T18:22:25.393Z`) confirma:

```json
{
  "mode": "training",
  "channelMode": "background_receive_only",
  "connectionState": "identity_verified",
  "manualControl": {
    "eligible": false,
    "unavailableReason": "dedicated_identity_required",
    "enabled": false,
    "stopped": false,
    "faulted": false,
    "remainingMs": null
  }
}
```

La identidad y la telemetría eran correctas (última página hace 202 ms), pero
el botón principal «Iniciar entrenamiento» solicitaba `training`, que abre
`SLAVE_RECEIVE_ONLY` en background. `ManualControlLink.dedicated` permanecía
falso durante toda esa sesión por diseño. No era un timeout, falta de confirmación
ni fallo del flujo EventChannel: la app estaba solicitando el modo equivocado
para la intención de entrenar con control. El fallo era de selección del modo
en la interfaz, no de la restricción que impedía transmitir por ese canal.

**Segundo bloqueo presente en el mismo JSON:** `devices` solo contenía la página
`0x51` (software/serial). No había `manufacturerId` ni `modelNumber`, ni una
página `0x50` en los mensajes/eventos aportados. Abrir el canal específico
resuelve el primer bloqueo, pero **no autoriza a dar por recibido el modelo**.
Si la nueva sesión no recibe página 0x50 con fabricante 67/modelo 22, la casilla
seguirá correctamente bloqueada y explicará ese motivo. No se copia información
de capturas antiguas ni se envían solicitudes ANT nuevas para obtenerla.

Correcciones implementadas:

- «Iniciar entrenamiento» solicita ahora `training_connected`, con la identidad
  completa seleccionada. «Solo telemetría (sin control)» conserva el antiguo modo
  `training`. El cambio de modo requiere finalizar primero; no se reasigna un
  canal abierto ni se habilita/transmite control automáticamente.
- La casilla usa `ManualActivationStatus`: entrenamiento activo, UUID recibido,
  sin operación pendiente/cierre/fallo y decisión `eligible` confirmada por Kotlin.
  La confirmación explícita se pide **después** de pulsarla. El temporizador no
  tiene que haber empezado para permitir abrir ese diálogo.
- Un texto inmediatamente debajo muestra código y explicación en español de
  cada bloqueo, incluidos estado nativo ausente, operación en curso y temporizador.
  «Condiciones actuales de seguridad» detalla canal/estado de apertura/radio,
  identidad, fabricante/modelo, edad de señal, telemetría y fecha de actualización.
- Kotlin separa canal de solo recepción, canal aún sin abrir, radio no disponible,
  sesión cerrada e identidad pendiente. `manualControl.blockingReasons` contiene
  **todos** los motivos y `link` sus valores reales; no se ocultan los bloqueos
  secundarios detrás del primero. El motivo antiguo combinado se interpreta
  con el modo explícito si aparece en un snapshot anterior.
- `snapshot()` ya no devuelve `eligible=false` con motivo nulo para una sesión
  parada o fallida; también informa `test_timeout` al alcanzar los 30 s antes
  del siguiente tick. No se cambia el transporte, rango, plazo ni parada.
- Al comenzar una nueva sesión se limpian el UUID, autorización, telemetría,
  identificación y fechas anteriores. Se muestra «Conectando» hasta recibir el
  nuevo estado nativo, en lugar de reutilizar una aparente autorización antigua.
- El JSON de Entrenamiento añade `manualActivationUi` con el código mostrado,
  disponibilidad y estados de operación/cierre de Flutter. El estado nativo
  completo continúa en el diagnóstico y en `antTraining` del JSON general.

### Cómo verificar la corrección

1. Finalizar cualquier sesión abierta e instalar la APK nueva. Seleccionar
   30064/112/5 y pulsar **Iniciar entrenamiento**.
2. Comprobar `channelMode=dedicated_bidirectional_manual_opt_in` y que el estado
   deja «Conectando» al llegar información nativa. No debe figurar
   `background_receive_only` salvo que se elija expresamente «Solo telemetría».
3. Esperar identidad, página 0x50 (67/22), señal <3 s y velocidad/potencia/cadencia
   válidas (<10 s). El texto debe pasar a **«Condiciones cumplidas»** y habilitar
   la casilla **sin marcarla**. Aún no se transmite ninguna orden.
4. Si sigue gris, leer su motivo y expandir las condiciones. En particular,
   `manufacturer_model_not_verified` requiere esperar la página 0x50 real; la
   página 0x51 y el ID conocido no sustituyen esta comprobación. Exportar JSON
   si no aparece esa página o persiste otro bloqueo.
5. Para verificar solo la corrección de interfaz, no aceptar el diálogo de
   habilitación. La prueba física de pendiente sigue requiriendo aceptación
   expresa; se mantienen 0–1 %, 30 s y «Detener prueba».

### Regresión reproducible

`test/fixtures/manual_control_blocked_s20.json` conserva un subconjunto literal
del JSON del usuario, sin inventar fabricante/modelo. Los tests reproducen la
casilla deshabilitada con telemetría real válida y canal de solo recepción;
comprueban el modo que solicita el botón principal, el borrado del estado antiguo,
las actualizaciones EventChannel de bloqueado a elegible y de nuevo a bloqueado,
y la ausencia de habilitación/envío automáticos.

Las pruebas Kotlin verifican que la página 0x51 no proporciona modelo ni
fabricante, que el modo específico por sí solo no basta y que una página 0x50
válida permite la elegibilidad sin transmitir. Esa página procede de la captura
anterior usada en los tests: **no** se presenta como recibida en la última
sesión del S20. También cubren apertura, radio, fallo, parada y timeout con
transporte falso. No se transmiten órdenes a hardware en las pruebas.

Resultados de validación de esta corrección (2026-11-13):

- `flutter analyze`: sin incidencias.
- `flutter test`: 21 pruebas correctas (incluida la reproducción del JSON real).
- `./gradlew :app:testDebugUnitTest` desde `android`: 42 pruebas correctas.
- `flutter build apk --debug`: compilación correcta; APK en
  `build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: correcto. Los avisos Gradle de deprecación son previos.
- Pruebas con canales simulados y transporte falso. No se instala la APK ni se
  envían comandos al rodillo durante esta corrección. La comprobación física
  de la interfaz nueva y la recepción de 0x50 en una sesión nueva quedan para
  el Galaxy S20; la validación local no sustituye esa prueba.

## Diferenciar recepción, canal e instalación de la APK

En la comprobación posterior el usuario sigue leyendo literalmente
`Control no disponible: dedicated_identity_required`. Ese texto ya no existe en
la interfaz actual: pertenece a la APK anterior. Es evidencia de una instalación
anterior o de una actualización incompleta, no de que el ID esté necesariamente
mal. La nueva compilación sube a **1.0.0+2 (versionCode 2)** y muestra debajo del
bloqueo **«Diagnóstico de control v2 · Kotlin: 2»** al iniciar la sesión. Si aparece
«Kotlin: pendiente», todavía no ha llegado el snapshot nuevo; no se debe atribuir
un estado anterior al código nuevo. Hay que instalar la APK completa, ya que un
hot reload de Dart no actualiza el código Kotlin del teléfono.

Además se añade evidencia explícita del canal activo:

- `channelIdentity.selected`: identidad seleccionada por el operador.
- `channelIdentity.configured`: ID cuya configuración terminó correctamente.
- `channelIdentity.adapterReadback`: ID que devuelve el adaptador mediante
  `AntChannel.requestChannelId()` después de abrir el canal específico.
- `channelIdentity.lastReceived`: identidad extendida del último paquete recibido.
- `channelIdentity.allMatch`: las cuatro identidades coinciden exactamente,
  incluidos número, tipo y transmisión. Deben ser **30064/112/5**.

`requestChannelId()` consulta al adaptador ANT, según el SDK oficial: no solicita
una página al rodillo ni envía datos de pendiente/resistencia. Se realiza una
vez al configurar el canal específico. Si falla sin pérdida IPC, la telemetría
puede continuar, pero el control queda bloqueado con el error completo registrado.
Un `RemoteException` significa canal no utilizable y se conserva su cierre seguro.
No se declara verificado un ID solo porque se haya seleccionado en Flutter.

La elegibilidad exige ahora también esa coincidencia. Un dato ausente, comodín,
un dispositivo diferente o un transmission type diferente produce
`active_channel_identity_not_verified`. Las identidades y el posible error de
consulta aparecen en «Condiciones actuales de seguridad» y en el JSON.

Cada transición de elegibilidad se registra como `events[].event=manual_availability`
con `details` estructurados: bloqueos, valores del enlace e identidades comparadas.
No se genera un evento por cada milisegundo de edad de señal; el snapshot sí se
actualiza continuamente. Esto permite distinguir recepción de telemetría, canal
abierto/apto y autorización explícita para transmitir. Ninguna de estas lecturas
habilita la prueba o envía automáticamente una pendiente.

Validación de esta ampliación: `flutter analyze` sin incidencias, 21 pruebas
Flutter y 44 Kotlin correctas; APK 1.0.0+2 compilada. El paquete se inspecciona
con `aapt` para verificar `versionCode=2` y etiqueta OpenBkool. Para evitar
confundir descargas anteriores se incluye una copia con nombre propio:
`build/app/outputs/flutter-apk/openbkool-1.0.0-2-debug.apk`.

ADB no detecta teléfonos conectados: no se ha leído la versión realmente
instalada en el S20 ni instalado la APK durante esta ampliación. Tras instalarla,
iniciar una **sesión nueva** y comprobar la marca v2/Kotlin 2, expandir condiciones
y verificar los cuatro ID iguales a 30064/112/5. El texto exacto y los eventos
`manual_availability` del JSON nuevo identificarán cualquier bloqueo restante,
incluida la página 0x50 pendiente. Ninguna prueba automatizada usa radio real.
