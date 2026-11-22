# OpenBkool

**ENTRENAMIENTO LIBRE** conecta con el Bkool Smart Pro v1 por ANT propietario.
Muestra velocidad, potencia, cadencia, distancia y tiempo. La autorización
explícita habilita las 41 pendientes de −5 % a +15 % en pasos de 0,5 % para esa
sesión. Las pendientes negativas y superiores a +3 % siguen siendo experimentales.

Mantén OpenBkool visible durante el entrenamiento. Bloquear la pantalla,
cambiar de aplicación o salir del entrenamiento solicita la parada nativa.
Puedes copiar el CSV al finalizar y el JSON desde la sesión. [Entrenamiento libre y validación](docs/entrenamiento_libre_1_5.md).

Inicio permite seleccionar o buscar el rodillo recordado. **Ajustes →
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
