# Diagnóstico ANT+ de OpenBkool

Implementado el 12 de noviembre de 2026. La pantalla «Diagnóstico ANT+» se abre
desde el diagnóstico BLE. No inicia comprobaciones hasta pulsar «Comprobar
capacidades ANT». Al volver, los resultados BLE y el último informe ANT se
conservan durante la sesión. No se cambia el escaneo ni el descubrimiento GATT.

## SDK oficial e interfaces utilizadas

Se integra **ANTLib 4.16.0** del [SDK oficial ANT Android C.B7](https://github.com/ant-wireless/ANT-Android-SDKs/tree/0e8cea714a231fb9565170d4ed01eafa868f9798/ANT_Android_SDK).
El AAR original está en `android/app/libs/`, con procedencia y SHA-256 en su
[README](../android/app/libs/README.md). No se reutiliza código descompilado de Bkool.

La consulta general de capacidad utiliza ANTLib de bajo nivel. No hace falta
abrir un perfil ANT+ ni integrar ANT+ PluginLib para preguntar por hardware y
canales. ANT+ Plugins Service se consulta como paquete instalado, **sin afirmar
que esté funcionando o que soporte un perfil concreto**.

Interfaces oficiales usadas por `AntDiagnostics.kt`:

| API | Qué comprueba | Qué no demuestra |
|---|---|---|
| `AntSupportChecker.hasAntFeature(context)` | soporte integrado declarado por el sistema/servicios | que exista una radio utilizable ahora |
| `AntSupportChecker.hasAntAddOn(context)` | declaración de un servicio para hardware adicional | que haya un USB ANT conectado |
| `PackageManager.getPackageInfo()` | instalación, habilitación y versión de Radio/Plugins/USB Service | hardware físico disponible |
| `AntService.bindService()` y `AntService(IBinder)` | enlace real por IPC con Radio Service | disponibilidad de canales |
| `AntService.getChannelProvider()` y `getNumChannelsAvailable()` | proveedor que responde y canales libres en ese instante | ausencia de hardware si devuelve cero |
| `isLegacyInterfaceInUse()` | si la interfaz legacy está ocupada | permiso para apropiarse de ella |
| `getAdapterProvider().getAdaptersInfo(context)` | adaptadores observados, ID, versión e integrado/externo | funcionamiento de un rodillo/perfil |
| `acquireChannel(context, PredefinedNetwork.PUBLIC)` | reserva temporal de un canal **sin asignar** | conexión ANT con un sensor |
| `AntChannel.release()` | devolución de esa reserva al servicio | confirmación independiente posterior por radio |

La semántica de reserva sin asignar, los adaptadores y los motivos de fallo se
contrastaron con el Javadoc **4.16.0** del mismo commit:
[ZIP oficial del Javadoc](https://github.com/ant-wireless/ANT-Android-SDKs/blob/0e8cea714a231fb9565170d4ed01eafa868f9798/ANT_Android_SDK/API/Android_ANTLib_Javadoc_4-16-0.zip).
Se verificaron también las firmas del AAR con `javap`.

## Flujo nativo y límites de operaciones

Dart utiliza `MethodChannel('openbkool/ant')`, método `inspectCapabilities`,
registrado en `MainActivity.kt` de manera independiente del canal de permisos BLE.

1. Consulta paquetes y declaraciones de hardware. Aunque falte Radio Service,
   devuelve esas observaciones; no convierte una instalación ausente en ausencia
   confirmada de hardware.
2. Si Radio Service está instalado y habilitado, intenta enlazar con él.
3. Consulta proveedor, canales y adaptadores mediante llamadas Binder en un
   ejecutor de trabajo, fuera del hilo de interfaz.
4. Si hay canales libres, reserva uno en la red pública predeterminada y lo
   libera inmediatamente. Si no hay canales libres, no fuerza la recuperación
   de la interfaz legacy ni ocupa un canal de otra aplicación.
5. Libera el enlace al servicio al terminar, al agotarse el plazo o al limpiar
   el motor Flutter. La limpieza de la actividad devuelve una cancelación.

**No se llama a `assign`, `open`, configuración de ID/frecuencia/período, búsquedas,
redes privadas, páginas de control, transmisión de datos ni DFU.** Los accesos IPC
pueden activar temporalmente el servicio/controlador local, pero no se configura
un canal inalámbrico ni se intenta comunicar con el rodillo.

La consulta tiene un plazo de respuesta de ocho segundos. Si el servicio indica
`SERVICE_INITIALIZING`, vuelve a consultar tras 500 ms, dentro de ese plazo; esto
es una repetición de consultas locales, no un escaneo de sensores. Las llamadas
Binder de Android no son necesariamente cancelables: si una termina después del
plazo, se ignora su resultado y cualquier reserva obtenida se libera. Se evitan
reservas nuevas cuando la consulta ya consta como finalizada.

## Interpretación de resultados

- **Hardware integrado declarado:** afirmación de `AntSupportChecker`; puede
  indicar soporte previsto por el firmware del teléfono. Se muestra separadamente
  de un adaptador integrado observado por Radio Service.
- **Radio/Plugins/USB Service instalado:** existencia del paquete y estado de
  habilitación. Instalar servicios no añade una radio ANT física al teléfono.
- **Proveedor operativo:** se informa tanto si responde por IPC como si tiene
  canales libres. Puede responder correctamente con cero canales libres.
- **Radio accesible:** se obtuvo una reserva sin abrir y se devolvió. Es evidencia
  de acceso en esa consulta; no una conexión a un rodillo ni garantía futura.
- **Radio no accesible ahora:** puede significar radio ausente, deshabilitada,
  ocupada, modo avión, incompatibilidad del servicio o retirada de un adaptador.
  Se conserva el motivo original de `ChannelNotAvailableException` cuando existe.
- **No comprobado:** dato desconocido, consulta pendiente/incompleta, API no
  soportada, fallo de enlace o timeout. No se representa como un «No» de hardware.
- **Error al liberar:** se distingue una reserva obtenida de un fallo de limpieza;
  no se presenta todo el proceso como éxito. El enlace al servicio se libera también.

Estados generales del JSON: `not_checked`, `completed`, `partial`, `timeout`,
`radio_service_unavailable`, `bind_failed`, `service_disconnected`, `binding_died`,
`null_binding`, `cancelled`, `error`, `channel_error` y `unsupported_platform`.
Los fallos incluyen etapa, tipo, mensaje y motivo/código si está disponible.
`completed` significa que terminó la consulta, **no** que se encontrara una radio.

## JSON compartido

La exportación existente conserva `devices`, `gattDiscoveries`, `events` y los
ajustes BLE. Se añade el campo aditivo `antDiagnostics`:

- inicialmente `{"status":"not_checked"}`, sin iniciar acceso ANT al exportar;
- después, el último informe nativo, con fechas, modelo/versión Android,
  versión ANTLib, declaraciones de hardware, paquetes, enlace al servicio,
  proveedor/canales, adaptadores, prueba de acceso/liberación y errores;
- los fallos MethodChannel también se guardan, sin inventar disponibilidad de radio.

El botón de exportación de ambas pantallas copia el mismo informe conjunto al
portapapeles. Una consulta nueva reemplaza la anterior cuando recibe respuesta;
la pantalla avisa si aún muestra datos anteriores durante una comprobación.
No se envían informes a servidores ni se guardan datos entre reinicios de la app.

## Compatibilidad Android

El AAR incorpora consultas de visibilidad para Android 11+. El manifiesto de la
app añade consultas explícitas de los paquetes `com.dsi.ant.service.socket`,
`com.dsi.ant.plugins.antplus` y `com.dsi.ant.usbservice`, además del intent de
información de servicios. No usa `QUERY_ALL_PACKAGES`, no cambia los permisos
Bluetooth ni hace obligatorio el hardware ANT para instalar la aplicación.

Las [notas oficiales C.B7](https://github.com/ant-wireless/ANT-Android-SDKs/blob/0e8cea714a231fb9565170d4ed01eafa868f9798/ANT_Android_SDK/README.md)
explican la actualización de visibilidad a partir de API 30 y declaran soporte
hasta Android 13 (API 33). OpenBkool sigue compilando para el SDK configurado por
Flutter; el informe incluye `sdkInt`, versión Android, fabricante, modelo y target
de la instalación en ejecución. Si la API es posterior a 33, la pantalla advierte
que la compatibilidad del servicio ANT depende de la prueba efectiva de enlace
y acceso; no se infiere soporte a partir de que el paquete esté instalado.

**Limitación de esta sesión:** `adb devices -l` no encontró dispositivos conectados.
Por tanto no se ha podido comprobar la versión Android ni las capacidades ANT del
teléfono del usuario. La versión real quedará reflejada al ejecutar la pantalla en
él. La compilación y los tests no sustituyen esa verificación física. Tampoco se
han instalado servicios ANT, activado la radio ni actualizado software del teléfono.

En servicios antiguos puede no estar disponible el proveedor de adaptadores;
antes de Radio Service 4.12.10, una lista vacía también puede ocurrir durante
inicialización según el Javadoc. Se documenta esa incertidumbre; no se certifica
compatibilidad con todas las combinaciones de Android y servicios ANT antiguos.

## Validación

Resultados verificados en este entorno:

- `flutter analyze`: sin incidencias.
- `flutter test`: siete pruebas correctas (cuatro BLE y tres ANT).
- `:app:testDebugUnitTest`: cuatro pruebas Kotlin correctas, cero fallos/errores.
- Manifiesto fusionado: consultas de paquetes ANT presentes; mínimo API 24,
  target API 36. Los permisos BLE anteriores se mantienen.
- `flutter build apk --debug`: APK generada correctamente. Gradle emite avisos
  de deprecación y acceso nativo de Java que no impiden la compilación.

Comandos de reproducción:

```sh
flutter analyze
flutter test
cd android
./gradlew :app:testDebugUnitTest
cd ..
flutter build apk --debug
```

Las cuatro pruebas BLE anteriores se mantienen. Las pruebas Flutter ANT simulan
el MethodChannel para verificar navegación sin perder resultados BLE, exportación
conjunta, distinción entre servicios instalados y radio ausente/ocupada, errores
de enlace y radio externa disponible sin hardware integrado ni Plugins Service.
Las cuatro pruebas Kotlin verifican que no se reserva con cero canales libres,
que la reserva se libera inmediatamente y que fallos de adquisición/liberación
no se convierten en éxito.

Los tests Kotlin cubren la política de reserva y limpieza; los tests Flutter usan
respuestas nativas simuladas. **No prueban un enlace Binder real con ANT Radio
Service**, que requiere un teléfono/servicio compatible. APK de depuración:
`build/app/outputs/flutter-apk/app-debug.apk`.
