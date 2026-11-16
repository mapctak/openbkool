# Auditoría y modo continuo preparado — OpenBkool 1.1.6+9

Rama: `feature/control-ant`. **El modo continuo queda preparado y probado con
transporte simulado, pero bloqueado para uso físico.** La APK conserva como único
modo operativo la prueba de 30 segundos, con máximo +1 % y activación expresa.
La interfaz identifica «Continuo experimental · bloqueado» sin permitir elegirlo.
No hay preferencia, argumento RPC ni reanudación que retire ese bloqueo.

La validación física aportada de 1.1.3/1.1.4 demuestra telemetría, pendientes,
indicador, parada, timeout y salida a segundo plano en S20. No demuestra qué
sucede con el búfer ANT, un cero fallido, muerte del proceso o pérdidas de enlace
durante una sesión larga. Esta nueva APK no se ha probado con el rodillo.

## Auditoría de las rutas reales

| Escenario | Ruta revisada y resultado |
|---|---|
| Desaparece la telemetría con pendiente activa | `manualLink()` usa datos de esta conexión: señal <3 s y métricas válidas <10 s. `ManualAntControl.abortReason()` retiene el primer fallo; el latido nativo de 1 s y cada solicitud comprueban enlace. No se permiten nuevos aumentos ni se reactiva al recibir de nuevo. |
| Canal muere/cierra | `onChannelDeath`, `onServiceDisconnected` y eventos de canal en `AntTrainerSearch` marcan radio no disponible y finalizan. Se mantienen identidad exacta y liberación de recursos. |
| Android pasa a segundo plano | `TrainingPage` observa `paused/detached`; `MainActivity.onStop` mantiene la vía nativa. La primera parada cancela la sesión; llamadas duplicadas no repiten el cero. |
| Regreso a primer plano | No hay reconexión, activación ni reproducción automáticas. Se requiere una nueva conexión y autorización. |
| Suspensión del proceso | Los callbacks/latidos requieren CPU. Al recuperar ejecución, las comprobaciones usan tiempo monotónico; no se puede garantizar solicitar cero durante la suspensión. |
| Android mata el proceso/teléfono apagado | Puede no ejecutarse ningún callback. El rodillo puede conservar resistencia; no existe garantía de cero ni exportación del JSON que esté solo en memoria. |
| Salir de entrenamiento | `PopScope` espera parada/cierre; diagnóstico anidado conserva su comportamiento. No se bloquea el hilo de interfaz con operaciones ANT. |
| Órdenes en cola al parar | Se cancelan las aún no admitidas al procesamiento mediante `ManualCommandFence`; nunca se reproducen al reconectar. |
| Orden ya dentro de IPC/búfer de ANT | No se puede retirar con la cancelación de la aplicación. El transporte actual no implementa una cancelación verificada del búfer del servicio/radio. Estado exportado: **desconocido**, no cero pendientes. |
| IPC bloqueado | El trabajador serial puede esperar dentro de la llamada SDK; la petición de cancelación es inmediata y no espera su bloqueo. Flutter tiene timeout RPC y bloquea nuevas órdenes por incertidumbre. Esto no interrumpe una llamada nativa ya iniciada ni garantiza ejecutar a tiempo el latido/cero. |
| Resistencia tras cierre/error | Siempre desconocida; ni cerrar, ni retorno correcto de `setBroadcastData`, ni esperar drenaje confirman el efecto físico. |

## Protecciones añadidas

### Cancelación de aplicación y diagnóstico honesto

`ManualCommandFence` mantiene un contador atómico de órdenes que esperan al
trabajador y el primer motivo de cancelación. Parada manual, segundo plano y
`finish()` cancelan antes de esperar a ejecutar el cierre. Cada orden se vuelve
a comprobar al salir de la cola y también antes de usar el transporte. Las
canceladas producen `command_cancelled` con método, porcentaje, motivo y
`apiCalled=false`; no se codifican ni envían. Las comprobaciones de UUID y estado
nativo permanecen.

`commandQueue` separa `pendingApplicationCommands` de `radioBufferPending=unknown`
y `radioBufferCancellation=not_verified`. `manualControl.pendingCommands` refleja
la cola de la aplicación; **no es una afirmación sobre el búfer ANT**. La barrera
no promete cancelar una orden que ya entró en la llamada ANT: incluso la ventana
entre la última comprobación y la llamada se trata como trabajo en curso, no
como un paquete radio que pueda recuperarse.

Flutter conserva la barrera de generación para no revivir una sesión con una
respuesta tardía. Ante excepción/timeout de RPC o error del stream añade
`controlTransportUncertain=true`, bloquea nuevas órdenes/activación y conserva
el intento de detener. El bloqueo persiste en snapshots de ese UUID, aunque
llegue una respuesta posterior; solo una nueva conexión lo reinicia. Una
respuesta RPC incierta no se presenta como orden aplicada.

### Cero de parada con telemetría obsoleta

**Cambio deliberado respecto a 1.1.4/1.1.5:** antes se omitía cero ante cualquier
`link_lost`, incluso si solo faltaban métricas recientes y el canal aún estaba
abierto. Ahora `ManualControlLink.stopReason()` mantiene obligatorios:

- Destino 30064/112/5 y canal dedicado abierto.
- Coincidencia exacta seleccionado/configurado/leído/recibido.
- Identidad verificada, fabricante 67/modelo 22 de esta conexión.
- Radio disponible y sesión nativa no cerrada.

