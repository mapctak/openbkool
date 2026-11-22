# OpenBkool 1.4.2 · segundo plano y latencia ANT

> Registro histórico. La política actual se describe en [Entrenamiento libre 1.5](entrenamiento_libre_1_5.md).

## Qué cerró la sesión del S20

En la sesión `247aae8e-4647-4f58-9d52-3891ed8c2963`, a las 09:55:48 UTC el
motivo fue `app_background`. OpenBkool solicitó 0 % y cerró ANT. Los datos
facilitados indican una parada deliberada de la aplicación. No muestran una
pérdida espontánea de radio.

En 1.4.1, había dos entradas capaces de producir ese motivo.

- `MainActivity.onStop` llamaba a `TrainingService.setVisible(false)`. El servicio
  cerraba ANT si su referencia a la instancia promovida era nula.
- Entrenamiento, Control manual, Pendientes experimentales y Spinning podían
  enviar `stop(app_background)` desde Flutter al pasar a pausa. Android lo
  ignoraba si la referencia al servicio promovido ya existía. Si todavía era
  nula, la solicitud podía cerrar la sesión aunque Android aún no hubiera
  tomado la decisión en `onStop`.

En 1.4.1, `releaseForeground()` limpiaba la referencia al servicio. El
`backgroundAuthorized=false` del diagnóstico final también es compatible con
un servicio que ya había terminado. Con los extractos disponibles no se puede
atribuir el cierre a un callback concreto, ni identificar qué permiso tenía
concedido el S20. Un fallo de diseño confirmado es el filtro de Dispositivos
cercanos de 1.4.1. Lo aplicaba desde API 31, aunque el requisito del tipo
`connectedDevice` se impone a partir de API 34. En Android 12 y 13 podía enviar
a primer plano exclusivo una sesión ANT que podía tener un servicio.
Notificaciones denegadas o bloqueadas también provocaban ese modo.

## Cómo se decide y verifica ahora

La decisión de cerrar por segundo plano se toma en Android, una vez que
`MainActivity.onStop` confirma el cambio. Una pausa de Flutter no solicita
parada y el canal nativo registra e ignora las solicitudes antiguas con motivo
`app_background`. Volver explícitamente desde la pantalla de entrenamiento y
DETENER siguen usando la parada nativa. En Spinning solo se pausa la guía local
al salir de la app.

Android verifica el estado real de primer plano mediante `ActivityManager`,
la publicación de la notificación mediante `NotificationManager` y adquiere
el wake lock antes de abrir ANT. La notificación solicita publicación
inmediata y mantiene DETENER.
En API 34+ se exige el permiso de dispositivo conectado aplicable al manifest.
En API 33+ se comprueba POST_NOTIFICATIONS para garantizar que DETENER pueda
mostrarse. Si falta un requisito, la interfaz explica que bloquear la pantalla
o cambiar de aplicación detendrá la sesión e indica el ajuste correspondiente.
Un error al lanzar o promover el servicio vuelve como error de inicio con su
diagnóstico. El manifiesto del SDK ANT conserva su consulta del servicio
`com.dsi.ant.service.socket`. El servicio de la app sigue siendo privado y
`START_NOT_STICKY`. La muerte real del servicio solicita el cierre si el
proceso sigue vivo. Si Android mata todo el proceso, no se puede garantizar
una última transmisión ni se rearma la consigna al volver a abrir la app.

El JSON incluye `backgroundLifecycle`. El CSV conserva filas `android:*`
con la decisión y los permisos, la instancia iniciada, el retorno de la
promoción, la autorización, la actividad fuera de pantalla y el estado
de publicación de la notificación. Para decidir si la sesión debía continuar,
usar la fila `activity_stopped` y su campo `decision`, junto con los eventos
de arranque anteriores. El estado final puede corresponder al servicio liberado.
En Android, `adb logcat -s OpenBkoolTraining` muestra la misma secuencia y
`adb shell dumpsys activity services com.example.openbkool` permite confirmar
`isForeground=true` y el tipo de servicio mientras se entrena.
[Tipo connectedDevice](https://developer.android.com/develop/background-work/services/fgs/service-types#connected-device)
y [permiso de notificaciones](https://developer.android.com/develop/ui/compose/notifications/notification-permission).

## Qué mide la latencia

En 1.4.1, los cinco mandos del S20 llegaron a la API, con esperas nativas de
5, 410, 680, 955 y 907 ms. Flutter sustituía una orden que aún esperaba el
retorno de otra llamada al canal de plataforma. Kotlin sustituía una orden
pendiente antes de despacharla. En cuanto el limitador abría la siguiente
ventana, despachaba el escalón pendiente aunque el usuario siguiera ajustando.
Un escalón que ya entró en la API no puede retirarse.

Para los botones +/− del modo manual, 1.4.2 conserva el despacho inmediato
cuando el transporte está libre. Si un escalón ya tiene que esperar, se
despacha al vencer el mayor de dos plazos: 1.000 ms desde la anterior entrada
ANT o 180 ms desde la última pulsación nativa. Los plazos corren en paralelo.
Así una ráfaga puede sustituir el objetivo pendiente incluso cerca del límite.
Una selección directa o LLANO no añaden el plazo de 180 ms. Una secuencia que
deja pasar ambas ventanas todavía se envía como órdenes individuales.
El refresco cede ante la consigna pendiente. DETENER cancela el trabajo
diferido. Las 41 posiciones y los perfiles conservan su autorización.

El CSV distingue `uiQueueMs` (Flutter), `nativeAdmissionMs` (hasta el
controlador nativo), `controllerToApiEntryMs` (incluye la espera de despacho),
`apiDurationMs` y `apiReturnToObservationMs`. Los relojes monotónicos de
Flutter y Android se usan para medir intervalos internos. La correlación
anota `requestedAtUtc` y los refrescos ya no heredan el identificador ni
los tiempos de la pulsación. En la muestra del S20, +2,5 % tardó 907 ms hasta
la entrada en la API y unos 2,1 s más hasta la primera coincidencia 0x11.
Ese segundo tramo incluye el SDK y la espera de la página recibida. El
payload 0x11 sirve como observación numérica y carece de valor de ACK o de
confirmación mecánica. El estado visible distingue cambio pendiente y orden
aceptada por la API.

## Validación

Probar en el S20 con permisos concedidos y un rodillo activo: abrir la
notificación, bloquear la pantalla, pulsar Inicio, volver, y detener desde
la notificación. Comprobar que las filas de fondo autorizadas dicen
`continue_training` y que el CSV conserva telemetría. Repetir con el permiso
de notificaciones denegado y con el canal de notificación desactivado. La app
debe advertir y terminar al ir al fondo. Con el rodillo parado, probar cierre
forzado del proceso y reapertura; una sesión nueva debe quedar sin consigna
hasta autorización y orden explícitas. Un fallo al promover el servicio debe
quedar registrado como `promotion_failed`.

Para medir mandos, comparar una ráfaga de +0,5 % a +3 % con la selección
directa de +3 %. Probar LLANO y DETENER durante una espera, y pérdida real
del enlace. Las pruebas Kotlin comprueban la ventana de consolidación,
el límite de transporte, los tiempos del refresco y las reglas de autorización.
Flutter verifica que pausa y retorno ya no disparan la parada, la cancelación
de la cola ante parada nativa y la presentación de consignas pendientes.
