# Preparación de sesiones continuas — OpenBkool 1.1.4+7

Rama `feature/control-ant`. Se toma como validación física aportada por el usuario
la 1.1.3 en Galaxy S20: recepción, indicador, botones y cambios perceptibles de
resistencia. Esta validación no cubre todavía los fallos y el ciclo de vida de
1.1.4 descritos aquí.

**Continúan el máximo de 30 segundos por activación y el rango 0–1 %.**
`ManualControlPolicy` sigue centralizando máximo, paso y duración;
`continuousControlEnabled=false`. No hay opción para quitar el temporizador,
autorizar +2 %, reproducir GPX o mantener control en segundo plano. Codificación,
red PUBLIC/RF40/período32768, canal dedicado e ID 30064/112/5 sin cambios.

## Auditoría del ciclo de vida y protecciones

| Situación | Comportamiento |
|---|---|
| Inicio de pantalla/conexión | Telemetría y comprobación de identidad; ninguna orden automática. |
| Disponible | Canal dedicado, abierto, identidad exacta verificada, fabricante 67/modelo 22 y datos recientes. Requiere activación expresa. |
| Activación | Arma una sola ventana de 30 s; activar no envía pendiente. |
| Cambio manual | Valida de nuevo identidad, radio/canal, señal y telemetría, rango, duplicados, frecuencia y sesión. |
| Señal obsoleta | Señal de menos de 3 s; las métricas válidas deben tener menos de 10 s. El supervisor nativo revisa cada segundo y cada orden vuelve a comprobarlo. |
| Pérdida detectada | Se retiene el primer motivo de aborto (`terminalAbort`). Aunque vuelva la señal, no se permite recuperar el control de esa sesión ni reproducir la orden. |
| Muerte de canal/servicio | Se marca radio no disponible, se termina y libera; nuevas órdenes bloqueadas. |
| Parada manual/caducidad | Intento único de cero si todavía es admisible; drenaje existente de 1,5 s antes de cerrar, sin reintentos. |
| Pérdida de enlace | No se intenta cero a través de un canal no utilizable; se registra que no se pudo solicitar. |
| Salida de entrenamiento | Se espera la parada antes de abandonar la pantalla. Motivo `screen_closed`. |
| Segundo plano | Flutter detecta `paused`/`detached`; Android `MainActivity.onStop` conserva una segunda vía nativa. Motivo `app_background`. |
| Regreso a primer plano | No reconecta, no arma ni reenvía. Hay que crear conexión/sesión y activar expresamente. |
| Destrucción del motor/cierre del stream | Solicita parada con `engine_disposed`/`event_stream_closed`; liberación conservada. |
| Muerte forzada del proceso/teléfono | No hay garantía de ejecutar callbacks, enviar cero o persistir el JSON en memoria. No se deduce resistencia segura. |

El doble aviso Flutter/Android es intencional: `Session.finish` ya es idempotente
y conserva el motivo del primer cierre; no genera dos intentos de cero.
No se para por `inactive` de Flutter: un diálogo puede producir ese estado.
`stopOnExit=false` de la vista de diagnóstico anidada conserva su comportamiento;
la pantalla de entrenamiento exterior y Android supervisan el segundo plano.

La supervisión se ejecuta en el trabajador serial que ya posee el canal.
`ManualAntControl.supervise` no envía comandos. El primer fallo observado no se
borra si llega un paquete fresco antes del siguiente latido: se elimina así una
ventana de recuperación implícita. La sesión termina por la ruta existente de
`finish`; para recuperar se exige otra conexión y activación. Las comprobaciones
anteriores no se relajan.

## Estados y diagnóstico JSON

`manualControl.state` tiene valores explícitos, mostrados traducidos en la tarjeta:

| JSON | Interfaz | Significado |
|---|---|---|
| `inactive` | Inactivo | Sin activación y faltan condiciones de enlace. |
| `available` | Disponible | Condiciones nativas cumplidas, aún sin armar. |
| `active` | Activo | Ventana autorizada y enlace válido. |
| `stopping` | Deteniendo | No admite nuevas órdenes; termina el intento de cero/cierre. |
| `stopped` | Detenido | Cierre completado sin fallo, incluido timeout normal. |
| `error` | Error | Fallo de API, pérdida de enlace/radio o fallo de liberación. |

