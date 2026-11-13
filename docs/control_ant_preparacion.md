# Preparación de control ANT V1 — transmisión bloqueada

Estado: código para reservar y abrir un canal específico, recibir telemetría y
preparar candidatos de pendiente **sin transmitirlos**. No existe implementación
de transporte de comandos, opción de habilitación, reenvío periódico ni reset
al finalizar. Tampoco se activa Bkool V2, DFU o GPX.

La recepción y el CSV anteriores han sido confirmados físicamente por el usuario
en S7/S20. El **nuevo canal específico aún necesita prueba física**, inicialmente
solo con telemetría. La compilación/pruebas locales no demuestran recepción real
por ese canal.

## Evidencias y decisiones

Referencias de partida: [protocolo_bkool.md](protocolo_bkool.md) y
[telemetria_ant.md](telemetria_ant.md). Fuentes originales excluidas de Git:

- `research/jadx/sources/com/bkool/sensors/tech/ant/devices/TrainerBkoolPro1.java`:
  `connect()` llama `assignChannel(..., 0, 0, 32768, 40, ..., false)` y abre el
  canal; `genericRequest()` construye páginas y llama `sendBroadcast()`.
- `research/jadx/sources/com/bkool/sensors/tech/ant/BkoolSensorAntWrapper.java`,
  `assignChannel()` (líneas 346–425): rama sin background reserva PUBLIC, llama
  `assign(ChannelType.create(b2))`, configura período y timeouts. La rama de
  búsqueda activa background scanning y `SLAVE_RECEIVE_ONLY`.
- En esa misma clase, `sendBroadcast()` (547–553) llama
  `AntChannel.setBroadcastData()`. La pendiente de Pro1 **no** usa datos acknowledged.
- `research/jadx/sources/com/bkool/sensors/beans/ConstantesSensors.java` contiene
  `ANT_BKOOL_SEARCH_LEN=16`. No se interpreta ese número como milisegundos o
  segundos válidos para nuestra ANTLib sin comprobar su API.

**Hechos del SDK instalado ANTLib 4.16.0**, contrastados con sus Javadocs y AAR:

