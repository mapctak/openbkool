# OpenBkool

**ENTRENAMIENTO LIBRE** comienza con un calentamiento y conecta por ANT
propietario con la identidad guardada del Bkool Smart Pro v1. El cuadro muestra
tiempo, velocidad, potencia, cadencia, distancia y un perfil de elevación virtual.
Al completarse la identificación, la autorización explícita habilita las 41
pendientes de −5 % a +15 % para esa sesión. Las pendientes negativas y superiores
a +8 % siguen pendientes de validación física completa.
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
