# Pendiente y preparación del control continuo — OpenBkool 1.1.2+5

Rama: `feature/control-ant`. Operación conservada: PUBLIC, RF=40,
período=32768, canal específico para **30064/112/5**, fabricante 67/modelo 22.
No cambia el transporte `AntChannel.setBroadcastData`, ni se añade GPX o firmware.

## Discrepancia de indicadores y estado corregido

La revisión anterior está en [pendiente_interfaz_1_1_1.md](pendiente_interfaz_1_1_1.md).
En el código recibido para esta tarea ya hay un único `ManualOrderSummary`:
no hay un segundo indicador principal fijo a cero que permita reproducir
exactamente la pantalla instalada que describió el usuario. No se dispone de
una captura de versión/JSON de esa instalación; por tanto no se atribuye su
fallo físico a una línea que ya no existe en esta revisión.

Sí se identificaron dos debilidades concretas y reproducibles:

- `SlopePresentation.fromReport` reconstruía la solicitud mediante
  `manualControlEvents`, con fallback a `lastSubmittedPercent`. Solicitar y
  entregar a la API son estados distintos; un historial ausente no aportaba
  una fuente independiente de la última solicitud.
- Un evento `api_error` reemplazaba el último `api_returned` en el presentador,
  ocultando el último envío aceptado. No se conservaban ambos visualmente.

`ManualAntControl.snapshot()` exporta ahora `lastRequestedPercent`,
`lastApiSuccess` y `lastApiError`, además de `lastSubmittedPercent`.
Una parada que solicita cero no reemplaza la última selección manual.
Los valores canónicos no dependen de páginas 0x10/0x19 ni de retener el historial.
La intención Flutter (`SlopeUiIntent`, vinculada al UUID de sesión) actualiza
inmediatamente el indicador antes de la respuesta RPC; se marca pendiente o
sin registro si la respuesta falla. El historial sigue siendo compatible con
capturas anteriores.

El indicador destacado muestra **Pendiente solicitada: +0,5 %** o **+1,0 %**
(cero: **0,0 %**). Otro texto muestra la última orden entregada a la API ANT.
Errores y rechazos no se presentan como envíos aceptados y no borran el último
éxito. La aplicación física continúa explícitamente **no confirmada**.
Al parar/caducar, el título cambia a «Última pendiente solicitada» y el resultado
del intento de cero se muestra por separado; no se deduce resistencia cero.

## Protecciones para una futura sesión continua

Se conserva la máquina de estados existente, sin prolongar la prueba:

- Activación explícita por sesión, sin transmitir al entrar ni al activar.
- Canal dedicado abierto, radio disponible, sesión activa, coincidencia exacta
  del ID seleccionado/configurado/leído del adaptador/recibido; modelo y
  fabricante verificados en esta conexión.
- Comprobación antes de cada orden y parada; señal menor de 3 s y telemetría
  válida. El supervisor nativo revisa caducidad y pérdida de enlace. La muerte
  del canal o desconexión del servicio finaliza la sesión.
- La interfaz bloquea órdenes si Kotlin declara `eligible=false`, además de
  las barreras de sesión, temporizador y operación en curso. Kotlin mantiene
  la autoridad final aunque un estado Flutter esté atrasado.
- «Solicitar 0 %» y «Detener control» permanecen fijados al pie durante el
  control. El primero conserva las mismas validaciones y deduplicación;
  detener conserva el intento único de cero si el enlace sigue utilizable,
  espera existente y liberación. No hay reintento ni reactivación automática.
- Salir de entrenamiento finaliza la sesión. `MainActivity.onStop` detiene
  entrenamiento/búsqueda al pasar a segundo plano. No hay servicio de control
  en segundo plano. Un cierre forzado del proceso no garantiza enviar cero.
- JSON mantiene intentos, bytes, retorno/error de API, rechazos, pérdida de
  señal/canal, parada y liberación; añade los campos canónicos anteriores.

