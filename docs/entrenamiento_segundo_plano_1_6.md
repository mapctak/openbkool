# Segundo plano en OpenBkool 1.6

## Auditoría de 1.4.1 y 1.4.2

En 1.4.1 coexistían solicitudes de parada desde cuatro pantallas Flutter y
desde `MainActivity.onStop`. Ambas rutas podían producir `app_background`
cuando faltaba la referencia nativa a un servicio promovido. También se exigía
permiso de dispositivo cercano desde Android 12, aunque la condición de tipo
`connectedDevice` aplica desde Android 14. La sesión del S20 prueba que la app
pidió el cierre. El estado final no permite distinguir cuál de las dos rutas
actuó ni si el servicio llegó a promoverse.

1.4.2 retiró las solicitudes Flutter y verificó la promoción y la notificación.
Aun así, la actividad cerraba ANT desde `onStop` si la comprobación en esa
transición fallaba. El S20 siguió desconectándose y no hay trazas suficientes
para atribuir el segundo fallo a un permiso, a la promoción o al fabricante.
1.5.1 había dejado explícita la política de primer plano.

## Arquitectura y permisos

`TrainingService` crea y posee un único controlador de entrenamiento. Flutter
se conecta al stream de estado y usa el canal de métodos existente. Se puede
destruir o reconstruir la actividad sin disponer el controlador. La entrega
de instantáneas y la exportación final sobreviven al cierre de ANT mientras
continúe el proceso. Un intento de nuevo entrenamiento se rechaza mientras
haya un arranque, un servicio propietario o un cierre ANT anterior en curso.

La conexión arranca desde una acción explícita en la actividad visible.
El servicio es privado. Usa `connectedDevice` cuando el sistema admite tipos
de servicio. Desde API 34 comprueba el requisito de Dispositivos cercanos
mediante los permisos Bluetooth existentes. Desde API 33 comprueba el permiso
de notificaciones. Android permite iniciar ciertos servicios aunque el usuario
deniegue la notificación. OpenBkool requiere que sea visible para garantizar
acceso a **DETENER** fuera de la actividad. [Tipos y requisitos de servicios](https://developer.android.com/develop/background-work/services/fgs/service-types#connected-device) · [Permiso de notificaciones](https://developer.android.com/develop/ui/compose/notifications/notification-permission).

El servicio llama a `startForeground()` y comprueba que Android lo presenta
como promovido y que su notificación esté activa. Después adquiere un wake lock
parcial, instala el receptor de pantalla y abre ANT. Si falta un permiso, se
bloquea el canal de notificación o falla la promoción, informa del motivo y no
abre ANT. No existe una sesión alternativa de control sin supervisión.
El wake lock se libera al acabar el cierre. [Inicio y promoción](https://developer.android.com/develop/background-work/services/fgs/launch).

## Quién actúa en cada escenario

| Escenario | Decisión |
|---|---|
| A–F. Pantalla encendida, bloqueo, varios minutos apagada, Inicio, otra app y retorno | El servicio conserva ANT y la autorización si las condiciones de seguridad se mantienen. La actividad solo informa de salida y retorno. La pantalla se asocia de nuevo al UUID en curso. |
| G–H. DETENER en la notificación o la pantalla | Ambas rutas llaman a la misma parada del controlador. Un token de notificación identifica el lanzamiento actual. El cierre invalida los objetivos y conserva la secuencia ANT de 1.5.1. |
| I. Falta temporal de una métrica | El supervisor existente suspende el control cuando corresponde. Puede continuar la telemetría parcial. |
| J. Pérdida total de ANT | El supervisor y los eventos de radio aplican el cierre existente. |
| K. Permiso, notificación o promoción perdidos | El servicio comprueba su estado en la supervisión ANT y antes del envío normal. La pérdida detectada invalida la sesión y activa la parada conservadora. |
| L. Fallo de lanzamiento o promoción | La app informa del error. No se abre un canal ANT. |
| M. Destrucción de servicio o proceso | Si el proceso sigue vivo, la destrucción del servicio solicita el cierre. Una muerte completa del proceso puede impedir la última solicitud de 0 %. El servicio usa `START_NOT_STICKY` y no recupera consignas. |

El CSV y el JSON conservan el UUID de 1.5.1 y los eventos de las órdenes.
Se añaden `service_started`, `foreground_promoted`, `notification_active`
con permisos, `activity_stopped`, `activity_resumed`, `screen_off`,
`screen_on`, `ant_received_screen_off`, el origen de la parada y
`service_stopping`. Se registra la primera trama válida en cada intervalo
apagado y un contador al volver o cerrar. `service_stopped` se registra
en Logcat tras retirar la notificación. El informe final se lee con
**Copiar CSV** y **Copiar JSON** en la misma pantalla.

## Próxima prueba en el Galaxy S20

1. Abrir **ENTRENAMIENTO LIBRE**, conectar y verificar la notificación
   **OpenBkool — Entrenamiento libre activo** antes de autorizar el control.
2. Autorizar, mantener una consigna conocida de 0 % a +3 %, apagar la
   pantalla varios minutos y volver. Comparar el UUID y la autorización.
   Repetir con Inicio y otra app. En el CSV, buscar
   `ant_received_screen_off` y comprobar que sigue habiendo páginas ANT.
3. Detener con **DETENER** en la pantalla bloqueada. Repetir con el botón
   desde la app. Exportar CSV y JSON finales y verificar el motivo y origen.
4. Probar permisos denegados y canal de notificación desactivado antes
   de conectar. Para pérdida completa del servicio o del proceso, usar
   el rodillo detenido y comprobar que al reabrir no se rearma una sesión.
5. En una prueba separada, registrar −2 % → LLANO → +2 %. LLANO conserva
   `33 FF FF FF FF 20 4E FF`. El retorno de API y la página 0x11 no
   confirman entrega ni aplicación mecánica. Los valores negativos y los
   superiores a +3 % siguen siendo experimentales.

Las pruebas unitarias cubren exclusión del propietario, promoción requerida,
permisos por API, rechazo de una parada vieja, retorno a la interfaz, parada
y exportación. También se ejecuta la suite existente de codificación, cola,
fallos ANT y cierre de 1.5.1. ADB no detectó un S20 ni un emulador operativo.
La continuidad de ANT con la pantalla apagada, la respuesta física y el acceso
a DETENER desde la pantalla bloqueada quedan pendientes en el S20. La
visibilidad y las acciones en el bloqueo también dependen de los ajustes de
notificaciones de Android y del dispositivo.
