# OpenBkool

**Inicio** conecta automáticamente con el rodillo guardado en modo de solo
lectura. La tarjeta muestra **CONECTANDO…**, **CONECTADO** o **DESCONECTADO**
según el estado que publica el servicio Android. El estado conectado requiere
identidad ANT exacta, fabricante 67, modelo 22 y señal vigente. Si una búsqueda
agota su tiempo o se libera un enlace perdido, Inicio espera 15 segundos antes
de volver a intentarlo mientras permanece visible y en primer plano.

El servicio libera el canal de solo lectura al quitar la tarea, al permanecer
15 minutos en segundo plano o al iniciar los diagnósticos avanzados para que
puedan usar la radio. La pérdida de enlace y los fallos de servicio se gestionan
con la supervisión nativa. Un entrenamiento posterior usa el canal si sigue
vigente o continúa la conexión durante el calentamiento.

**ENTRENAMIENTO LIBRE** comienza con un calentamiento y conecta por ANT
propietario con la identidad guardada del Bkool Smart Pro v1. El cuadro muestra
tiempo, velocidad, potencia, cadencia, distancia y un perfil de elevación virtual.
Cuando Android verifica la conexión y confirma el control activo, empieza el
cronómetro de entrenamiento y se habilitan las 41 pendientes de −5 % a +15 %
mediante pasos de 0,5 %. Las pendientes negativas y superiores a +8 % siguen
pendientes de validación física completa.
[Cuadro de entrenamiento y perfil virtual](docs/cuadro_entrenamiento_1_7.md).

En Android, el servicio de entrenamiento mantiene ANT y ofrece **DETENER** en la
notificación. Puedes copiar el CSV y el JSON final tras detener. La continuidad
con la pantalla bloqueada y al cambiar de aplicación se comprobó en el Galaxy
S20 con OpenBkool 1.6.0. Queda pendiente repetir esa prueba durante el
calentamiento automático. [Segundo plano y procedimiento](docs/entrenamiento_segundo_plano_1_6.md).

**Ajustes → Rodillo seleccionado** permite sustituir el rodillo guardado. **Ajustes →
Diagnósticos avanzados** conserva la inspección de capacidades ANT, el escaneo
BLE y la exportación de un JSON combinado. La búsqueda ANT solamente recibe.
BLE enumera GATT sin escrituras, notificaciones ni DFU. [Búsqueda ANT](docs/deteccion_rodillos_ant.md) · [Diagnóstico ANT](docs/diagnostico_ant.md) · [Detección BLE](docs/deteccion_ble.md).

```sh
flutter analyze
flutter test
(cd android && ./gradlew :app:testDebugUnitTest)
flutter build apk --debug
```

La APK de depuración queda en `build/app/outputs/flutter-apk/app-debug.apk`.
