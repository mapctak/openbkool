# Control manual OpenBkool 1.3.0+15

Rama `feature/control-ant`, revisión 2026-11-16.

Actualización 1.3.1+16: [ensayo acotado de reenvío y parada](ensayo_reenvio_parada_1_3_1.md),
solo 0/+0,5 y 30 s, para reunir evidencia física/radio. `manual_session` sigue
bloqueado; el ensayo no lo habilita automáticamente.

**Modo prolongado preparado, pero bloqueado para uso físico.** La aplicación
ofrece una nueva pantalla y los 41 valores −5..+15 %, paso 0,5, con cero exacto.
Seleccionarlos en reposo solo previsualiza. La barrera nativa impide activar el
modo `manual_session`; no se puede evitar desde un MethodChannel ni activando
el antiguo modo continuo. Las pruebas aisladas de 30 s permanecen en diagnósticos.
No se amplía silenciosamente el máximo +1 del control ordinario ni se desbloquea
+4 en diagnósticos. El usuario ha comunicado respuesta física hasta +3 y retorno
al solicitar LLANO; los demás valores y el funcionamiento prolongado no están
validados físicamente.

## Formato original y pendientes negativas

`research/jadx/sources/com/bkool/sensors/tech/ant/devices/TrainerBkoolPro1.java:213–217`:

```java
int grade = (int) ((percentFloat + 200.0f) * 100.0f);
// 33 FF FF FF FF gradeLow gradeHigh FF
```

La interfaz original `SessionForceView.java:20–22,193–207` limita a −5..+15
en pasos 0,5. La ruta hasta Pro1 y los artefactos de JADX contrastados con DEX
están documentados en [limites_smart_pro_v1.md](limites_smart_pro_v1.md).
`encodePro1Slope` conserva Float y truncamiento originales, valida rango, paso
y finitud antes de convertir; no envuelve ni satura entradas inválidas.

| Pendiente | Entero | Payload ANT |
|---|---|---|
| −5 % | 19500 | `33 FF FF FF FF 2C 4C FF` |
| −0,5 % | 19950 | `33 FF FF FF FF EE 4D FF` |
| 0 % | 20000 | `33 FF FF FF FF 20 4E FF` |
| +0,5 % | 20050 | `33 FF FF FF FF 52 4E FF` |
| +3 % | 20300 | `33 FF FF FF FF 4C 4F FF` |
| +15 % | 21500 | `33 FF FF FF FF FC 53 FF` |

Los 41 puntos coinciden con la fórmula original y caben en LE16. Esto demuestra
compatibilidad de codificación, **no carga mecánica disponible o calibrada**.
La rama negativa usa la misma fórmula; no contiene una orden de motor o impulso.
No se infiere que la rueda acelere, que exista asistencia ni una curva concreta
de resistencia negativa. La pantalla muestra la solicitud y la última API
aceptada, siempre con aplicación física no confirmada.

## Interfaz y estados

Inicio → **Control manual 1.3**. `ManualRidePage` comparte conexión, telemetría y
transporte existentes, sin auto conexión ni envío al entrar. Incluye:

- Selector directo de los 41 valores y controles grandes − / LLANO / +.
- Pendiente seleccionada y última aceptada por API separadas; un rechazo/error
  no cambia el valor presentado como ordenado.
- Potencia, velocidad, cadencia, tiempo y estado de conexión/control.
- DETENER CONTROL permanente, disponible mientras pueda solicitarse la parada.
- Acceso a los registros JSON, CSV y diagnóstico existentes, sin eliminarlos.

En esta APK, la autorización y los botones de envío prolongado están desactivados
y se explica el motivo. El selector permanece disponible como previsualización,
sin llamadas ANT. Se puede conectar para observar telemetría y consultar registros.
Las pruebas de interfaz habilitan estados futuros únicamente mediante snapshots
simulados; **esa inyección no está expuesta en la aplicación**.

La infraestructura conserva estados inactivo, disponible, activo, deteniendo,
detenido y error. En una futura autorización revisada, iniciar requerirá un
consentimiento nuevo por sesión; confirmar no enviará el valor preseleccionado.
Cambiar selector/−/+ durante control autorizado solicitará el nuevo valor. LLANO
solicitará cero y continuará la sesión; Detener la finalizará. No hay fecha de
caducidad fija en el modelo de este modo, ni se añade un máximo alternativo.

