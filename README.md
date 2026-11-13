# OpenBkool

Diagnóstico BLE de un Bkool Smart Pro antiguo con Flutter y
`flutter_blue_plus 2.3.14`.

Busca durante 30 segundos sin filtros y muestra todos los dispositivos, con o sin
nombre, sus identificadores, RSSI y UUID anunciados. Destaca pistas `bkool` y
Cycling Power `0x1818`; permite conectar manualmente con cualquiera para enumerar
GATT y comprobar el servicio propietario Bkool. No realiza escrituras GATT
ni activa notificaciones ni modifica firmware.

En Android permite dispositivos cercanos y ubicación precisa, y activa Bluetooth
y los servicios de ubicación. La app solicita ubicación para evitar el filtrado
de algunas balizas; no consulta el GPS. Un rodillo solo ANT/ANT+ no aparecerá
con un escáner BLE.

«Exportar diagnóstico JSON» copia anuncios, descubrimientos y eventos al
portapapeles, incluso sin dispositivos o sin conexión GATT. Pégalo en un archivo
`.json`. Los resultados permanecen durante la sesión; al cerrar la app se pierden.

```sh
flutter analyze
flutter test
flutter build apk --debug
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`.

- [Implementación, validación y limitaciones de detección](docs/deteccion_ble.md).
- [Investigación estática del protocolo Bkool](docs/protocolo_bkool.md).

También está disponible «Diagnóstico ANT+»: consulta hardware declarado,
servicios instalados, proveedores, adaptadores y acceso temporal a una radio sin
abrir canales ni buscar el rodillo. Sus resultados se incluyen en el mismo JSON.
Consulta [implementación y límites ANT](docs/diagnostico_ant.md).

«Buscar rodillos ANT» permite buscar FE-C y Bkool V1 público de forma secuencial,
ver identificación y tramas V1 recibidas, detener y exportar el informe combinado.
No envía páginas de control. Bkool V2 sigue desactivado.
[Resultados y limitaciones de búsqueda ANT](docs/deteccion_rodillos_ant.md).

«Entrenamiento» recibe telemetría del Smart Pro v1 confirmado (ANT público,
ID 30064/112/5): velocidad, potencia, cadencia y distancia, con detección de
pérdida de señal. Al finalizar permite copiar el registro CSV. No transmite
comandos de control. [Formatos, capturas, pruebas y limitaciones](docs/telemetria_ant.md).

- [Icono original SVG, generación Android y comprobaciones](docs/icono_openbkool.md).

- [Preparación bidireccional ANT V1, sin comandos, y plan de primera prueba](docs/control_ant_preparacion.md).
