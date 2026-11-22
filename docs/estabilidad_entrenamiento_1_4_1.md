# Estabilidad del entrenamiento ANT en 1.4.1

El 20 de noviembre de 2026, el CSV del Galaxy S20 registró el cierre a las
19:24:19 UTC tras 13:39 de sesión. La potencia llevaba 12.015 ms sin actualizarse,
la velocidad 3.015 ms y el rodillo todavía enviaba páginas ANT, incluida 0x54.
La causa fue `link_lost:telemetry_not_fresh`. La supervisión del control elevaba
a cierre de toda la sesión el fallo del requisito de velocidad, potencia y
cadencia válidas con menos de 10 s de antigüedad.

## Estado del enlace y parada

- Las páginas identificadas del rodillo mantienen la recepción. Potencia, cadencia
  y velocidad tienen su propia validez. Con recepción activa y alguna métrica
  indisponible, la interfaz muestra telemetría parcial y un guion en su lugar.
- Si falla el requisito de métricas con el control habilitado, se revoca la
  autorización para esa conexión. Se cancelan cambios pendientes y refrescos.
  Se usa la solicitud existente de 0 % una sola vez cuando el canal permite
  enviarla. Si el usuario finaliza durante los 1.500 ms de drenaje, el cierre
  espera el tiempo restante. La telemetría puede recuperarse; el control exige
  otra conexión y autorización explícita. Un fallo de la API sigue provocando cierre.
- La supervisión del enlace conserva el umbral de 3 s sin señal para control, y
  los de 5 s y 15 s para pérdida de señal y desconexión de telemetría. El estado
  final distingue timeout de búsqueda, muerte o cierre del canal y caída de ANT
  Radio Service. La parada por pérdida real usa las comprobaciones existentes.
- El selector conserva 41 posiciones en pasos de 0,5 %. El perfil Original
  experimental mantiene −5 % a +15 %. Los ensayos acotados conservan sus límites.

## Android

Una sesión autorizada inicia un servicio `connectedDevice` y adquiere un
wake lock parcial durante la sesión. La actividad se suscribe a un controlador
ANT con contexto de aplicación. Minimizar, bloquear la pantalla o recrear la
actividad permite mantener la sesión mientras el servicio y la radio sigan
operativos. Salir voluntariamente de una pantalla de entrenamiento mediante su
acción de volver conserva la semántica de cierre explícito de esa pantalla.
En spinning se pausa la guía local al salir de la app; el enlace ANT autorizado
puede continuar y la guía se reanuda explícitamente.

La notificación incluye **DETENER**, que usa la misma finalización nativa que
la app. Descartar la notificación también solicita la parada. Si Android impide
mostrarla o faltan los permisos de dispositivo conectado, se permite entrenar
en primer plano y se cierra al salir de él. Si falla la promoción del servicio,
la app muestra el error. El servicio usa `START_NOT_STICKY` y descarta acciones
de parada de sesiones anteriores. Si Android termina todo el proceso, no hay
garantía de enviar el 0 % ni de conocer el estado físico resultante.

El SDK ANT empaquetado expone el enlace y la adquisición de canal mediante
`Context`; el código ya usa el contexto de aplicación para enlazar ANT Radio
Service. Esto permite independizar los objetos nativos de la actividad. La
continuidad de ANT Radio Service, su canal y el rodillo en reposo de pantalla
requiere una comprobación física en el Galaxy S20. Véanse los requisitos oficiales
de [tipo de servicio conectado](https://developer.android.com/develop/background-work/services/fgs/service-types#connected-device)
y [permiso de notificaciones](https://developer.android.com/develop/ui/compose/notifications/notification-permission).

## Latencia de los mandos

La reproducción de los ocho rechazos de 1.4.0 identifica un componente de
software: siete coincidían con un refresco anterior dentro de la ventana de
1.000 ms. En los ocho casos quedaban entre 65 y 756 ms de espera para la primera
ventana admisible según las marcas de la captura. La cola de 1.4.1 conserva la
última consigna, incluido LLANO, y la despacha al vencer esa ventana. Un
refresco cede ante trabajo manual pendiente. DETENER cancela el trabajo diferido
y conserva la secuencia nativa de parada.

El CSV conserva páginas y añade `details_json` en las filas `manual:*`.
El campo `requestedAtUtc` proviene de Flutter. En Kotlin, `request`,
`manual_pending`, `ant_api_entered` y `api_returned` permiten medir la espera,
entrada y duración de IPC con un reloj monotónico. `page11_numeric_match`
registra la primera página observada después del retorno en la que el entero
de los bytes 4–5 coincide con el campo de consigna transmitido. Una nueva orden
explícita reemplaza esa correlación y un refresco no la reinicia. El campo
`apiReturnToObservationMs` mide el tiempo hasta esa observación numérica.
El retorno de la API y la coincidencia 0x11 no confirman entrega, efecto
mecánico ni la semántica de esa página. Sin una medición posterior en el S20,
la contribución de radio/firmware a la latencia sigue sin cuantificarse.

## Validación

Las pruebas Kotlin avanzan un reloj simulado durante 30 y 60 min. Incluyen
pausas de 0x19 con 0x10, 0x11 y 0x54 activas, recuperación de potencia sin
rearmar el control, pérdida total posterior y una sola orden de parada.
La reproducción de los ocho rechazos, el refresco simultáneo, LLANO,
DETENER y la correlación numérica 0x11 usan transporte simulado. Flutter
prueba la interfaz con telemetría parcial, pausa y retorno con sesión
autorizada, cierre cuando solo se admite primer plano y la cola de mandos.

En el S20 queda por comprobar un entrenamiento real de 30 y 60 min con ANT
activo, alternando pantalla apagada y otras apps, el retorno a la actividad,
DETENER desde ambos lugares y el comportamiento con notificaciones denegadas
y pérdida de radio. Exportar CSV y JSON de esa ejecución permite comparar los
tiempos de software con las primeras páginas compatibles del rodillo.