Solo para **el intento único de cero durante parada** se excluyen los dos
bloqueos de frescura de señal/métricas. No se relaja ninguna condición de
activación ni de los cambios manuales, incluido el botón LLANO. Esto permite
intentar la petición documentada de cero cuando el canal aún permite usarla,
sin suponer que el rodillo siga escuchando. No se envía cero por una radio
muerta/canal cerrado/identidad dudosa, antes de haber activado, ni se reintenta
tras un fallo de API.

Se conserva el drenaje de 1,5 s existente tras retorno correcto del cero antes
de cerrar. Un cero no solicitado tras activación, cero fallido o liberación
fallida termina en estado **error** y muestra «Resistencia física actual
desconocida». No se muestra el mensaje de cero solicitado con éxito si hubo un
error. La última pendiente manual aceptada se conserva separada de la parada.

## Infraestructura de modos

`ManualControlMode` define:

| Modo | Duración | Máximo | Entrega |
|---|---|---|---|
| `trial_30s` | 30 000 ms | +1 % | Predeterminado y operativo, con confirmación por sesión. |
| `continuous_experimental` | Sin deadline fijo | +1 % | Solo autorizado en pruebas con transporte falso; bloqueado en APK. |

`ManualAntControl.enable` recibe el modo expresamente y rechaza valores
incorrectos o continuo no autorizado. `ManualControlPolicy.CONTINUOUS_PHYSICAL_ENABLED`
es **false**, se pasa explícitamente desde el controlador de producción y no
se puede cambiar mediante MethodChannel. Las pruebas inyectan autorización en
el constructor de la máquina de estados junto con un transporte falso. Ninguna
prueba abre una radio ni permite activar ese modo en la APK física.

En continuo simulado, `maxDurationMs` y `remainingMs` son nulos, no cero. El
supervisor conserva todas sus comprobaciones aunque no exista deadline.
`elapsedControlMs` avanza con reloj monotónico desde activación y se congela al
solicitar parada. Hay controles LLANO/Detener fijados y tiempo de control visible;
la interfaz entiende ambos modos sin interpretar nulo como una prueba caducada.
La selección física permanece bloqueada también en Flutter; modificar solo el
cliente no saltaría la validación Kotlin.

La codificación 0/0,5/1, la tasa de envíos, deduplicación y parámetros PUBLIC,
RF40/período32768 permanecen. No se habilitan +2 %, ERG, firmware ni GPX.
Se conservan BLE, identificación de la sesión actual, CSV y exportación JSON.

## Pruebas automatizadas

- `flutter analyze`: sin incidencias.
- `flutter test`: **53 pruebas correctas**. Modo trial por defecto, opción
  continua no seleccionable, interfaz con estado continuo simulado después de
  30 s, tiempo visible, fallo de cero sin falsa confirmación, bloqueo tras error
  RPC y parada permitida, regresiones de segundo plano, salida y snapshots.
- `./gradlew :app:testDebugUnitTest`: **64 pruebas correctas**. Dos horas con
  supervisor cada segundo y 241 cambios simulados, cero manual, cero fallido,
  señal obsoleta, radio/canal/identidad inválidos, reconexión sin reactivación,
  cancelación de órdenes mientras el trabajador está bloqueado y rechazo de
  continuo con la política de producción. Se conserva la prueba de timeout de
  30 s para el modo trial.
- `flutter build apk --debug`: correcto. **1.1.6+9**:
  `build/app/outputs/flutter-apk/openbkool-1.1.6-9-debug.apk`.

Los tests del trabajador usan un ejecutor simulado, no el Handler/servicio ANT
real. La prueba de error RPC usa una excepción simulada que recorre el mismo
bloqueo que un timeout; no prueba un Binder real atascado. Los callbacks Android,
la radio, latencia de entrega y efecto mecánico necesitan validación física.

## Por qué el continuo físico sigue bloqueado y qué falta

1. Validar en S20/S7 pérdida de señal con pendiente activa y nuevo intento único
   de cero cuando la radio sigue disponible; revisar JSON y efecto físico.
2. Validar cierre de canal/servicio y fallo de cero: error visible, ninguna orden
   nueva tras la parada y reconexión que exija nueva activación sin replay.
3. Investigar o medir el búfer del SDK/ANT tras `setBroadcastData`, una llamada
   en curso y cierre. No basta con cancelar la cola propia ni con un retorno void.
4. Probar suspensión, bloqueo, segundo plano y retorno bajo carga/IPC lento;
   registrar cuánto tarda en procesarse la parada. Documentar una política
   aceptable para muerte del proceso, donde no hay callback garantizado.
5. Antes de horas de uso físico, resolver conservación de eventos de control:
   JSON sigue en memoria hasta exportar y el historial puede crecer en continuo.
   Los anillos de mensajes/eventos generales están acotados y el CSV se conserva,
   pero no equivalen a un diario durable de todas las órdenes ante un crash.
6. Revisar esas evidencias y autorizar una futura habilitación experimental
   explícita, conservando trial como predeterminado y máximo +1 %. No cambiar
   solo una constante y asumir que las pruebas lógicas prueban una parada física.

Esta entrega satisface la preparación del modo continuo y su validación lógica;
**no autoriza uso físico sin límite ni afirma resistencia segura después de
una desconexión**.
