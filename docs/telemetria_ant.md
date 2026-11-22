# Telemetría ANT de Bkool Smart Pro v1

Implementación de recepción local para el rodillo confirmado **30064 / tipo 112 /
transmisión 5**, protocolo `BKOOL_V1_PUBLIC`. Acceso desde «Entrenamiento» en la
pantalla principal. No se transmite ninguna página de datos o control al rodillo.
La configuración del adaptador mediante ANT Radio Service sí utiliza sus operaciones
administrativas normales: reserva, asignación, configuración, apertura y cierre.

## Evidencias y formatos

Referencia: [protocolo_bkool.md](protocolo_bkool.md), sección 4, y las fuentes locales
excluidas de Git:

- `research/jadx/sources/com/bkool/sensors/tech/ant/devices/TrainerBkoolPro1.java`,
  `TrainerBkoolChannelEventHandler.onReceiveMessage()`, especialmente líneas 92–122.
- `research/jadx/sources/com/bkool/sensors/tech/ant/devices/TrainerBkoolPro2.java`,
  `TrainerBkool2ChannelEventHandler.onReceiveMessage()`, bloques de páginas `10` y `19`.
- `research/jadx/sources/com/bkool/sensors/tech/ant/BkoolSensorAntWrapper.java`:
  asignación y recepción pública documentadas en el informe anterior.

Índices desde cero dentro de los **ocho bytes de payload**, sin ID de mensaje,
canal ni identidad extendida:

| Página | Campo | Decodificación | Unidad |
|---|---|---|---|
| `0x10` | velocidad | `(b4 + 256*b5) * 0.0036` | km/h |
| `0x10` | contador distancia | `b3`, sin signo, módulo 256 | metros |
| `0x19` | potencia instantánea | `b5 + ((b6 & 0x0F) << 8)` | W |
| `0x19` | cadencia | `b2`, sin signo | RPM |

