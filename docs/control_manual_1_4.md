# OpenBkool 1.4.0+18 — control manual por perfiles

Fecha: 16 de noviembre de 2026. Rama `feature/control-ant`.

## Decisión de autorización física

Se habilita **el rango original completo −5 % a +15 %, paso 0,5 %, como perfil
experimental autorizado expresamente por sesión**. No se desbloquea por enviar
un comando, por un TX ni por recibir 0x11. No exige una APK por cada porcentaje.
El consentimiento no se guarda entre sesiones y no envía la selección previa.

La decisión se fundamenta en una combinación de evidencias, no en una garantía
inexistente de ANT:

- La interfaz original y su ruta real hasta `TrainerBkoolPro1` utilizan ese
  rango de 41 pendientes, incluidas negativas y extremos, sin un clamp +1 %
  para Pro1. El formato está contrastado con la implementación original.
- El usuario comunica aumento/reducción de resistencia en 0 %, +0,5 %, +1 %,
  +2 % y +3 %. **No se han medido todos los puntos intermedios**, pendientes
  negativas ni valores superiores a +3 %.
- El ensayo 1.3.1 documentó reenvíos y parada sin órdenes posteriores a nivel
  de aplicación/API. En 1.3.2 el usuario comunica **81,696 s** de sesión física,
  cambios 0/+0,5 %, refrescos y parada/cierre registrados correctamente. Esta
  última duración se toma de su informe; no se presenta como una nueva captura
  independiente analizada aquí.
- Las simulaciones cubren sesiones de dos horas, cambios, fallo de envío,
  pérdida de enlace, segundo plano y carreras de parada/refresco.
- El usuario comprobó en este montaje de fricción que puede dejar de pedalear,
  permanecer estable y esperar a que se detenga la rueda sin ayuda de app/ANT.
  Esto permite abandonar el esfuerzo, **no certifica liberar el freno**.

Con estas evidencias se considera justificable **ofrecer la elección experimental
informada**, manteniendo supervisión y recuperación independiente, sin afirmar
que todo el rango tenga una respuesta física conocida o una curva calibrada.
Se revisa explícitamente la política anterior: la captura RF sigue pendiente,
pero ya no se usa como requisito absoluto para esta autorización experimental.
Sí impide afirmar entrega/orden garantizados o certificar una parada mecánica.
No se elimina ninguna validación de identidad, enlace, parada o consentimiento.

## Perfiles físicos disponibles en la misma pantalla

| Perfil | Rango autorizado al iniciar | Alcance |
|---|---|---|
| Carga baja | 0/+0,5 % | Sesión supervisada ya disponible en 1.3.2. |
| Positivo | 0..+3 %, paso 0,5 % | Perfil inicial de la pantalla; incluye puntos intermedios no probados individualmente. |
| Original experimental | −5..+15 %, paso 0,5 % | Los 41 valores con consentimiento específico; negativos y superiores a +3 % sin validación física comunicada. |

Todos carecen de vencimiento fijo. La selección del perfil no arma el control.
El perfil no puede cambiar mientras el control está activo; para ampliarlo hay
que detener, iniciar una conexión nueva y autorizar otra sesión. No hace falta
cambiar de APK ni realizar otra pantalla de diagnóstico.

Kotlin valida `confirmed`, `experimentalConfirmed` y un `rangeProfile` reconocido
antes de habilitar `manual_session`. Congela `authorizedRange` durante esa sesión.
Una llamada directa al canal sin perfil/consentimiento o fuera del rango se
rechaza sin invocar el transporte. Los valores no finitos, fuera de −5/+15 o
que no sean múltiplos de 0,5 también se rechazan. El perfil bajo conserva su
modo nativo `manual_low_load`; `manual_session` permite además los tres perfiles
explícitos. El antiguo `continuous_experimental` sigue deshabilitado y no se usa
para el nuevo entrenamiento. Los modos históricos de 30 s permanecen para
compatibilidad/diagnóstico y no definen el límite de la pantalla 1.4.

## Uso de la pantalla única

