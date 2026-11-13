# ANTLib oficial

`android_antlib_4-16-0.aar` es el artefacto binario original, sin modificaciones,
del SDK oficial Dynastream/ANT Wireless. No procede de la APK Bkool descompilada.

- Repositorio: https://github.com/ant-wireless/ANT-Android-SDKs
- Commit fijado: `0e8cea714a231fb9565170d4ed01eafa868f9798`.
- Archivo: `ANT_Android_SDK/API/android_antlib_4-16-0.aar`.
- Descarga: https://raw.githubusercontent.com/ant-wireless/ANT-Android-SDKs/0e8cea714a231fb9565170d4ed01eafa868f9798/ANT_Android_SDK/API/android_antlib_4-16-0.aar
- SHA-256: `944fab1871b18f2b191228af720aaa2eb7057312ffa18d7150f96d1859562d17`.
- Documentación del distribuidor: https://github.com/ant-wireless/ANT-Android-SDKs/blob/0e8cea714a231fb9565170d4ed01eafa868f9798/ANT_Android_SDK/API/README.md

Copyright Dynastream Innovations Inc. Se conservan los avisos del artefacto;
consultar el SDK original para las condiciones del distribuidor. La documentación
Javadoc se consultó para implementar las llamadas y no se incluye en la app.

## Búsqueda ANT+ FE-C

Del mismo commit oficial se incorporan:

- `ANT+_Android_SDK/API/antpluginlib_3-9-0.aar`, SHA-256
  `ba0ead4f393209ca5742738fde058672f4cfe3fd1a6553f12022076d8c279559`.
- `ANT+_Android_SDK/API/fit_21.105.00.jar`, dependencia del perfil Fitness Equipment,
  SHA-256 `8cd91f26985c704e31c2b3890cead2ad1a899a018ca28ea21ab150cbac4af03d`.

Ambos son binarios oficiales sin modificaciones. Documentación:
https://github.com/ant-wireless/ANT-Android-SDKs/tree/0e8cea714a231fb9565170d4ed01eafa868f9798/ANT%2B_Android_SDK/API

FIT se utiliza como dependencia de las clases del perfil; la app no crea,
sube ni modifica archivos de entrenamiento ni firmware.
