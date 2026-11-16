# Auditoría de transmisión y parada ANT — 1.1.7+10

Trabajo únicamente en `feature/control-ant`, conservando los cambios anteriores.
**Continuo físico bloqueado.** Se mantienen +1 %, 30 s, activación expresa,
identidad 30064/112/5, fabricante 67/modelo 22 de la sesión actual, codificación,
RF40/período32768/PUBLIC, telemetría, BLE, CSV y navegación.

## Fuentes y alcance

1. [SDK oficial ANT Android, versión C.B7](https://github.com/ant-wireless/ANT-Android-SDKs/blob/master/ANT_Android_SDK/README.md), que incluye ANTLib 4.16.0.
2. [Javadoc oficial ANTLib 4.16.0](https://github.com/ant-wireless/ANT-Android-SDKs/blob/master/ANT_Android_SDK/API/Android_ANTLib_Javadoc_4-16-0.zip).
   Se descargó y examinó el ZIP porque las antiguas URLs HTML redirigen al
   portal Garmin y ya no muestran el contrato. Rutas internas verificables:
   `com/dsi/ant/channel/AntChannel.html` (`setBroadcastData`, `close`, `release`),
   `com/dsi/ant/channel/IAntChannelEventHandler.html` y
   `com/dsi/ant/message/EventCode.html`.
   SHA256 ZIP: `87e76d880dcbaf8eeca5493e2de677bf38f8ab19670216fa5fa286cb0f149724`.
3. Biblioteca instalada `android/app/libs/android_antlib_4-16-0.aar`, examinada
   con `javap -c` sobre su `classes.jar`. SHA256 AAR:
   `944fab1871b18f2b191228af720aaa2eb7057312ffa18d7150f96d1859562d17`.
4. Fuente local excluida, `research/jadx/sources/com/dsi/ant/channel/AntChannel.java`,
   líneas 189–193 y 222–227; wrapper Binder
   `channel/ipc/aidl/IAntChannelAidl.java`, líneas 279–295. Es evidencia de la
   APK analizada; las firmas/bytecode relevantes se contrastaron con el AAR actual.
5. [Foro oficial: EVENT_TX durante cierre](https://www.thisisant.com/forum/viewthread/1972),
   respuesta del administrador del 20-09-2011. Documenta que puede observarse
   un TX previo a CHANNEL_CLOSED; no identifica qué bytes salieron.

No se ha inspeccionado el código interno de ANT Radio Service 4.18 ni el firmware
ANT del S20. Las fuentes no permiten reconstruir todos sus búferes internos.

## Qué garantiza el contrato revisado

Según el Javadoc 4.16.0, broadcast no tiene acuse de recepción. Un maestro emite
el contenido configurado periódicamente; un esclavo lo emite una vez en la
siguiente ventana. `close()` retorna al aceptarse el comando de cierre: hay que
observar `CHANNEL_CLOSED` para constatar que acabó. `TX` describe una emisión,
no recepción. `TRANSFER_TX_COMPLETED` corresponde a acknowledged/burst, no a
confirmación de un broadcast. Después de `onChannelDeath` el objeto no es
utilizable. Estas garantías no certifican el efecto mecánico del rodillo. [1–2]

**Aplicación al canal específico:** OpenBkool usa `BIDIRECTIONAL_SLAVE`, no maestro.
Por tanto no se deduce que una pendiente se retransmita continuamente hasta
cambiarla. El retorno void es un resultado de API, no un acuse de aplicación.
La capa Java actual comprueba ocho bytes y delega en el comunicador; no devuelve
un recibo del rodillo, un número de transmisión ni un identificador de paquete.
El wrapper Binder local hace una transacción síncrona y lee excepciones, pero
eso no revela cuándo se transmite por RF. [3–4]

### Sustitución, cola y orden: límites de lo demostrable

| Pregunta | Conclusión |
|---|---|
| ¿Una llamada sustituye el mensaje anterior? | Configura el mensaje lógico de broadcast del canal para una transmisión futura. No queda demostrado si un mensaje previo ya admitido en otra capa se retira antes de transmitir. |
| ¿Único búfer o FIFO? | El contrato Android revisado no promete una FIFO de todas las llamadas ni especifica profundidad/overwrite de las capas servicio/controlador. Tampoco prueba que exista una cola ilimitada. No se escoge ninguna hipótesis como hecho. |
| ¿Orden garantizado? | Nuestro trabajador invoca A y después B, y registra los retornos. Ese orden de llamadas no demuestra que ambos mensajes se emitan, lleguen, o se apliquen en ese orden. |
| ¿Cierre vacía o entrega el último mensaje? | No hay garantía documentada de flush ni de entrega de cero antes del cierre. Un TX puede observarse mientras el canal termina de cerrar. [5] |
| ¿Se puede cancelar lo ya entregado a ANT? | La cancelación implementada solo alcanza nuestra cola. No hay cancelación verificada de una llamada ya iniciada o del contenido del servicio/radio. |
| ¿TX confirma cero? | No: el evento carece de porcentaje/payload/secuencia de comando. No se correlaciona con el último retorno de API por mera proximidad temporal. |
| ¿Ausencia de TX demuestra fallo? | Tampoco. Se conserva la observación sin transformarla en un recibo negativo de un comando específico. |

Los modelos de pruebas de sobrescritura y FIFO son **modelos adversariales**,
no ingeniería inversa demostrada del servicio. Muestran por qué no debe
presentarse «API aceptó 0» como «ya no puede emitirse un incremento anterior».
El drenaje de 1,5 s existente no se presenta como prueba de entrega.
No se cambia a acknowledged, no se añaden retransmisiones ni paquetes nuevos.

## Carreras revisadas y cambios funcionales

- Incremento frente a LLANO: procesamiento serial, validación de enlace en cada
  orden, tasa de 1 s y deduplicación conservadas. La interfaz no admite dos
  cambios simultáneos mientras espera RPC. Las tramas admitidas en ANT siguen
  bajo la incertidumbre anterior.
- Parada frente a órdenes en cola: `ManualCommandFence` cancela antes de esperar
  al trabajador. Las aún en cola se rechazan; la parada admite un único cero
  por su ruta separada si el canal sigue válido. No se garantiza recuperar una
  llamada que ya entró en IPC. La respuesta Flutter tardía no revive la sesión.
- **Fallo encontrado y corregido:** antes, al recibir `CHANNEL_CLOSED` el callback
  SDK solo liberaba el latch; `radioDead` se marcaba después al llegar el evento
  al trabajador. Un incremento ya en cola podía ejecutarse en esa ventana.
  Ahora el propio callback marca radio no disponible y cancela la cola antes
  de publicar trabajo. `RX_SEARCH_TIMEOUT` hace lo mismo. El transporte además
  comprueba `AntTransmissionAudit.channelUsable` inmediatamente antes de usar ANT.
- `onChannelDeath` también invalida el diagnóstico y cancela de inmediato.
  **Otra corrección:** despertar el latch por muerte del canal ya no equivale a
  demostrar `CHANNEL_CLOSED`. La espera de cierre exige haber observado el
  evento real; un fallo se registra y no autoriza `unassign` como si existiera
  esa prueba. Si falla liberación, se conserva el estado de error y el bloqueo
  conservador de recursos; no se afirma recuperación limpia.
- Retorno de apertura atrasado: una apertura que retorna después de observar
  cierre/muerte no restaura `channelUsable=true`.
- Cierre frente a TX/transferencia tardíos: se conservan eventos incluso durante
  drenaje y cleanup, cuando las callbacks normales del trabajador ya se ignoran.
  Un evento TX no vuelve a abrir el canal ni confirma pendientes.

No se elimina la ventana física de una orden ya en curso. Android puede
suspender/matar el proceso o bloquear el IPC; no hay un callback de parada
mecánica garantizado. Esta incertidumbre mantiene el continuo bloqueado.

## Diagnóstico nuevo

`controlDiagnosticsVersion=6`, objeto JSON `transmissionDiagnostics`:

- `lastManualOrder`: último retorno correcto de una orden manual, separado de
  `lastStopCommand`, `stopResult`, `lastApiResult` y `lastControllerResult`.
- `channelUsable`, `openedAtMs`, `closeRequestedAtMs`, `closeApiReturnedAtMs`,
  `channelClosedEventAtMs`, `channelDeathAtMs`. Son tiempos monotónicos absolutos
  del dispositivo; comparar por diferencias, no con fechas UTC directamente.
- `channelEvents`: últimos 64 eventos con código, nombre, tiempo y correlación
  `unavailable`. `droppedChannelEvents` informa descartes; los contadores TX y
  transfer-completed conservan el total de la sesión.
- `broadcastDelivery=unacknowledged`, `physicalResistance=unknown`, programación
  de esclavo y ausencia de contrato de orden para múltiples escrituras.

La captura de eventos se hace en una clase sincronizada por conexión, desde la
callback del SDK; no efectúa llamadas ANT ni espera a la radio bajo su bloqueo.
No se toca el orden ni bytes de los comandos de pendiente. El panel desplegable
«Diagnóstico de transmisión ANT» muestra pendiente ordenada, última parada,
resultado de API, canal utilizable/cierre observado, número de TX y advertencia
física. JSON/CSV, telemetría y diagnósticos existentes permanecen disponibles.

## Validación automática y APK

- `flutter analyze`: sin incidencias.
- `flutter test`: **54 pruebas correctas**, incluido diagnóstico con cero fallido,
  TX sin correlación y pendiente manual conservada; permanecen las regresiones.
- `./gradlew :app:testDebugUnitTest`: **72 pruebas correctas**. Casos nuevos:
  incremento en cola mientras el callback confirma cierre, incremento/LLANO
  atrasados frente a parada, TX durante cierre, retorno de apertura atrasado,
  muerte sin evento de cierre, historial acotado y modelos adversariales de
  sustitución/FIFO/cierre que descarta o no descarta trabajo pendiente.
- Todos los canales y transportes de estas pruebas son simulados; no hubo
  transmisión real ni conexión con el rodillo.
- Se compila APK **porque se corrigieron carreras funcionales de cierre**, no
  solo por el documento: **1.1.7+10**,
  `build/app/outputs/flutter-apk/openbkool-1.1.7-10-debug.apk`.

Las pruebas no certifican el scheduler/IPC del S20 ni la aplicación física de
cero; tampoco demuestran la política interna real del búfer.

## Procedimiento físico breve y conservador — Galaxy S20

No desconectar deliberadamente ANT con resistencia elevada. No hace falta
probar +1 % ni provocar una avería para esta primera validación.

1. Con el rodillo estable y rueda inicialmente detenida, abrir una **nueva sesión**
   e identificar 30064/112/5, fabricante 67/modelo 22. Exportar el diagnóstico
   después de cada ensayo. Mantener trial 30 s; continuo sigue bloqueado.
2. Activar expresamente. Con pedaleo suave, solicitar **LLANO 0 %**, observar
   telemetría y resultado API; pulsar **Detener control** mientras está en llano.
   Comprobar cierre/estado final y ausencia de errores. No inferir efecto físico
   solo por el texto de API.
3. Solo si el ensayo anterior fue normal y resulta cómodo, nueva sesión:
   solicitar brevemente **+0,5 %**, después **LLANO 0 %**. Esperar a percibir la
   reducción y a que la telemetría permanezca normal, luego detener ya en llano.
   No acelerar la sucesión de botones ni provocar pérdida de señal.
4. En otra sesión, comprobar timeout permaneciendo en **0 %**; opcionalmente
   comprobar segundo plano también desde llano. Volver debe exigir nueva
   conexión/activación, sin reenvío de la pendiente anterior.
5. Si hay error, respuesta anómala o no se percibe reducción, dejar de pedalear
   y dejar que se detenga la rueda; no insistir con nuevas pendientes ni usar
   una desconexión deliberada como ensayo. Conservar el diagnóstico y detener
   el procedimiento. La aplicación no garantiza resistencia cero.

Revisar `manualControlEvents`, `commandQueue`, `transmissionDiagnostics` y las
operaciones `cleanup.closeChannel`/`awaitChannelClosed`. Interesa que el intento
único de cero preceda a la solicitud de cierre, que cierre se observe o se
informe error, y que no haya nuevas llamadas de incremento tras la parada.
Un TX después del intento de cero puede ser evidencia temporal útil, **no prueba
que ese cero fue el transmitido**. Ausencia de TX tampoco da esa respuesta.
Documentar observación mecánica por separado del JSON. No se afirma que esta
prueba descarte todos los fallos de búfer ni habilite el modo continuo.
