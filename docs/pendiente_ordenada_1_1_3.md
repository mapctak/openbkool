# Indicador de pendiente ordenada — 1.1.3+6

Trabajo en `feature/control-ant`, sobre los cambios 1.1.2 existentes. No cambia
la codificación, el transporte ANT, los límites 0–1 %, el temporizador de 30 s,
la identificación 30064/112/5 ni las validaciones/parada. Sin comandos reales en
las pruebas automatizadas.

## Flujo revisado y fallo de presentación

1. `TrainingPage._requestSlope` registra `SlopeUiIntent.percent` en Flutter y
   llama `AntTrainerSearchController.manualAction('setManualSlope')` con el UUID.
2. MethodChannel `openbkool/training` llega a `Session.manualAction` en
   `AntTrainerSearch.kt`. `ManualAntControl.request` valida y registra la solicitud.
3. Solo el retorno correcto de `setBroadcastData` genera `api_returned`.
   Una excepción genera `api_error`; no confirma recepción ni efecto físico.
4. Kotlin publica un snapshot por EventChannel y devuelve otro por MethodChannel.
   `AntTrainerSearchController._update` notifica a `TrainingPage` y su
   `WorkoutSummary`/`ManualOrderSummary`.

El indicador grande de 1.1.2 usaba **`SlopePresentation.requested`**, alimentado
por `manualControl.lastRequestedPercent`, el historial de solicitudes o la
intención Flutter. No usaba `lastApiSuccess` como fuente del valor grande.
`lastSubmittedPercent` era también un fallback para solicitudes sin historial.
Estos campos representan acciones diferentes: un cero final no informa sobre
los valores ordenados previamente durante la sesión. El presentador además
mezclaba `api_returned` de parada con `api_returned` manual en `apiPercent`.

Se encontró otra vulnerabilidad concreta: `_update` reemplazaba el snapshot sin
ordenar las respuestas RPC frente a eventos. Un snapshot RX anterior con valor
cero podía sobrescribir uno posterior con +0,5/+1. Las pruebas anteriores
inyectaban snapshots ordenados o utilizaban un controlador de pantalla falso;
no probaban este intercambio por ambos canales. Ahora una prueba reproduce la
regresión enviando deliberadamente esos snapshots atrasados.

**Límite de la conclusión:** la secuencia JSON final aportada por el usuario
confirma los envíos, pero no contiene una traza temporal de los snapshots que
recibió la interfaz. No demuestra por sí sola que esa carrera fuera el motivo
exacto del cero persistente en el teléfono. Se corrigen la fuente incorrecta del
indicador y la posibilidad de regresión reproducida; no se afirma haber observado
la pantalla del S20 ni su orden real de callbacks.

## Estado separado y actualización

- **Seleccionada:** `SlopeUiIntent.percent` y, al procesarse en Kotlin,
  `lastRequestedPercent`. Se muestra en texto secundario, incluso pendiente o
  rechazada; nunca como orden entregada.
- **Pendiente ordenada:** `lastManualApiSuccess.requestedPercent`, guardado
  exclusivamente en un retorno correcto de la API para una orden manual.
  Es la fuente del indicador grande. Antes del primer éxito muestra «—».
  Se muestra +0,5/+1,0 o 0,0 con coma decimal. Un error no lo reemplaza.
- **Última parada:** `lastStopCommand` conserva su propio evento, porcentaje,
  bytes, resultado o error. No sustituye el último éxito manual. Se conservan
  además `lastApiSuccess`, `lastApiError`, `lastSubmittedPercent` y todos los
  eventos para compatibilidad y reconstrucción.
- **Resistencia física:** desconocida. La API no confirma aplicación.

Snapshots nuevos incluyen `controlDiagnosticsVersion=3` y `reportSequence`,
contador creciente dentro del UUID de sesión. Flutter ignora snapshots de esa
misma sesión con número inferior al ya recibido. Los snapshots siguen siendo
completos: la publicación de telemetría no reinicializa los campos de control.
El contador se reinicia únicamente al comenzar otra sesión. No se altera el
contenido del protocolo radio.

La prueba no espera una página 0x10/0x19 para actualizar la pendiente: basta la
respuesta de la operación manual o su evento de estado. El historial conserva
secuencia, UUID, hora, bytes, retorno/error y bandera `stopRequest`.

## Interfaz y parada

Controles manuales: **[ − ] [ LLANO 0 % ] [ + ]**. Se conservan también los
accesos fijos «Solicitar 0 %» y «Detener control». LLANO es una petición de
pendiente cero; no implica resistencia nula físicamente confirmada.

Después de finalizar, si el intento de cero retornó correctamente:

> Control finalizado · Se solicitó 0 % · Resistencia actual desconocida

Durante el drenaje aún se indica que se está deteniendo. Si el cero falló o no
se pudo solicitar, se muestra ese resultado y no el mensaje de éxito anterior.
El último porcentaje manual permanece como «Última pendiente ordenada».
Caducidad, pérdida de señal/canal y salida conservan su política original.

## Validación

- `flutter analyze`: sin incidencias.
- `flutter test`: 43 pruebas correctas.
- `./gradlew :app:testDebugUnitTest`: 49 pruebas correctas, transporte falso.
- `flutter build apk --debug`: correcto, versión 1.1.3+6.
- APK: `build/app/outputs/flutter-apk/openbkool-1.1.3-6-debug.apk`.

`manual_session_sync_test.dart` usa el controlador de producción y simula ambos
canales: activación expresa → +0,5 → +1 → +0,5 → 0 → parada. Comprueba cada valor
aceptado, inyecta un snapshot antiguo y otro RX actualizado entre cada transición,
y verifica el mensaje final y el historial. Las pruebas de pantalla adicionales
comprueban selección pendiente, error/rechazo con el éxito previo conservado,
caducidad y bloqueo de acciones por indisponibilidad. Kotlin prueba la secuencia
completa y la separación entre último éxito manual y orden de parada.

BLE, diagnóstico ANT, búsqueda, conexión directa, CSV y JSON permanecen; sus
pruebas de regresión están incluidas. No se ha verificado físicamente esta APK.
Para comprobarla, instalar 1.1.3+6 y comparar el indicador con
`manualControl.lastManualApiSuccess.requestedPercent`, no con el cero del JSON
final. Conservar `reportSequence`, UUID y eventos al exportar un nuevo diagnóstico.