## Reenvío de objetivo vigente

Original: `EntrenamientoFragment.java:602–616` cuenta cinco ticks de sesión,
Timer de 1000 ms (`:747–748`, `Constants.java:20`), y vuelve a solicitar pendiente
o ERG. Los cambios reinician contador y reemplazan Handler de 500 ms
(`:1031–1071`). Esto demuestra refresco normal, **no un watchdog de firmware**.

`ManualAntControl.refreshTarget`, llamado en el trabajador serial por el
heartbeat existente, prepara un equivalente de unos 5 s para `manual_session`.
En 1.3.0 estaba bloqueado físicamente. Desde 1.3.1 se reutiliza también en el
ensayo explícito y acotado `refresh_trial_30s`, sin habilitar `manual_session`.
El antiguo continuo y las pruebas individuales de pendiente conservan su comportamiento.

- No crea un temporizador por objetivo, cola de payloads ni tarea con pendiente
  capturada. Consulta la última pendiente cuyo envío aceptó la API.
- Un cambio aceptado reemplaza la consigna y reinicia la espera desde esa llamada.
  Solicitudes rechazadas no reemplazan el objetivo aceptado.
- Un heartbeat retrasado emite como máximo una vez; no recupera ticks perdidos.
- Se conserva la tasa mínima de un segundo entre intentos, incluidos refrescos;
  se rechazan cambios demasiado rápidos sin encolarlos. La parada conserva su
  excepción existente para intentar un cero aunque el envío anterior sea reciente.
- Cada refresco registra `periodic_refresh` y `periodicRefresh=true` con los
  eventos normales de payload/retorno/error. No se presenta como acuse del rodillo.
- Al perder enlace, fallar la API o detenerse, no vuelve a refrescar; recibir de
  nuevo telemetría no reactiva. Es necesaria una conexión/sesión y consentimiento
  nuevos. Antes del primer objetivo aceptado no hay nada que refrescar.

## Parada: revisión sin cambio de producción

Original: autopausa (`EntrenamientoFragment:622–640`) y destrucción (`:1109`)
solicitan modo básico cero; `stopSession:803–809` cancela el Timer. El botón de
finalizar pausa y abre el diálogo de guardar (`:453–454,596–598`), sin cero directo
en ese callback. No se cancela expresamente el Handler de 500 ms en esa secuencia.
`BkoolSensorAntPlus:232–237` pasa entero×2 a `BasicResistance`; Pro1 `:223–224`
construye `30 FF FF FF FF FF FF 00`. No se encontró paquete previo independiente
de cambio de modo: seleccionar la página es el cambio observado. El wrapper
`BkoolSensorAntWrapper:547–553` captura errores de broadcast y solo los registra.

Pendiente cero usa `33 FF FF FF FF 20 4E FF`. **No son órdenes equivalentes
mecánicamente demostradas.** No se cambia la parada actual a básica cero ni se
encadenan paquetes nuevos. Se conserva:

1. Cancelación inmediata de la cola de aplicación y bloqueo de nuevas órdenes.
2. Un intento de pendiente cero, condicionado al canal/identidad y estado de
   comunicación existentes. La telemetría obsoleta por sí sola no impide ese
   intento si aún hay canal válido; el canal muerto o comunicación incierta sí.
3. Espera existente de 1,5 s si la API retornó; cierre, espera de evento real
   CHANNEL_CLOSED y liberación. Un fallo no se presenta como cierre limpio.

Las pruebas seriales muestran que después de detener no se programan refrescos
ni salen objetivos normales pendientes; solo el intento de cero previsto. El
heartbeat se retira y las ejecuciones tardías consultan el estado detenido.
Los callbacks de pérdida de canal cancelan/inutilizan antes de publicar trabajo.
El transporte revalida canal y cancelación antes de cada llamada. Pasar a segundo
plano, cerrar pantalla o finalizar aplicación mantiene las protecciones nativas
y Flutter. Android puede matar el proceso sin ejecutar callbacks: no se promete
una última orden en ese caso.