1. Inicio → **Control manual 1.4**. Conectar 30064/112/5. Esperar identidad
   actual, fabricante **67**, modelo **22**, canal dedicado abierto y telemetría
   fresca. Un rodillo recordado no equivale a conexión verificada.
2. Elegir perfil. El selector de pendiente muestra **siempre los 41 valores**;
   los que exceden el perfil se marcan **previsualización**. Se puede explorar
   el selector sin conectar o sin activar: no envía órdenes.
3. Pulsar **Autorizar sesión manual** (o Iniciar sesión supervisada en el
   perfil bajo), leer el rango y las limitaciones y confirmar. Cancelar no arma.
   Confirmar tampoco envía automáticamente el valor preseleccionado.
4. Con control activo, elegir un valor autorizado solicita expresamente el envío.
   `−` y `+` cambian 0,5 %. Se mantiene el limitador de una solicitud por segundo.
   Elegir un valor fuera del perfil solo cambia la previsualización: no se
   transmite, no sustituye el objetivo aceptado ni sus refrescos. LLANO permanece
   disponible para volver a solicitar cero aunque la selección sea una vista
   previa exterior al rango. Los botones ± se desactivan en esa vista previa.
5. Observar por separado **pendiente seleccionada**, **pendiente solicitada** y
   **pendiente ordenada** (último retorno correcto de API). Un fallo/rechazo no
   reemplaza el último éxito. La velocidad/potencia/cadencia no sobrescriben
   esa orden. El tiempo de entrenamiento y DETENER permanecen visibles.
6. **LLANO 0 %** mantiene la sesión y cambia la consigna. **DETENER CONTROL**
   finaliza la sesión. El perfil original no prescribe empezar con un salto a
   un extremo: empezar con carga conocida y usar cambios deliberados según
   tolerancia. No interpretar pendiente negativa como motor, impulso o
   aceleración real de la rueda.

La barra inferior conserva LLANO y DETENER; no depende del desplazamiento de
la lista. Las herramientas de eventos/hex, JSON, CSV, BLE y ANT siguen accesibles.
La pantalla libre anterior y sus ensayos históricos se conservan por
compatibilidad; el nuevo control de perfiles se utiliza en `ManualRidePage`, sin
crear pantallas adicionales. Spinning sigue siendo guiado: no se envían pendientes
al cambiar intervalos y no se habilita control automático ni GPX.

## Reenvío y parada sin cambios silenciosos

No se cambia la codificación de Pro1, el firmware, la red PUBLIC, RF40 ni el
período32768. El reenvío utiliza el trabajador serial existente y **solo el
último objetivo aceptado por API**. Cadencia aproximada de cinco segundos; no
cola de refrescos, no ráfaga para recuperar ticks atrasados ni restauración de
consignas previas. No hay refrescos antes de la primera orden aceptada.

Se limita además la admisión nativa a **una orden pendiente**: nuevas solicitudes
mientras ese hueco esté ocupado se rechazan como `command_busy`, sin acumularlas.
La orden en ejecución puede estar ya dentro de IPC y no se puede retirar. Flutter
mantiene su propio bloqueo de operación en curso. El JSON de cola registra los
rechazos por ocupación. Detener no espera a obtener ese hueco: invalida y cancela
inmediatamente los objetivos pendientes y el heartbeat.

La secuencia de parada de producción **no cambia**: invalidar/cancelar, intentar
una pendiente cero si sigue siendo posible según la política existente, esperar
el drenaje de 1,5 s, solicitar cierre, esperar CHANNEL_CLOSED y liberar. El cero
puede intentarse con métricas obsoletas si el canal sigue abierto e identificado;
un error incierto conserva la política existente de no reintentar. No se añade
resistencia básica cero ni se cambia al modo básico. Fallos de envío, cero o
cierre siguen visibles y registrados. No se afirma resistencia neutralizada.

