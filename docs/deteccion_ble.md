# Diagnóstico de detección BLE de OpenBkool

Implementación del 12 de noviembre de 2026, basada en las secciones 1 y 2 de
[protocolo_bkool.md](protocolo_bkool.md). No se ha establecido comunicación con el
rodillo durante el desarrollo; la identificación del equipo físico sigue pendiente.

## Comportamiento implementado

- Búsqueda de 30 segundos, modo Android `lowLatency`, con actualizaciones continuas.
  Se pasan listas vacías para UUID, nombre, palabras clave, identificador,
  manufacturer data y service data. No hay filtros posteriores por nombre,
  UUID, flags de discoverability, fabricante o conectabilidad.
- Se muestran todos los identificadores entregados por el sistema, incluidos los
  anuncios sin nombre, sin UUID y marcados como no conectables. La selección
  manual permite intentar conexión con cualquiera; un anuncio no conectable puede
  fallar o agotar el timeout de 15 segundos.
- Cada tarjeta muestra nombre anunciado (o nombre del sistema como alternativa,
  o «sin nombre»), identificador, RSSI, UUID anunciados, UUID en service data,
  conectabilidad y última detección. Orden por RSSI, sin excluir dispositivos.
- Se conservan nombres no vacíos y se acumulan UUID por identificador durante la sesión. Un anuncio
  posterior incompleto no elimina una pista anterior; RSSI, conectabilidad y fecha
  reflejan la última observación. Al repetir búsqueda se conservan las tarjetas
  anteriores y su última fecha: no significan que el dispositivo siga presente.
- Se destacan las pistas `bkool` sin distinguir mayúsculas, el UUID Cycling Power
  `00001818-0000-1000-8000-00805f9b34fb` y el anuncio del servicio propietario
  `f03eee01-4910-473c-be46-960948c2f59c`. Las dos primeras son indicios, no una
  identificación inequívoca del modelo ni garantía de que acepte control.
- Tras conectar se enumeran los servicios primarios y los secundarios incluidos,
  sus características, propiedades y UUID de descriptores. Se registra y marca
  explícitamente si se encontró el servicio propietario Bkool en el último
  descubrimiento completado. No se confunde el UUID de anuncio con GATT descubierto.
- Registro con fecha UTC, estado del adaptador, permisos, inicio/final de búsqueda,
  primera observación de cada dispositivo por búsqueda, pistas, errores,
  solicitudes de conexión/desconexión y descubrimiento GATT. La información se
  conserva tras desconectar durante la sesión.

## Exportación JSON

«Exportar diagnóstico JSON» copia un informe al portapapeles. Puede usarse antes
de conectar o incluso cuando una búsqueda falla o no detecta dispositivos.
Pega el texto en un archivo `.json` para conservarlo fuera de la app.

El esquema incluye `schemaVersion`, versión del plugin, fecha de exportación,
estado del adaptador, opciones de escaneo, `devices`, `gattDiscoveries` y `events`.
En `devices` se separan UUID anunciados y UUID de service data, junto con nombres,
RSSI, fechas, manufacturer/service data y pistas. `gattDiscoveries` contiene el
último descubrimiento completo por identificador; un intento fallido posterior
no borra ese resultado fechado. Los eventos se exportan en orden cronológico.

Los datos son de sesión y se pierden al cerrar/reiniciar la app. La fecha se toma
del reloj del teléfono. El JSON conserva identificadores Bluetooth y nombres de
los dispositivos observados; solo se copia localmente y no se envía a servidores.

## Compatibilidad y permisos Android

`pubspec.yaml` y `pubspec.lock` mantienen `flutter_blue_plus 2.3.14`. La interfaz
`flutter_blue_plus_platform_interface 9.0.4` se declara como dependencia de
**desarrollo** para las pruebas simuladas, sin cambiar la versión ya instalada.

Se han contrastado las firmas de `startScan`, `connect` y `discoverServices` con
el código del paquete instalado en `.pub-cache`. La conexión mantiene
`license: License.nonprofit` y `mtu: null`.

El manifiesto conserva `BLUETOOTH` y `BLUETOOTH_ADMIN` limitados a Android 11
(SDK 30); declara `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_COARSE_LOCATION`
y `ACCESS_FINE_LOCATION`. Se elimina `neverForLocation` y el límite SDK del
permiso de ubicación para este diagnóstico: Android advierte que ese indicador
puede filtrar algunas balizas BLE. Esto elimina una posible restricción; no prueba
que estuviera filtrando este Bkool concreto.

Antes de escanear, un canal Android en `MainActivity.kt` solicita los permisos
que correspondan a la versión. Solicita COARSE y FINE conjuntamente, como requiere
Android 12+ para pedir ubicación precisa, además de dispositivos cercanos.
El plugin recibe `androidUsesFineLocation: true`; su implementación instalada
comprueba los servicios de ubicación en Android 11 o anterior. El estado del
adaptador se empieza a consultar después de conceder permisos para evitar
conservar un estado inicial sin autorización. Si se deniega o cancela el permiso, se registra el error y no empieza
la búsqueda. Si se deniega permanentemente, hay que habilitarlo en Ajustes.
No se solicitan permisos de ubicación en segundo plano ni se consulta el GPS.