Se añaden eventos `control_state` con `from`, `to`, motivo, tiempo monotónico,
secuencia, identidad y UUID/hora añadidos por la sesión. `stopReason` conserva
el motivo de cierre; `closeComplete` distingue comienzo de parada de cierre.
Un error de liberación tiene transición de error con motivo `cleanup_failed`.
Los eventos de estado no reemplazan `lastResult`: se conserva el resultado real
de la orden, incluido error/rechazo. Permanecen los eventos de intentos, bytes,
retorno/error API, parada y operaciones de liberación. Se conserva el control
de orden de snapshots por `reportSequence`.

La tarjeta sigue separando seleccionada, pendiente ordenada por la API y
aplicación física no confirmada. Una bandera `enabled=true` obsoleta no oculta
`eligible=false` ni su motivo. «LLANO 0 %» y «Detener control» permanecen fijados
al pie durante la ventana, aun desplazando el registro; LLANO se bloquea cuando
no es admisible enviar, y detener permite completar/cerrar. No se presenta
cerrar el canal ni entregar cero a ANT como confirmación de resistencia cero.

## Pruebas y límites de la validación automática

- `flutter analyze`: sin incidencias.
- `flutter test`: **47 pruebas correctas**. Nuevas pruebas de `paused`/`resumed`
  con la pantalla real: una parada `app_background`, ninguna reactivación;
  cierre de pantalla con `screen_closed`; las seis etiquetas de estado; una
  bandera enabled antigua no oculta pérdida de enlace. Se mantienen las pruebas
  de secuencia manual, errores, snapshots atrasados, caducidad, BLE y diagnóstico.
- `./gradlew :app:testDebugUnitTest`: **53 pruebas correctas**. Incluye supervisión,
  pérdida/retorno de señal sin recuperación implícita, métricas obsoletas, canal
  cerrado, radio desconectada, fallo de API/liberación y motivos de cierre.
- Prueba de duración: seis horas de conexión disponible simulada sin armar ni
  transmitir; cambios durante 30 s, parada al límite y 24 h posteriores sin
  reactivación. **No se ha habilitado ni probado control activo de varias horas**:
  hacerlo exigiría saltarse el límite que deliberadamente se conserva.
- `flutter build apk --debug`: correcto. Versión **1.1.4+7**, archivo
  `build/app/outputs/flutter-apk/openbkool-1.1.4-7-debug.apk`.

Todos los transportes de prueba son falsos. Las pruebas Flutter verifican los
callbacks de WidgetsBinding y el RPC de parada; las Kotlin, la máquina de estados.
No sustituyen una prueba de la radio real ni del orden de callbacks nativos,
la cancelación IPC o las restricciones de Samsung. No se han enviado comandos
reales durante el desarrollo.

## Antes de retirar los 30 segundos

Pendiente de validación física, conservando todavía 30 s y +1 %, en S20 y S7:

1. Exportar JSON de parada manual y de caducidad, revisar identidad, último éxito
   manual, intento de cero, drenaje, recursos liberados y efecto perceptible.
2. Probar pérdida de señal y desconexión de ANT Radio Service/radio: se debe
   bloquear el control, registrar error y no reactivarse al recuperar señal.
3. Probar salir de pantalla, inicio del teléfono/segundo plano y bloqueo de pantalla;
   al regresar debe estar detenido/error y exigir reconexión y activación.
4. Comprobar reconexión tras cada fallo: no reproducir la pendiente anterior,
   no duplicar cero/cierre, no perder canales ni confundir el dispositivo.
5. Acordar una política para el caso en que no pueda llegar cero o muera el proceso:
   el protocolo no confirma efecto físico. Validar que el comportamiento real
   de parada sea aceptable; no basta con un retorno correcto de la API.

Después harán falta una revisión expresa para habilitar el modo continuo,
pruebas activas largas de radio/batería/latencia y una estrategia de registro
durable o acotado para sesiones largas. Actualmente JSON y eventos de control
permanecen en memoria hasta exportar; el CSV sigue registrando telemetría.
La lista de eventos de control no se trunca durante estas pruebas limitadas;
antes de permitir horas activas hay que resolver su crecimiento y conservación
ante cierre forzado. Ningún resultado automático de este cambio autoriza por
sí solo retirar el temporizador ni ampliar la pendiente.
