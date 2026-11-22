# Registros, identificación y LLANO en OpenBkool 1.5.1

## Sesión del Galaxy S20

Para `963a573f-5f5d-45bc-851d-421d5234b9bc`, el CSV descrito registra
`activity_stopped` a las 11:44:21.643 UTC, la decisión `app_background` y la
política `foreground_only`. La parada omite la solicitud de 0 % con
`never_enabled` y el CSV termina a las 11:44:22.666 UTC.
El JSON disponible también indicaba que el control nunca se habilitó, pero
carecía de eventos de parada. En 1.5.0 el botón JSON serializaba la última
instantánea Flutter, incluso si la sesión seguía activa, mientras que el CSV
se copiaba tras el cierre. La exportación carecía de una marca explícita del
momento de captura y el CSV carecía de UUID. Además, la transición final de
control se registraba después de cerrar el escritor CSV.

La evidencia facilitada es compatible con un JSON anterior al cierre. El
instante exacto de esa copia no queda demostrado. El CSV descrito indica
que esa conexión nunca autorizó el control. Los datos disponibles no
permiten atribuirle la secuencia −2 % → 0 % → +2 % ni reconstruir su envío.
En 1.5.0 la selección visible se actualizaba antes de que Kotlin aceptara el
cambio. Un gesto podía quedarse en Flutter, ser reemplazado, rechazado o
cancelado antes de la API.

## Exportación

Cada fila del CSV incluye el UUID en `session_id`. El informe JSON nativo
usa `sessionId`, `recordState` (`partial` o `final`), `updatedAt` y
`capturedAt`. El valor `updatedAt` indica la última publicación nativa y
`capturedAt` la hora de copia. Durante el entrenamiento el botón se llama
**Copiar JSON parcial**. Tras el cierre ambos botones solicitan el informe
final de la sesión mostrada. Una discrepancia de sesión devuelve error.

Kotlin publica el final tras completar la limpieza, escribir la transición
de control y cerrar el CSV. Conserva el último informe final en memoria
durante la vida del controlador. No hace falta reconectar para copiarlo.
El CSV permanece en almacenamiento privado y la app no recupera el
informe tras reiniciar completamente el proceso. El CSV registra las
selecciones recibidas por Android, peticiones, colas, sustituciones, entrada,
retorno y error de SDK, cierre, enlace e identificación. El JSON añade la
auditoría acotada de gestos Flutter, incluidos los reemplazados antes de
Android. Un gesto seleccionado, una solicitud nativa y un retorno ANT
figuran como eventos distintos. El JSON indica los descartes de búfer.

## Identificación ANT

El código de Pro1 interpreta el modelo en los bytes 6–7 de 0x50. OpenBkool
exige además fabricante 67 en los bytes 4–5, modelo 22 e identidad de
canal exacta de esta conexión. 0x51 aporta revisión de software y número
de serie. Las páginas de telemetría 0x10 y 0x19 pueden llegar antes de una
0x50 utilizable. El informe descrito indica que faltaba esa confirmación
a los 53 segundos. No permite distinguir entre 0x50 tardía, ausente,
perdida o descartada. La transición 1.5.0 conservó el decodificador y sus
comprobaciones.

El registro distingue 0x50, 0x51, discrepancias de identidad y páginas de
identificación descartadas por falta de extensión ANT válida. Guarda bytes,
instante de recepción monotónico e interpretación. Tras 45 segundos desde
la apertura, si el bloqueo sigue siendo fabricante/modelo, muestra un
aviso y registra el hito. Si llega posteriormente la 0x50 válida y el
resto del enlace es apto, vuelve a estar disponible la autorización manual.
La recepción es pasiva. [Auditoría previa de identificación](identificacion_ant_1_1_5.md).

## LLANO

En el método `genericRequest` de `TrainerBkoolPro1.java` de la APK original
inspeccionada, la rama TrackResist calcula
`(int)((gradePercent + 200.0f) * 100.0f)` y envía el entero little-endian en
la página 0x33. La rama usa la misma fórmula con pendiente negativa, cero o
positiva. No aparece una operación extra específica para abandonar una
pendiente negativa. BasicResistance 0x30 es otra operación del original.
OpenBkool mantiene el comando de pendiente 0x33.

| Pendiente | Payload |
|---|---|
| −2 % | `33 FF FF FF FF 58 4D FF` |
| 0 % | `33 FF FF FF FF 20 4E FF` |
| +2 % | `33 FF FF FF FF E8 4E FF` |

El selector en 0 % y el botón LLANO usan la misma solicitud. El cero
reemplaza el objetivo diferido y un cambio posterior debe esperar a que
ese LLANO llegue a la API. Si se solicita antes, queda rechazado con
`flat_pending`. Los refrescos ceden ante el cero pendiente; el intervalo
mínimo ANT de 1.000 ms sigue vigente. Se puede solicitar 0 % de nuevo de
forma explícita. DETENER cancela los pendientes y conserva la secuencia
de parada. Una llamada ya iniciada queda fuera del alcance de la cola.
El retorno de la API y 0x11 dejan la entrega y la respuesta mecánica
sin confirmar. [Protocolo y fuentes inspeccionadas](protocolo_bkool.md).

## Validación

Las pruebas reproducen identificación retrasada y recuperación, rechazo de
identidad ajena, pendiente negativa → LLANO → pendiente positiva, LLANO
ante cambios pendientes y refrescos, cancelación tras parada, y copias
parcial y final con el mismo UUID. El tiempo de transmisión RF, la llegada
de 0x50 y la respuesta física a LLANO requieren una nueva prueba en el S20.
Se mantiene `foreground_only`. Bloquear el teléfono o dejar la app solicita
el cierre y registra `app_background`.