Referencias oficiales:

- [Permisos Bluetooth y filtrado de neverForLocation](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions).
- [Solicitud conjunta de ubicación aproximada y precisa](https://developer.android.com/develop/sensors-and-location/location/permissions/runtime).

## Garantía de operaciones limitadas en Android

Las operaciones BLE de la aplicación se limitan a escanear, conectar, descubrir
servicios y desconectar. No se implementan lecturas de valores de características,
escrituras de características/descriptores, activación de notificaciones,
comandos de resistencia, entrada a DFU ni actualizaciones de firmware.

Además de no llamar a métodos de escritura, se usa explícitamente
`discoverServices(subscribeToServicesChanged: false)`: el valor por defecto de
FBP 2.3.14 podría suscribir Services Changed y escribir el CCCD. `mtu: null`
evita la petición de MTU automática de esa versión en Android.
Esta comprobación se centra en la APK Android. Según el propio plugin, iOS realiza
ciertas suscripciones a nivel de sistema que no se pueden desactivar desde esa
opción; no se ha validado este flujo para iOS.

## Validación

Resultados en este entorno Linux:

- `flutter analyze`: sin incidencias.
- `flutter test`: cuatro pruebas correctas.
- `flutter build apk --debug`: APK generada correctamente en
  `build/app/outputs/flutter-apk/app-debug.apk`.

Se verificó el manifiesto Android generado: SCAN/CONNECT y COARSE/FINE presentes,
sin `neverForLocation` ni límite SDK para ubicación; permisos Bluetooth heredados
limitados a SDK 30. La compilación incluye el canal Kotlin de permisos.
Gradle emitió una advertencia de acceso nativo de Java, sin impedir la compilación.

Las pruebas usan la interfaz de plataforma real de la versión instalada y una
radio simulada, sin adaptador ni rodillo. Cubren:

- opciones de escaneo sin filtros y recepción de anuncios sin nombre/UUID;
- pistas de nombre mixto `bKoOl` y Cycling Power, conservación de anuncios parciales;
- selección de dispositivo sin pistas y marcado no conectable;
- enumeración de servicio propietario, secundario incluido y características;
- exportación de anuncios antes de GATT, GATT y registros después de desconectar;
- denegación de permisos, error de escaneo con reintento y final por timeout sin dispositivos;
- cero escrituras y cero suscripciones, con un servicio Services Changed presente
  para detectar una suscripción implícita del plugin.

La prueba del canal de permisos simula su respuesta Dart; el diálogo del sistema
Android y la radio real necesitan comprobación en un teléfono.

## Limitaciones y procedimiento para el rodillo real

1. **ANT no es BLE.** El informe estático confirma rutas ANT propietarias Pro1/Pro2
   y ANT+ FE-C. No confirma que nuestro ejemplar antiguo tenga BLE ni el firmware
   que lo habilita. Un rodillo solo ANT/ANT+ no aparecerá con este escáner; haría
   falta una radio/pila ANT. Tampoco se busca Bluetooth clásico RFCOMM.
2. **Publicidad y estado del equipo.** Un rodillo apagado, fuera de alcance,
   ocupado por otra app/teléfono o que haya dejado de anunciarse puede no aparecer.
   Cierra otras apps conectadas, acerca el teléfono y reinicia la alimentación del
   rodillo; compara una búsqueda con él apagado y otra con él encendido.
3. **El sistema es quien entrega los anuncios.** Permisos, ubicación desactivada,
   Bluetooth apagado, ahorro de energía, app en segundo plano y límites de Android
   a búsquedas repetidas pueden impedir resultados. Mantén la app visible y la
   pantalla encendida; deja una pausa antes de repetir búsquedas tras un error.
   Esta app no puede mostrar anuncios que la radio o el sistema no entregan.
4. **Anuncio incompleto.** No anunciar `1818` o no contener `bkool` no descarta el
   dispositivo. Por eso todos los resultados siguen siendo seleccionables.
   Nombres del sistema pueden estar en caché y direcciones privadas pueden cambiar.
5. **GATT no equivale a control confirmado.** Encontrar `1818` confirma ese servicio,
   pero no el modelo; encontrar `f03eee01…` coincide con el servicio propietario
   de la APK analizada. Ninguno demuestra por sí solo la versión de firmware o
   que sea seguro enviar comandos. Esta fase no envía esos comandos.

Para investigar el equipo que falta, acepta los permisos indicados, realiza
las dos búsquedas comparativas de 30 segundos y exporta cada informe. Selecciona
manualmente los dispositivos que aparecen o cambian al encender el rodillo,
incluso si carecen de nombre y de pistas. Compara los servicios GATT obtenidos
con [protocolo_bkool.md](protocolo_bkool.md). La ausencia de resultados no permite
concluir por sí sola que el rodillo esté averiado o necesite nuevo firmware.