**Continúan 30 000 ms y máximo +1 %.** `ManualControlPolicy` concentra duración,
máximo y paso de 0,5; `continuousControlEnabled=false` se exporta explícitamente.
No existe una opción de usuario que autorice ampliar estos límites.

Antes de control continuo faltan pruebas físicas documentadas de pérdida de
señal, pérdida del servicio/canal, salida de pantalla, bloqueo del teléfono y
segundo plano, parada y caducidad, tanto en S7 como en S20. Revisar los JSON
con identidad, bytes, tiempos y resultado del cero; observar cuánto persiste
la resistencia si no llega el cero. Definir una política de parada y recuperación
aceptable para sesiones largas y probarla antes de cambiar el límite. Los tests
con transporte falso no verifican comportamiento físico, recepción radio ni
el callback real de ciclo de vida Android. No se garantiza una parada remota si
la conexión se pierde o el proceso muere.

## Codificación futura, sin habilitar +2 %

Referencia: [protocolo_bkool.md](protocolo_bkool.md),
[telemetria_ant.md](telemetria_ant.md),
[control_ant_preparacion.md](control_ant_preparacion.md) y fuente local excluida
`research/jadx/sources/com/bkool/sensors/tech/ant/devices/TrainerBkoolPro1.java`,
`genericRequest`, caso `TrackResist` (líneas 213–218):

```java
int grade = (int)((percent + 200.0f) * 100.0f);
// página 0x33, grade little endian en bytes 5 y 6
```

Se conserva el octeto final FF usado por la llamada original de pendiente.

| Pendiente | Entero | Trama candidata |
|---|---:|---|
| 0 % | 20000 | `33 FF FF FF FF 20 4E FF` |
| +0,5 % | 20050 | `33 FF FF FF FF 52 4E FF` |
| +1 % | 20100 | `33 FF FF FF FF 84 4E FF` |
| +2 % | 20200 | `33 FF FF FF FF E8 4E FF` |

`encodeSlopeCandidate` permite comprobar matemáticamente el candidato +2 %;
no es una autorización operativa. El único camino de envío sigue pasando por
`encodeManualSlope`, que rechaza +2 %. Una prueba verifica cero llamadas al
transporte al solicitar +2 % incluso después de activar. No se cambian los bytes
de 0/0,5/1. Antes de ampliar rango: revisar registros reales del usuario de esos
tres valores, parada manual/caducidad y efecto físico; autorizar y planificar
una prueba incremental separada. La fórmula está confirmada estáticamente;
la respuesta física de +2 % y cualquier garantía de resistencia siguen sin validar.

## Validación y comprobación en el teléfono

- `flutter analyze`: sin incidencias.
- `flutter test`: 42 pruebas; incluye valores 0/0,5/1, respuesta pendiente,
  actualización nativa sin nuevas páginas RX, rechazo/error conservando éxito,
  parada/caducidad y bloqueo visual por indisponibilidad de radio.
- `./gradlew :app:testDebugUnitTest`: 48 pruebas correctas, transporte simulado;
  codificación +2 %, rechazo operativo y campos de estado Kotlin incluidos.
- `flutter build apk --debug`: correcto. APK identificable:
  `build/app/outputs/flutter-apk/openbkool-1.1.2-5-debug.apk`.
- Sin conexión con el rodillo ni comandos reales durante estas comprobaciones.
  BLE, conexión directa, CSV y diagnósticos avanzados conservados; regresiones
  de navegación/diagnóstico incluidas en la suite Flutter.

Instalar 1.1.2+5 y abrir una sesión nueva. Tras habilitar explícitamente,
seleccionar +0,5/+1 y contrastar el indicador grande con
`manualControl.lastRequestedPercent` del JSON. Comprobar aparte
`lastApiSuccess.requestedPercent`, error si existe, y el aviso de aplicación
física sin confirmar. Al llegar a 30 s, verificar caducidad, cierre y el resultado
separado del intento de cero. Pendiente la verificación física de esta APK.
