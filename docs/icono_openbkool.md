# Icono de lanzamiento de OpenBkool

Diseño vectorial original, creado mediante código: bicicleta de carretera blanca,
con dos ruedas, cuadro, sillín, pedal y manillar curvado; fondo esmeralda
`#008F70`. No utiliza texto ni el logotipo oficial de Bkool.

- Fuente editable: `assets/icon/openbkool.svg`.
- Vista previa: `assets/icon/openbkool.png` (512 × 512).
- Simulación de máscaras: `assets/icon/mask_preview.png` (círculo, cuadrado
  redondeado y cuadrado). Es una previsualización gráfica, no una captura del S20.
- Generación reproducible: `/usr/bin/python3 tool/generate_android_icons.py`.
  Usa librsvg y Cairo del sistema mediante ctypes, sin instalar paquetes Flutter.
- Iconos PNG Android: mdpi 48, hdpi 72, xhdpi 96, xxhdpi 144 y xxxhdpi 192 px.
- Android 8/API 26+: `mipmap-anydpi-v26/ic_launcher.xml`, fondo sólido y
  bicicleta VectorDrawable independiente para permitir la máscara del lanzador.
- Android 13/API 33+: `mipmap-anydpi-v33/ic_launcher.xml`, además una capa
  `monochrome`. Si se activan iconos temáticos, el lanzador puede sustituir
  el blanco y esmeralda por los colores del tema; el modo normal conserva el diseño.
- Manifest: `android:icon` y `android:roundIcon` apuntan a `@mipmap/ic_launcher`.
  Etiqueta visible de la aplicación: **OpenBkool**.

No se modificaron Dart de entrenamiento, BLE, ANT, Kotlin de comunicación,
permisos ni dependencias para este cambio de icono.

## Comprobaciones del 2026-11-13

Se inspeccionó visualmente el PNG y las tres máscaras simuladas: la bicicleta
permanece completa y reconocible. Se comprobaron las dimensiones de las cinco
densidades y el fondo exacto RGB (0, 143, 112).

`flutter analyze`: sin incidencias.

La consulta `adb devices -l` no muestra dispositivos conectados. Por tanto,
la verificación física en el **Galaxy S20 sigue pendiente**. Para completarla:
conectar el teléfono con depuración USB autorizada, instalar la APK generada,
y comprobar nombre e icono en cajón de aplicaciones y pantalla de inicio con
One UI. Revisar también el modo de iconos temáticos si está disponible. El
lanzador puede conservar el icono anterior en accesos directos antiguos; retirar
y volver a añadir el acceso si ocurre. No es necesario conectar con el rodillo.

`flutter build apk --debug`: correcto. APK actual:
`build/app/outputs/flutter-apk/app-debug.apk`.
Se inspeccionó el paquete con `aapt dump badging`: etiqueta `OpenBkool` y recurso
adaptativo API 33 seleccionado. El ZIP contiene los cinco PNG, el foreground
vectorial y los XML adaptativos API 26/API 33. Esta compilación también incorpora
el estado actual de la telemetría, cuya recompilación había quedado pendiente.