La escala de velocidad y la extracción de potencia/cadencia están confirmadas en
ambos controladores. Las unidades de 0.001 m/s y 1 m coinciden con la
[documentación oficial del SDK Fitness Equipment](https://thisisant.developer.garmin.com/assets/APIassets/Android_ANT_plus_plugins_API/com/dsi/ant/plugins/antplus/pcc/AntPlusFitnessEquipmentPcc.IpcDefines.html).
La correspondencia del contador propietario con metros es coherente con esa
interpretación y las capturas, pero falta contrastarla con una distancia física
independiente. No se afirma precisión/calibración del rodillo.

Velocidad `0xFFFF`, potencia `0xFFF` y cadencia `0xFF` se tratan como desconocidas,
conforme a la interpretación del formato FE; no son ceros. No se decodifican
flags de bloqueo, estado de entrenamiento ni otros campos propietarios sin
validación. El nibble superior de b6 **no** forma parte de la potencia.

## Capturas reproducibles

`android/app/src/test/resources/bkool_30064.csv` contiene un subconjunto literal
(páginas 10, 19 y 50) del JSON aportado por el usuario, exportado
2026-11-13T16:55:11.003203Z. Conserva fechas y payloads originales. No son datos
simulados. La envoltura ANT de las páginas de esa captura es:
`4E 00 <8 bytes> 80 70 75 70 05` (identidad 30064/112/5).

Ejemplos confirmados por pruebas:

- `10 19 98 65 86 0D FF 3C`: 3462 mm/s = 12.4632 km/h; contador 101.
- `19 BF 17 D2 05 1D 40 36`: 29 W y 23 RPM.
- Primera referencia 101, última 204: 103 m observados; último dato 13.0608 km/h,
  26 W, 17 RPM. Esto valida la aritmética de las capturas, no una nueva sesión física.
- La cadencia cambia de 20 a 23 con contador de actualización `C9` repetido:
  no se descartan todas las páginas por repetir ese contador.
- El byte temporal b2 de página 10 pasa de `FA` a `04`; no se usa para calcular
  distancia. El contador de distancia **no desborda** en esta captura.

## Distancia y pérdidas

El primer contador establece 0 m; no se suma distancia previa a la conexión.
Cada incremento se calcula `(nuevo - anterior + 256) % 256`. Los controladores
originales usan `+255` al desbordar; aquí se corrige ese desfase de un metro.
Los tests de desbordamiento de distancia (250→4 = 10 m) son **sintéticos** y
están separados de la reproducción de capturas reales.

No se integra velocidad para inventar distancia perdida. Tras 5 s sin ninguna
página del rodillo se invalida la referencia de distancia y las métricas; al
recuperar se conserva el total anterior y se establece otra referencia. La
pantalla/CSV marcan distancia parcial. Si entre páginas de distancia pasan
10 s, o un salto excede el máximo representable de velocidad (65.534 m/s,
con margen de 1 s de entrega y 2 m de cuantización), se omite el salto y se
restablece la referencia. Este guardia de discontinuidad es una **heurística**,
no una señal documentada de reinicio del rodillo.

También se marca parcial si el intervalo permite teóricamente más de 256 m
al máximo representable; se suma únicamente el incremento modular mínimo.
Un reinicio silencioso que produzca un incremento modular plausible no puede
identificarse inequívocamente con este contador. Se requiere prueba de campo
para ajustar tolerancias; los datos crudos permanecen en CSV para auditarlo.

## Canal y recursos

El entrenamiento usa un canal dedicado PUBLIC, RF 40, período 32768,
`BIDIRECTIONAL_SLAVE` e identidad extendida. La identidad seleccionada se compara
con la configurada, la leída del adaptador y la recibida. El control exige además
la identidad validada 30064/112/5 y fabricante 67/modelo 22.
La búsqueda ANT mantiene sus canales de recepción independientes.

El coordinador compartido impide simultanear entrenamiento, búsquedas o
reserva de diagnóstico ANT. No se activa FE-C ni la red privada V2 en entrenamiento.

- Espera inicial: hasta 30 s sin el rodillo.
- Pérdida de señal: 5 s sin páginas de la identidad seleccionada.
- Desconexión y liberación: 15 s desde la última página.
- Velocidad o potencia/cadencia con 10 s de antigüedad: cifra ausente, aunque
  sigan llegando páginas informativas. La potencia y la velocidad tienen edades separadas.
- Finalizar o salir del entrenamiento cierran recursos. Desde 1.6, el servicio Android supervisa
  el enlace cuando se apaga la pantalla o la actividad deja de estar visible.
  [Ciclo de vida y validación](entrenamiento_segundo_plano_1_6.md).
- Los fallos de permisos/servicio/configuración/canal y operaciones de limpieza
  se mantienen en los eventos y en `antTraining` del diagnóstico JSON general.
  Si falla la limpieza, no se afirma liberación y se bloquean nuevas reservas
  hasta reiniciar el proceso, igual que en las búsquedas existentes.

## Registro y exportación

`BkoolTelemetry.kt` es Kotlin puro, sin widgets ni dependencias de la radio.
Flutter recibe snapshots mediante `openbkool/training/events`; los métodos
start/authorizeControl/setManualSlope/stop/exportCsv utilizan `openbkool/training`.

Cada sesión escribe un archivo `training_*.csv` en el directorio privado Android,
con vaciado cada segundo y cierre al terminar. Incluye fecha UTC, tiempo
monótono de sesión, protocolo e identidad, payload hexadecimal, métricas,
edades, estado de señal y marca de distancia parcial. Las páginas informativas
también quedan registradas; los duplicados no añaden distancia. Los errores de
CSV se muestran y no impiden liberar ANT. JSON conserva un búfer acotado de
2000 mensajes y 500 eventos de entrenamiento, con contadores de descartes;
el CSV no depende de ese búfer.

«Copiar CSV» está disponible tras finalizar: pegar su contenido
en un archivo `.csv`, como en la exportación JSON existente. Usa decimal con
punto, separador coma, cabecera y escape de comillas. Exportar una sesión muy
larga requiere cargar el archivo en memoria y puede superar el límite del
portapapeles Android: se informa del error y el archivo privado permanece.
No hay selector de archivos, rotación automática ni recuperación de sesiones
anteriores tras reiniciar la aplicación. La aplicación puede perder hasta el
último segundo de datos si Android mata el proceso abruptamente.

## Validación

Las pruebas JVM incluyen capturas reales, unidades, máscara de potencia,
baseline, duplicados, límites sintéticos, tramas malformadas, identidad ajena,
señal perdida/recuperación, sentinelas, cadencia y CSV. Las pruebas Flutter
cubren métricas, fin de entrenamiento, exportación y estado sin señal, además
de la regresión BLE y diagnóstico ANT existente.

Pendiente: instalar esta nueva APK y validar una sesión real en S7/S20. La
detección previa confirmada no constituye validación en hardware de la nueva
pantalla, ni de pérdidas/reconexión o calibración de distancia.

Resultados de validación del 2026-11-13:

- `flutter analyze`: sin incidencias tras corregir las advertencias de estilo.
- `flutter test`: 13 pruebas correctas (11 existentes y 2 de entrenamiento).
- `cd android` y `./gradlew :app:testDebugUnitTest`: BUILD SUCCESSFUL,
  incluidas las pruebas del nuevo decodificador con capturas reales.
- `flutter build apk --debug`: primera compilación correcta. Después se añadieron
  ajustes de limpieza de métricas al perder señal, pantalla encendida,
  diagnóstico JSON y eventos de desconexión. Kotlin final compila en las pruebas
  Gradle, pero **la recompilación final de la APK no pudo ejecutarse**: la
  herramienta devolvió `rejected by user` para la autorización de ejecución fuera
  del aislamiento. Flutter necesita escribir en su caché fuera del proyecto.
  El archivo APK existente no representa el estado final del código y debe
  regenerarse con `flutter build apk --debug` antes de probar en el teléfono.
- Gradle informa deprecaciones preexistentes de la configuración Kotlin/AGP;
  no impiden compilar ni ejecutar las pruebas con las versiones instaladas.

Actualización posterior del 2026-11-13 (integración del nuevo icono):
`flutter analyze` y `flutter build apk --debug` completados correctamente.
La APK `build/app/outputs/flutter-apk/app-debug.apk` ya incluye los últimos
ajustes de telemetría descritos arriba. Queda resuelto el bloqueo anterior de
compilación; la prueba física de entrenamiento sigue pendiente.

La integración actual de control y parada se describe en [Entrenamiento libre](entrenamiento_libre_1_5.md).