Pérdida de señal/canal, segundo plano y salida de pantalla finalizan el control.
Una vuelta a primer plano o reconexión nunca reactiva ni recupera una pendiente.
Si Android mata el proceso sin callback no hay garantía de poder enviar cero.
Ante resistencia inesperada o un fallo, dejar de aportar esfuerzo y esperar
estable a la detención según la recuperación comprobada. No desmontar fijaciones
ni acercarse a piezas móviles; cortar alimentación no demuestra liberar el freno.

## Qué dice realmente ANT y la página 0x11

`setBroadcastData()` sin excepción significa retorno de API, no ACK del rodillo,
ni aplicación mecánica, ni orden de RF demostrado. Los TX carecen de asociación
con un payload concreto. El búfer de radio y una IPC iniciada no pueden cancelarse
de forma verificada desde esta app. Los cinco segundos no se presentan como
watchdog del firmware.

Se conserva `telemetry.page11Observation` íntegra: payload, bytes 4–5, entero LE,
fecha monotónica, edad y marca de semántica no verificada. El código original
Pro1 no interpreta 0x11; el callback General Settings de su clase FE-C está vacío.
En el ensayo real 1.3.1, `20 4E` pasa a `52 4E` en bytes 4–5 después de ordenar
+0,5 %. Es compatible con una **hipótesis de objetivo reportado/eco**, pero no
basta para establecerla como contrato del firmware. No se usa para autorizar,
para confirmar una entrega ni para presentar resistencia aplicada. No hay nueva
interpretación mecánica o decodificación inventada en 1.4.

Una captura independiente de la dirección controlador→rodillo, con payloads y
reloj alineado, sigue siendo la comprobación necesaria para contrastar si el cero
salió antes del cierre y si hubo un objetivo anterior después. Debe distinguir
tráfico de control de telemetría y observar también después del cierre. Sería
una evidencia de esos casos, no una garantía universal del SDK/firmware.

## Referencias y trazabilidad

- [Límites originales y rutas Pro1](limites_smart_pro_v1.md):
  `research/jadx/sources/com/bkool/bkoolmobile/views/SessionForceView.java:20–22,193–207`,
  `EntrenamientoFragment.java:1031–1052`, `BkoolSensorAntPlus.java:214–219`,
  `TrainerBkoolPro1.java:213–224`. Fuentes locales excluidas de Git, misma
  evidencia original; no se extrapola más allá del rango de aquella interfaz.
- [Auditoría del búfer ANT](auditoria_buffer_ant_1_1_7.md).
- [Ensayo de reenvío y carreras 1.3.1](ensayo_reenvio_parada_1_3_1.md).
- [Datos concretos del S20, página 0x11 y autorización limitada 1.3.2](control_prolongado_1_3_2.md).
  Su bloqueo histórico del rango completo queda sustituido por la decisión
  experimental por perfiles documentada aquí, no por nueva certeza RF.
- `manualControlEvents.enabled.authorizedRange` y
  `manualControl.authorizedRange` registran perfil y límites autorizados;
  `allValuesPhysicallyValidated=false`. `manualSessionPolicy.profiles` publica
  los rangos, `radioOrderingVerified=false` y consentimiento obligatorio.
  `experimentalSlopePolicy.scope=legacy_isolated_trials_only` evita confundir
  los topes de diagnósticos antiguos con los de una sesión 1.4 autorizada.

## Verificación y artefacto

- `flutter analyze`: sin incidencias.
- `flutter test`: **84 pruebas correctas**.
- `./gradlew :app:testDebugUnitTest`: **115 pruebas correctas**, cero fallos,
  errores u omisiones.
- `flutter build apk --debug`: compilación correcta; avisos previos de Gradle/Java.
- Se conservan las pruebas de BLE, ANT, telemetría, CSV, navegación y spinning
  guiado. Los escenarios nuevos prueban perfiles y sus rechazos, las 41 órdenes,
  vista previa exterior al perfil y carreras de parada antes/durante refresco.
- APK: `build/app/outputs/flutter-apk/openbkool-1.4.0-18-debug.apk`.

No se ha realizado una nueva validación física con 1.4.0 durante esta entrega.
Todas las pruebas automatizadas utilizan transportes simulados, sin comandos físicos.
