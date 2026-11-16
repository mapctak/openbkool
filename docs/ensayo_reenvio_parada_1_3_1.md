# Ensayo de reenvío y parada ANT — OpenBkool 1.3.1+16

**Disponible para ensayo físico acotado:** modo `refresh_trial_30s`, solo
0 % y +0,5 %, máximo 30 segundos desde la autorización. **`manual_session`
permanece bloqueado**; ningún resultado de este ensayo lo desbloquea automáticamente.
No cambia firmware, formato 0x33, RF40/PUBLIC/período32768, secuencia de parada
ni el antiguo modo continuo. No se transmite resistencia básica cero.

## Procedimiento breve en Galaxy S20

1. Mantener el montaje donde se comprobó poder dejar de pedalear y esperar
   estable a que se detenga la rueda sin ayuda de ANT/app. Preparar apoyo y
   acceso al aislamiento externo; un corte eléctrico no garantiza liberar el freno.
   No usar otra aplicación de control simultáneamente.
2. Si hay receptor/analizador independiente, iniciar captura **solo de recepción**
   antes del ensayo. Debe observar la dirección controlador→rodillo en este
   enlace; ver únicamente telemetría 0x10/0x19 del rodillo no demuestra capturar
   sus órdenes. Anotar equipo, archivo y referencia de reloj UTC.
3. Ajustes → Diagnósticos avanzados → **Reenvío y parada ANT**. Conectar
   30064/112/5 y esperar fabricante 67/modelo 22 de esta conexión y enlace fresco.
   Pulsar **Preparar ensayo de 30 s → Autorizar ensayo**. Confirmar no transmite.
4. Pulsar **Solicitar +0,5 %**. Con pedaleo suave, esperar unos 12–17 s para
   observar dos/tres refrescos aproximados de 5 s. El plazo de 30 s ya corre
   desde la autorización; no se reinicia con cada orden.
5. Pulsar **DETENER CONTROL directamente**, sin pedir LLANO previamente en
   este primer caso: se evalúa el cero de la propia parada. Observar por separado
   si disminuye la resistencia y guardar JSON/CSV al finalizar. Si no disminuye,
   dejar de aportar esfuerzo y usar la recuperación comprobada; no insistir con
   incrementos ni provocar desconexiones bajo carga.
6. Si hay captura independiente, continuarla unos 15 s después del cierre para
   detectar posibles órdenes de control tardías. La telemetría del rodillo puede
   continuar y no se considera por sí sola una orden tardía del controlador.

Después de revisar el primer caso, repetir **en sesiones nuevas y a la misma
carga baja** el vencimiento de los 30 s y el paso a segundo plano. LLANO está
disponible durante el ensayo: si se usa, pasa a ser el objetivo vigente y los
refrescos siguientes serán de cero. Anotar esa intervención para no confundirla
con el cero de Detener. No se requieren nuevas pruebas de cada pendiente.

Si el montaje cambió o no se cumple la salida independiente del esfuerzo, cancelar
la autorización. La respuesta física y la captura de este ensayo siguen pendientes.

## Comportamiento implementado

- Activación expresa y confirmación específica de reenvío; canal dedicado e
  identificación completa actuales obligatorios. Kotlin rechaza cualquier
  valor distinto de 0/0,5 en este modo, aunque se invoque directamente el canal.
- El trabajador serial existente consulta cada vez el último objetivo aceptado
  por la API. No guarda una cola de objetivos ni payloads capturados por un
  temporizador. Un tick retrasado produce como máximo un refresco; no recupera
  todos los ticks perdidos. Antes de la primera orden aceptada no hay refresco.
- Se conservan límite de frecuencia de 1 s, deduplicación de solicitudes normales,
  bloqueo por señal/canal, cancelación de cola, segundo plano y no reactivación.
- Detener invalida los objetivos inmediatamente mediante un indicador atómico,
  sin esperar al trabajador o a una IPC. El procesamiento serial conserva el
  último éxito para diagnóstico, pero ya no lo considera objetivo válido.
- El ensayo tiene además un vencimiento en el hilo principal: a los 30 s
  invalida y solicita finalizar incluso si el trabajador espera a ANT. No puede
  interrumpir una llamada ya iniciada; el cero/cierre deberán esperar su retorno.
  Por ello el límite no garantiza una duración mecánica exacta de la carga.
- Finalizar retira heartbeat y vencimiento, cancela órdenes pendientes e intenta
  **una pendiente cero** si siguen cumpliéndose las condiciones existentes.
  Conserva drenaje de 1,5 s, cierre y espera de CHANNEL_CLOSED/liberación. No hay
  reintentos de cero tras comunicación incierta ni nuevos comandos básicos.
- Una cancelación comprobada **antes de entrar en la API** se distingue de un
  fallo de IPC: no se marca falsamente como error de radio que suprima el intento
  de cero. Un error real/incierto conserva la política de no reintentar.

Una solicitud ya dentro del servicio/radio no puede retirarse de forma verificada.
El refresco no se interpreta como watchdog de seguridad del firmware.

## Registro para contrastar con una captura independiente

Campos dentro del snapshot de entrenamiento exportado en JSON:

| Campo/evento | Significado |
|---|---|
| `manualControlEvents`: `request`, `api_attempt` | Solicitud y preparación de llamada; payload, `commandId`, `targetRevision`, porcentaje, `periodicRefresh` y `stopRequest`. Un intento no prueba entrada en ANT. |
| `ant_api_entered`, `apiEnteredAtMs` | Marca tomada inmediatamente antes de invocar el SDK real, tras las validaciones. No es recepción RF. |
| `api_returned`, `apiReturnedAtMs` / `api_error`, `apiErrorAtMs` | Retorno de la llamada o error; mismo `commandId` que el intento. No son aplicación física. |
| `command_cancelled`, `apiCalled=false` | Cancelación comprobada antes de entrada en la API; no confundir con pérdida de entrega de una llamada iniciada. |
| `manualControl.stopRequestedAtMs`, `stopIntentReason` | Primera invalidación en el lado nativo, sin esperar al trabajador; puede proceder de Detener, segundo plano, vencimiento o pérdida de canal. No es la hora exacta del toque en pantalla. |
| Evento `stop_requested`: `stopProcessedAtMs` | Momento en que el trabajador procesa la parada; permite medir espera tras la solicitud. |
| `targetsInvalidated`, `refreshTargetPercent`, `targetRevision` | Objetivo invalidado/nulo tras parada frente al último envío conservado como historial. |
| `transmissionDiagnostics`: `closeRequestedAtMs`, `closeApiReturnedAtMs`, `channelClosedEventAtMs`, `channelDeathAtMs` | Petición y retorno de cierre, evento real y muerte de canal, por separado. |
| `radioCaptureCorrelation` | Reloj `android_elapsedRealtime_ms` y pareja aproximada `anchorMonotonicMs`/`anchorUtcEpochMs` para alinear con UTC. El reloj externo debe sincronizarse/verificarse aparte. |

Las marcas monotónicas usan la misma base temporal de Android. Las entradas
también conservan fecha UTC, UUID de sesión e identidad. La pareja de relojes
no calibra automáticamente el analizador ni garantiza sincronía exacta.
El `commandId` existe **solo en el registro de la app**, no se añade al paquete.

Payloads de ocho bytes, sin cabeceras/framing de la herramienta de captura:

```text
+0,5 %: 33 FF FF FF FF 52 4E FF
 0 %:   33 FF FF FF FF 20 4E FF
```

Repeticiones idénticas no permiten asignar inequívocamente cada trama RF a un
`commandId`. Los eventos TX conservan `commandCorrelation=unavailable`: ni su
proximidad temporal ni TRANSFER_TX_COMPLETED confirman este payload broadcast.
Guardar la captura bruta, JSON y observación física por separado; indicar
ausencia de receptor o limitaciones de dirección/framing y cualquier pérdida
de eventos (`droppedChannelEvents`). CSV sigue registrando telemetría.

## Criterios concretos de revisión

| Resultado a revisar | Criterio / consecuencia |
|---|---|
| Identidad y estado | 30064/112/5, fabricante67/modelo22 actuales, sin pérdidas ni errores no explicados. Si faltan, ensayo no válido. |
| Refresco | Objetivo +0,5 vigente, llamadas aproximadamente cada5s, sin ráfaga de recuperación de ticks ni objetivo antiguo después de un cambio aceptado. |
| Parada de aplicación | Invalidación inmediata; no nuevas entradas normales a API después de ella, salvo una invocación ya iniciada que debe identificarse como tal; un único cero de parada y ningún refresco posterior. Cancelación previa a API no cuenta como envío. |
| Cero y cierre | Cero aceptado por API, antes de pedir cierre; evento CHANNEL_CLOSED presente y liberación sin errores. Un cero fallido, canal muerto, marcas ausentes o orden inesperado impiden dar el caso por correcto. El evento cerrado puede adelantarse al retorno de `close()`; no imponer un orden falso entre ambos. |
| Observación física | Reducción percibida y ausencia de reaparición de carga; anotar cuándo, sin llamarlo neutralización certificada. Si no disminuye o reaparece, no avanzar. |
| Radio independiente, si existe | Contrastar bytes/dirección y tiempos; investigar cualquier +0,5 tardío. Un +0,5 después de un cero observado o después del cierre impide avanzar hasta explicar/corregir el caso. Ausencia observada en esa captura es evidencia acotada, no garantía universal. |

Sin captura independiente, se puede validar aplicación y observación física,
pero la cuestión del búfer/orden RF sigue **inconclusa**: API y TX no la resuelven.
No se exige provocar un corte ANT con carga; fallos y retardos pueden estudiarse
en banco con instrumentación. La revisión de los resultados físicos y de radio
debe terminar en una decisión explícita sobre la estrategia de parada y su
incertidumbre. Solo después se planteará un cambio revisado de la barrera nativa
de `manual_session`; no hay una casilla que lo habilite por realizar este ensayo.

## Pruebas automatizadas y entrega

Transporte simulado exclusivamente. Cubren consentimiento/rango, refrescos y
vencimiento; parada simultánea antes de API y durante una IPC; refresco retrasado;
cambio de objetivo; cierre de canal con retorno correcto o error; cancelación
previa a SDK sin suprimir cero; fallo de la última solicitud de cero; identidad,
tasa, pérdida de señal, segundo plano, órdenes canceladas y no reactivación.
La UI verifica que snapshots de refresco no generan envíos Flutter y que una
respuesta RPC atrasada no reactiva una sesión detenida.

Resultados: `flutter analyze` limpio; **82 pruebas Flutter y 106 Kotlin correctas**;
`flutter build apk --debug` completado. Gradle conserva avisos existentes de
deprecación/acceso nativo, sin errores. `git diff --check` correcto.

APK: `build/app/outputs/flutter-apk/openbkool-1.3.1-16-debug.apk`.
Sin comandos físicos durante las pruebas. La entrega actualiza el PR #1 desde
`feature/control-ant`; `main` no se modifica. Ningún ensayo físico/radio de
esta versión se da todavía por superado.