## Impedimento concreto para habilitar físicamente

La cola de **nuestra aplicación** está controlada. No hay garantía documentada
de retirada/orden definitivo de comandos ya admitidos dentro de Android ANT o
la radio; tampoco de entrega del último cero antes del cierre. TX no identifica
payload ni demuestra aplicación mecánica. El drenaje de 1,5 s no prueba entrega.
Cerrar, enviar cero o cortar alimentación no garantiza resistencia neutralizada.
Véanse las fuentes oficiales y los modelos adversariales en
[auditoria_buffer_ant_1_1_7.md](auditoria_buffer_ant_1_1_7.md).

Por ello `MANUAL_SESSION_PHYSICAL_ENABLED=false` queda **independiente** del
antiguo `CONTINUOUS_PHYSICAL_ENABLED=false`. No se puede activar el nuevo modo
solo con `confirmed=true`, ni usando el modo experimental. Es necesario revisar
y cambiar deliberadamente la autorización de producción después de validar:

1. En carga baja ya probada y con salida independiente del esfuerzo preparada,
   comparar cambios y LLANO/Detener con refresco en un ensayo separado autorizado.
   Capturar bytes reales con receptor/analizador apropiado y marcas de tiempo;
   la proximidad de un evento TX no basta para atribuirle un comando.
2. Comprobar en S20/ANTLib real el posible envío tardío de objetivos anteriores,
   la última orden antes de CHANNEL_CLOSED y el efecto de parar/segundo plano.
   Para fallos/retardos de radio usar banco, sin exigir cortes deliberados bajo
   carga elevada con ciclista. No confundir orden de llamadas con orden de RF.
3. Observar por separado reducción física y ausencia de reaparición de carga;
   revisar si la espera/estrategia existente es suficiente o necesita otro
   mecanismo respaldado por documentación/medidas. No usar básica cero sin su
   propia evaluación explícita. Registrar las garantías que continúen faltando.
4. Revisar progresivamente la respuesta de pendientes aún no medidas y duración
   real con registros. Las pruebas de software hasta +15 y dos horas no sustituyen
   esas observaciones. Reautorizar cada sesión, nunca tras reconexión automática.

## Pruebas y entrega

Tests Kotlin nuevos: 41 codificaciones y entradas inválidas; barrera de producción;
dos horas simuladas sin timeout; objetivo vigente frente a ticks retrasados;
deduplicación/tasa; señal obsoleta, identidad/canal; parada y tareas canceladas;
fallos de refresco/cero, sin afirmar neutralización física.
Tests Flutter: rango, previsualización sin envío, navegación sin conexión, modo
bloqueado, consentimiento simulado, errores conservando último aceptado, LLANO
y parada distintos, segundo plano/cierre y tamaños S7/S20.

Resultados de la ejecución final:

- `flutter analyze`: sin incidencias.
- `flutter test`: **76 pruebas correctas**.
- `./gradlew :app:testDebugUnitTest`: **96 pruebas correctas**, cero fallos,
  errores u omitidas; incluye dos horas simuladas con refrescos del nuevo modo.
- `flutter build apk --debug`: compilación correcta. Avisos existentes de
  deprecación/acceso nativo de Gradle, sin errores.
- `git diff --check`: correcto. Sin comandos físicos durante pruebas automatizadas.

APK: `build/app/outputs/flutter-apk/openbkool-1.3.0-15-debug.apk`.

## Evolución 1.3.2+17

La decisión posterior al ensayo físico 1.3.1 está en
[control_prolongado_1_3_2.md](control_prolongado_1_3_2.md): se habilita solo el
perfil prolongado supervisado 0/+0,5 %, con consentimiento específico.
El rango físico completo `manual_session` sigue bloqueado; las conclusiones
históricas de este documento no constituyen autorización de ese rango.

## Evolución 1.4.0+18

[Control manual por perfiles 1.4](control_manual_1_4.md) sustituye el bloqueo
histórico del rango físico completo por autorización experimental explícita
por sesión. No representa una nueva garantía de entrega RF o aplicación física.
