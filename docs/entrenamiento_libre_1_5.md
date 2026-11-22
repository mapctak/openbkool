# Entrenamiento libre en OpenBkool 1.5

Inicio ofrece **ENTRENAMIENTO LIBRE** y la selección del rodillo. En el
entrenamiento se conecta por ANT, se revisa la telemetría y se autoriza el
rango de −5 % a +15 % en pasos de 0,5 %. La conexión y la autorización
dejan la consigna vacía hasta que el usuario pide una pendiente. Las
pendientes negativas y mayores de +3 % son experimentales. La respuesta
física del conjunto de 41 posiciones sigue sin verificarse.

Se retiraron la segunda pantalla de control manual, las pantallas de
pendientes experimentales y de reenvío, los ensayos de 30 segundos, la
preparación de pendientes sin transmisión y los tres perfiles. Se retiraron
también la navegación de spinning guiado y el acceso de GPX sin implementación.
La consulta de capacidades ANT se integra en el diagnóstico avanzado existente.
Se conservan la selección persistente, el descubrimiento ANT y BLE, la
telemetría, el códec propietario y los registros. Git conserva la documentación
histórica de los ensayos retirados. Las capturas y auditorías técnicas que
siguen explicando la radio permanecen en el repositorio.

## Control y parada

El controlador verifica el canal dedicado, la coincidencia de identidad
seleccionada, configurada, leída y recibida, el fabricante 67, el modelo 22
y la frescura de señal y métricas antes de autorizar. La protección física
sigue limitada al equipo validado 30064/112/5. Una pérdida de potencia puede
suspender el control y mantener telemetría parcial. Una pérdida de enlace
sigue cerrando la sesión. La autorización pertenece a la conexión y acaba
con ella.

En Kotlin hay una sola consigna pendiente y se conserva el objetivo aceptado
para el refresco cada cinco segundos. Flutter conserva el último gesto
mientras responde el canal de plataforma para no acumular llamadas.
Un único temporizador nativo atiende el próximo despacho y la supervisión del enlace.
Un cambio pendiente tiene prioridad sobre el refresco. El transporte conserva
el intervalo de 1.000 ms. Los pasos rápidos que ya debían esperar pueden
consolidarse durante 180 ms, en paralelo con ese límite. La selección
directa y LLANO respetan el límite sin esa espera extra. DETENER invalida
órdenes antes de encolar el cierre. La secuencia conserva una sola solicitud
de 0 % si el enlace lo permite, 1.500 ms de drenaje si retorna la API y el
cierre nativo. Una orden que ya entró en la API y el estado físico posterior
siguen siendo inciertos. Las coincidencias de 0x11 aportan observación
numérica y carecen de valor de ACK o confirmación mecánica. [Auditoría del búfer ANT](auditoria_buffer_ant_1_1_7.md).

## Segundo plano y exportación

El Galaxy S20 siguió desconectándose con 1.4.2. En esta versión la política
es de primer plano. Se retiró el intento anterior de servicio y su
notificación. Android solicita la parada desde `MainActivity.onStop`.
Flutter deja esa decisión al controlador nativo. Al volver a la pantalla no
se restablecen ni la conexión ni la autorización. Una muerte completa del
proceso puede impedir la última solicitud de parada. Queda por verificar en
el S20 que el motivo y el cierre corresponden a la nueva política al bloquear
la pantalla o cambiar de aplicación.

**Copiar CSV** está disponible al terminar. **Copiar JSON** conserva el
estado y los eventos en memoria. El diagnóstico avanzado puede exportar
además el informe combinado de BLE y ANT. Los registros incluyen pendientes,
temporización nativa y de interfaz, respuestas del SDK, eventos ANT, estado
del enlace, motivos de parada y la transición al segundo plano. [Formato de telemetría y exportación](telemetria_ant.md).

## Validación

La suite cubre las 41 pendientes y la autorización por conexión, identidad
y configuración ANT, sesiones prolongadas, telemetría parcial, cambios rápidos,
LLANO, DETENER, reenvíos, errores, cancelación, navegación, exportación y
eventos de segundo plano. La latencia física y el comportamiento con el
rodillo real requieren una nueva prueba en el Galaxy S20.

Comprobaciones de entrega: `flutter analyze`, 28 pruebas de `flutter test`,
86 pruebas de `./gradlew :app:testDebugUnitTest` y `flutter build apk --debug`.