- [ChannelType](https://www.thisisant.com/APIassets/Android_ANT_API/com/dsi/ant/message/ChannelType.html):
  `SLAVE_RECEIVE_ONLY` no puede transmitir. `BIDIRECTIONAL_SLAVE` recibe y permite
  transmisión inversa; su valor raw es 0, comprobado en test con el SDK instalado.
- [AntChannel](https://www.thisisant.com/APIassets/Android_ANT_API/com/dsi/ant/channel/AntChannel.html):
  hay que desasignar antes de reasignar. `assign()` restablece valores por defecto.
  El modo esclavo transmite `setBroadcastData()` una vez en la próxima ventana
  de transmisión. No ofrece confirmación de recepción ni de aplicación física.
- `setSearchTimeout(low, high)` está prohibido en background scanning. En un
  canal normal admite un máximo de 30 s y se recomienda desactivar alta prioridad.
- [LowPrioritySearchTimeout](https://www.thisisant.com/APIassets/Android_ANT_API/com/dsi/ant/message/LowPrioritySearchTimeout.html):
  **`create(int)` recibe milisegundos**, no el byte raw del protocolo. El AAR instalado limita la parte de baja prioridad a **25 s**:
  `create(30000).convertToMilliseconds()` devuelve 25000. Se usa directamente
  `TWENTY_FIVE_SECONDS`; alta prioridad queda desactivada. No se confunde el
  máximo combinado documentado de 30 s con la parte de baja prioridad. El test
  también muestra que `create(16)` devuelve 2500 ms: copiar el 16 de JADX sin
  contrastar versiones produciría otro comportamiento.

**Conclusión:** el canal actual sirve para descubrir y observar varios equipos;
no debe convertirse en transmisor cambiando una bandera sobre el canal abierto.
Se termina la búsqueda, se confirma su liberación y se reserva otro canal normal
asociado a la identidad completa. Se conservan PUBLIC, RF 40 y período 32768.

**Limitación de JADX:** la salida Java de la rama normal de `assignChannel()`
parece retornar `null` antes del bloque común de ID/RF. No se copia ese flujo
aparentemente defectuoso ni se afirma que se ejecutara así en la APK original.
La configuración explícita de ID/RF/apertura se justifica mediante la API oficial
y los parámetros del controlador, separando intención de reconstrucción Java.

Abrir un canal normal y configurar la radio requiere comandos administrativos
al **ANT Radio Service**. No se envían páginas de aplicación al rodillo. No se
promete silencio RF absoluto de la pila: su señalización automática y el protocolo
de enlace dependen de ANT. El bloqueo aquí se aplica a datos/comandos del rodillo.

## Buscar → Seleccionar → Conectar → Entrenar

En «Entrenamiento»:

1. «Buscar rodillos ANT» abre el diagnóstico existente. Es secuencial y conserva
   FE-C/V1. Al volver se ha detenido/liberado la búsqueda. No hay autoconexión.
2. Se selecciona una identidad de los resultados V1 (número/tipo/transmisión).
   Se mantiene además el rodillo confirmado 30064/112/5 como elección inicial.
   Un tipo 112 encontrado no demuestra fabricante Bkool por sí solo.
3. «Conectar y entrenar (sin comandos)» solicita explícitamente
   `training_connected`. Se valida PUBLIC V1, número 1–65535, tipo 112,
   transmisión 1–255, sin comodines. El dispositivo seleccionado se envía a Kotlin.
4. Se reserva canal normal, handler, `BIDIRECTIONAL_SLAVE` **sin** asignación
   extendida de background; ID completo, período 32768, RF 40, búsqueda de baja
   prioridad 25 s/alta prioridad desactivada, salida de identidad extendida y apertura.
5. Abrir no demuestra conexión. `connectionState=waiting_for_identity` hasta
   recibir una trama con los tres identificadores exactos. Solo entonces queda
   `identity_verified`, y la telemetría continúa con el decodificador existente.
   Paquetes de otro número, tipo o transmisión no actualizan métricas/presencia/CSV.

«Iniciar entrenamiento» conserva el modo anterior de recepción en background,
con filtro software sobre la identidad seleccionada. Si falla el canal nuevo,
se puede finalizar y usar ese modo. **No hay fallback automático ni transmisión
automática**. Para esta fase, conectar y entrenar inicia solamente telemetría;
no hay un paso de entrenamiento que habilite comandos.

Un coordinador común impide que búsqueda, diagnóstico de reserva y entrenamiento
abran canales simultáneos en OpenBkool. El cambio de modo exige finalizar primero.
No se libera la exclusión si la limpieza falla; se requiere reiniciar el proceso.
Los timeouts de inicialización, eventos de canal/servicio, pérdida de señal 5 s,
desconexión 15 s, salida de pantalla y segundo plano conservan la limpieza existente.

La identidad elegida queda en `selectedDevice`, la configuración en
`operationEvents`, el modo en `channelMode`, y los bloqueos en `controlPreparation`
y eventos `slope_dry_run`. Todo se incluye en `antTraining` del diagnóstico JSON.
El CSV usa la identidad real seleccionada, no constantes del rodillo anterior.

## Pendiente: candidato offline, incertidumbres y límites

Interfaz Flutter: deslizador 0–1 % y botón «Aplicar pendiente (bloqueado)» con
callbacks nulos. El usuario no puede solicitar envíos desde la pantalla.

`ManualSlopePreparation` es Kotlin puro. `prepareSlope` por MethodChannel es
solo diagnóstico de preparación en la cola serial: exige sesión activa y una
identidad comprobada recientemente en el **canal específico**. Incluso un plan
válido devuelve `state=transmission_disabled`, `sent=false` y
`transmissionEnabled=false`. No hay bandera modificable para habilitarlo.

Pro1 construye en `genericRequest(TrackResist)`:

```text
g = (int)((pendiente + 200.0f) * 100.0f)
33 FF FF FF FF gL gH FF
```

El último FF procede del segundo argumento 255 que pasa el adaptador original.
Para preparar candidatos se admiten solo valores finitos entre 0 y +1 %, en
centésimas exactas, y se construye LE16 de `20000 + centésimas`. No se extrapola
el rango útil del firmware ni se imitan truncamientos de valores arbitrarios.

| Pendiente | Candidato (NO enviado) |
|---|---|
| 0 % | `33 FF FF FF FF 20 4E FF` |
| +1 % | `33 FF FF FF FF 84 4E FF` |

La representación byte a byte de esos extremos está confirmada por la fórmula
original y los tests; **su aceptación y efecto en el rodillo no están probados**.
Siguen sin confirmarse significado de todos los FF, revisión de firmware,
necesidad previa de UserConfig, efectos de peso/configuración de usuario,
repetición necesaria, caducidad de órdenes y comportamiento después de perder
el enlace. La semejanza con FE-C no autoriza sustituirlo por el controlador FE-C.

El preparador rechaza NaN/infinito/rango/precisión inválidos; bloquea sin conexión,
tras parada, duplicados de la última pendiente y cambios a menos de 1 s. Ese
segundo es una política conservadora local, **no una exigencia del protocolo**.
No hay colas de comandos: `pendingCommands=0`. Se distingue preparado de enviado;
ningún resultado dice que el rodillo haya aceptado una pendiente.

## Diseño del futuro envío (no implementado)

Una fase posterior deberá añadir un transporte separado y explícitamente
habilitado para cada sesión física. Solo podrá ejecutarse en la misma cola serial,
tras volver a comprobar sesión, ID completo, modelo/fabricante/firmware, señal
reciente, rango aprobado y permiso explícito del operador. El único método del
SDK justificado por Pro1 es `setBroadcastData(payload)` sobre el canal específico.
No hay referencia a esa llamada en el código productivo actual.

Una solicitud tendría estados `requested → validated → submitted_to_radio` o
`rejected/failed`; nunca `applied` sin evidencia independiente. Un retorno del
SDK solo probaría entrega a la pila. Los errores IPC/canal deben invalidar la
conexión, cancelar pendientes y registrarse completos. No habrá reintentos
ciegos, replay al reconectar ni temporizador de repetición en la primera prueba.
La deduplicación del preparador demuestra la política, pero el futuro transmisor
deberá distinguir la última preparación de la última entrega exitosa al SDK.

## Parada segura

Ahora: bloquear preparación, invalidar conexión, vaciar estado pendiente (siempre
cero), cerrar/esperar cierre/desasignar/liberar, restaurar configuración extendida
previa y desenlazar servicio. Se registran todos los errores y se intentan las
etapas de limpieza restantes. Se conserva una advertencia visible:
**cerrar no garantiza resistencia cero**. No se envía ni siquiera la página de 0 %.

Para una futura prueba con control: separar «detener órdenes/cerrar» de una
solicitud de retorno a una condición previamente ensayada. 0 % de pendiente no
es resistencia cero; el envío broadcast tampoco garantiza aplicación. Si se
pierde la radio, no se puede prometer un reset remoto. El operador debe poder
dejar de pedalear, esperar a que se detenga la rueda y desmontar; el procedimiento
físico de alimentación se debe acordar conforme al rodillo, sin confiar en la app.
No mantener un bucle de reenvío durante parada ni retomar control al reconectar.

## Qué falta antes de probar 0 % → +1 %

1. Instalar esta APK y verificar solo telemetría en canal específico sobre S7/S20:
   ID 30064/112/5 verificado, modelo 22/fabricante 67 recibido, pérdidas y liberación
   correctas. Guardar JSON y CSV. Este paso aún no transmite páginas de control.
2. Resolver o acotar las incertidumbres de UserConfig/FF/firmware y documentar
   qué candidato se probará, si es de un solo envío, y cómo se observará su efecto.
3. Aprobar una fase que añada el transporte y una habilitación explícita por sesión,
   con limitación dura 0–1 %, identidad completa y modelo verificados, confirmación
   manual de cada orden, registro y sin reintentos automáticos. El código actual
   no puede habilitarse simplemente moviendo el deslizador.
4. Acordar parada física y criterio de aborto: sin respuesta, subida inesperada,
   telemetría antigua o error de radio → dejar de pedalear y detener la prueba.
   No asumir que enviar 0 % o cerrar devuelve el rodillo a una carga segura.

## Pruebas

JVM: orden de configuración sin background ni interfaces de envío, identidad
exacta/sin comodines, errores por operación, RF incompatible, unidades del timeout
con ANTLib instalada, candidatos 0/+1, rango/precisión/NaN, deduplicación, limitación
de frecuencia, desconexión/parada, ausencia de cola y exclusión entre sesiones.
Se conservan las pruebas de capturas reales y diagnósticos existentes.

Flutter: seleccionar otro ID y comprobar los argumentos exactos del modo específico,
comprobar callbacks nulos del control, ausencia de conexión automática, telemetría,
finalización/CSV y regresión BLE/ANT.

Resultados locales del 2026-11-13:

- `flutter analyze`: sin incidencias.
- `flutter test`: 14 pruebas correctas, incluidas las regresiones BLE/ANT.
- `cd android` y `./gradlew :app:testDebugUnitTest`: 29 pruebas correctas.
- `flutter build apk --debug`: compilación correcta;
  `build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: correcto. APK original y fuentes JADX siguen excluidas.
- Inspección del código productivo Kotlin/Dart: ninguna llamada a
  `setBroadcastData`, `startSendAcknowledgedData`, burst, control FE-C o escritura GATT.
  No se ha realizado una prueba física ni enviado páginas de control durante
  esta implementación. Los avisos de Gradle sobre Kotlin/AGP son deprecaciones
  preexistentes y no bloquean las pruebas ni la compilación actual.
