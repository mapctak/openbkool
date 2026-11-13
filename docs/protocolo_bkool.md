# Protocolo del Bkool Smart Pro en Bkool Mobile 1.12.0

Investigación estática realizada el 12 de noviembre de 2026 con JADX 1.5.6.
No se ha ejecutado la APK, abierto una conexión con el rodillo, enviado comandos,
actualizado firmware ni modificado el código Flutter.

## Resultado y grado de certeza

**Confirmado en la APK:** hay tres rutas de control: ANT propietario Bkool V1,
ANT propietario Bkool V2 y ANT+ FE-C; además existe una ruta BLE GATT propietaria.
`TrainerBkoolPro1` y `TrainerBkoolPro2` pertenecen a ANT, no son controladores BLE.
El control BLE transmite páginas de ocho bytes a una característica Bkool,
con formatos muy parecidos a los que construyen los controladores ANT propietarios.
No aparece FTMS en las rutas de rodillo estudiadas.

**Inferencia con apoyo del código:** es viable desarrollar un controlador local
independiente de los servidores Bkool. Los métodos de conexión y control estudiados
usan GATT o servicios ANT locales, sin token de cuenta en sus mensajes.
**No comprobado:** que el Smart Pro concreto del proyecto exponga BLE controlable,
qué firmware tiene, qué variante admite y si acepta los mensajes documentados.
Tampoco se ha demostrado que la aplicación original completa arranque o permita
entrenar sin sesión de usuario ni Internet.

## Muestra y reproducción

La ruta indicada en la petición, `research/bkool_mobile_1.12.0.apk`, no existe en
este workspace. Se analizó el archivo disponible, sin renombrarlo:

- Archivo: `research/Bkool Mobile_1.12.0_Apkpure.apk`.
- SHA-256: `4d3b6da8ed92a8595f405655a759d084247573f74f1f2cbb85170f6eeea5fc85`.
- Manifiesto decodificado: `research/jadx/resources/AndroidManifest.xml`, líneas
  3–4: `versionCode="76"`, `versionName="1.12.0"`.
- Esa identificación no verifica la autenticidad ni la firma de la distribución.

```sh
/home/xabu/tools/jadx/bin/jadx --version
sha256sum 'research/Bkool Mobile_1.12.0_Apkpure.apk'
/home/xabu/tools/jadx/bin/jadx -d research/jadx \
  'research/Bkool Mobile_1.12.0_Apkpure.apk'
```

JADX terminó con código 3, `finished with errors, count: 7`. Se generaron las cinco
clases prioritarias. Hay errores en dependencias como `DiffUtil`,
`GridLayoutManager` y clases Google; los métodos prioritarios no contienen
`Method not decompiled`. Esto **no convierte el Java reconstruido en una fuente
infalible**: también hay artefactos de reconstrucción en métodos sin ese aviso.

Se contrastaron dos métodos ambiguos con salidas adicionales:

```sh
/home/xabu/tools/jadx/bin/jadx -r --decompilation-mode simple \
  --single-class com.bkool.sensors.ManagerBkoolSensors \
  --single-class-output research/jadx/verification/ManagerBkoolSensors.java \
  'research/Bkool Mobile_1.12.0_Apkpure.apk'
/home/xabu/tools/jadx/bin/jadx -r --decompilation-mode simple \
  --single-class com.bkool.sensors.tech.ant.BkoolSensorAntWrapper \
  --single-class-output research/jadx/verification/BkoolSensorAntWrapper.java \
  'research/Bkool Mobile_1.12.0_Apkpure.apk'
/home/xabu/tools/jadx/bin/jadx -r --decompilation-mode fallback \
  --single-class com.bkool.sensors.tech.ant.BkoolSensorAntWrapper \
  --single-class-output research/jadx/verification/BkoolSensorAntWrapper.fallback.java \
  'research/Bkool Mobile_1.12.0_Apkpure.apk'
```

Las tres comprobaciones terminaron correctamente. Las líneas indicadas a
continuación corresponden a esta salida de JADX; los nombres de métodos son los
anclajes más estables para reproducir la investigación.

## Índice de evidencias

Todas las rutas de esta tabla son relativas a `research/jadx/sources/`.

| ID | Clase / archivo | Ubicación relevante |
|---|---|---|
| E1 | `com/bkool/sensors/tech/ant/devices/TrainerBkoolPro1.java` | `connect()` desde línea 179; `genericRequest()` desde 209; recepción de páginas en `onReceiveMessage()` |
| E2 | `com/bkool/sensors/tech/ant/devices/TrainerBkoolPro2.java` | `connect()` desde línea 190; `genericRequest()` desde 220; recepción de página `F0` |
| E3 | `com/bkool/sensors/tech/ant/devices/TrainerFEC.java` | `connectImpl()` desde 85; `genericRequest()` desde 185 |
| E4 | `com/bkool/sensors/tech/ble/BkoolSensorBle.java` | `connectDevice()`; métodos `changeBKOOL…` desde 185 |
| E5 | `com/bkool/sensors/tech/ble/devices/trainer/TrainerManager.java` | UUID en 38–48; `onServicesDiscovered()` en 70; `onCharacteristicChanged()` en 200; `readCharacteristicsTrainner()` en 269; `connect()` en 335; `writeCharacteristic()` en 387 |
| E6 | `com/bkool/sensors/tech/ble/BkoolSensorBleWrapperLollypop.java` | `onScanResult()` y `scanBtDevices()`; análogo `BkoolSensorBleWrapperKitKat.java` |
| E7 | `com/bkool/sensors/utils/UtilsDecoderBle.java` | `decodeDeviceAdvData()` y decodificadores de UUID |
| E8 | `com/bkool/sensors/tech/ant/BkoolSensorAntPlus.java` | `startProcedureScanning()`; métodos de control desde 214 |
| E9 | `com/bkool/sensors/tech/ant/BkoolSensorAntWrapper.java` | `assignChannel()` en 346; `sendBroadcast()` en 547; `crearSensorDeviceAnt()` alrededor de 646 |
| E10 | `com/bkool/sensors/beans/ConstantesSensors.java` | tipos, modelos y parámetros ANT; inicializador estático en 68–76 |
| E11 | `com/bkool/sensors/ManagerBkoolSensors.java` | `sendValueToTrainer()` desde 683; contrastado con `research/jadx/verification/ManagerBkoolSensors.java:516` |
| E12 | `com/bkool/bkoolmobile/fragments/EntrenamientoFragment.java` | `checkRefreshDataRoller()` en 602; configuración en 744; pendiente/ERG desde 1031 |
| E13 | `com/dsi/ant/plugins/antplus/pcc/AntPlusFitnessEquipmentPcc.java` | `requestSetBasicResistance()` en 1984; potencia en 1995; pendiente en 2029; constantes IPC desde 711 |
| E14 | `com/dsi/ant/plugins/antplus/pccbase/AntPlusCommonPcc.java` y `AntPluginPcc.java` | `sendRequestCommand()` en 255 y `sendPluginCommandInternal()` en 536, respectivamente |
| E15 | `com/bkool/registrousuarios/connection/tasks/user/LoginTaskBkoolApi.java` y `com/bkool/registrousuarios/connection/tasks/general/CheckLastFirmwareBkoolApi.java` | `doInBackground()`: HTTPS de cuenta y consulta de firmware, separado del transporte del rodillo |

## 1. Descubrimiento y elección de controlador

### BLE: confirmado

`BkoolSensorBle.newInstance()` elige KitKat para API <21 y Lollypop para API ≥21.
El primero llama a `BluetoothAdapter.startLeScan`; el segundo a
`BluetoothLeScanner.startScan(null, settings, callback)` con `setScanMode(2)`.
No aplica un filtro del sistema por fabricante: interpreta cada anuncio después.
[E4, E6]

El criterio para rodillo es que el anuncio contenga el servicio `0x1818`
(Cycling Power). Si el nombre es nulo o contiene `bkool` sin distinguir mayúsculas,
lo clasifica como tipo 3, rodillo; con nombre no nulo que no contenga `bkool`,
tipo 5, potenciómetro. También distingue pulsómetro, CSC y anuncios de DFU.
**No busca exclusivamente el servicio propietario de configuración.** [E6]

Fragmento de `onScanResult()`:

```java
} else if (UtilsDecoderBle.decodeDeviceAdvData(bytes, TrainerManager.TRAINER_SERVICE_ID)) {
    if (device.getName() != null && !device.getName().toLowerCase(Locale.getDefault()).contains("bkool")) {
        bkoolSensorDevice.setType(5);
    } else {
        bkoolSensorDevice.setType(3);
    }
}
```

`UtilsDecoderBle` exige además flags LE discoverable: `(flags & 3) > 0` y UUID
reconocido. Examina AD types 2/3, 4/5 y 6/7. Sus decodificadores de UUID de 32 y
128 bits comparan una porción de 16 bits, no el UUID completo; es una peculiaridad
de la app original, no un criterio que debamos copiar sin evaluar. [E7]

### ANT y ANT+: confirmado

`BkoolSensorAntPlus` divide el tiempo de búsqueda en seis bloques y alterna
`indexRepeticion % 3`: ANT+ estándar, ANT Bkool V1, ANT Bkool V2, dos vueltas.
ANT+ usa `MultiDeviceSearch`; las otras dos búsquedas abren un canal de escaneo
en segundo plano, con ID comodín 0. [E8, E9]

| Controlador | Transporte / selección | Configuración observada |
|---|---|---|
| `TrainerBkoolPro1` | ANT propietario, device type 112 (`0x70`), encontrado en modo 1 | `PredefinedNetwork.PUBLIC`, período 32768, parámetro RF 40, channel type 0 |
| `TrainerBkoolPro2` | ANT propietario, device type 112 (`0x70`), encontrado en modo 2 | `acquireChannelOnPrivateNetwork`, constante `ANT_BKOOL2_NETWORK_PRIVATE`, período 32768, RF 40, channel type 0 |
| `TrainerFEC` | ANT+ Fitness Equipment / FE-C, device type 17 (`0x11`) | `AntPlusFitnessEquipmentPcc.requestNewOpenAccess(context, id, 0, …)` |
| `BkoolSensorBle` + `TrainerManager` | BLE GATT | anuncio `1818`, control en servicio propietario |

Fuentes: E1–E4, E8–E10. ANT no usa UUID GATT. Las cifras de período y RF de la tabla
son los argumentos efectivos de la API, sin asumir una frecuencia de envío de
comandos a partir de ellos.

La constante de red V2 está incorporada en la APK: `ConstantesSensors.java:74`
contiene **16 bytes**, pasados directamente al constructor `NetworkKey`:

```text
8D 1E DE 3A 5D 5E B7 7C B6 39 1A 3A 44 86 15 70
```

Esto confirma un parámetro local de red privada, no una clave descargada del
servidor. No se ha determinado cómo el servicio ANT externo interpreta esos
16 bytes; no debe reducirse sin evidencia a una supuesta clave de radio de ocho.
`com/dsi/ant/channel/NetworkKey.java` conserva el array y lo transporta por IPC.

**Precaución de identidad:** los sufijos de clase Pro1/Pro2 designan rutas de
protocolo elegidas por la búsqueda; no prueban una correspondencia exclusiva con
modelos físicos. Ambas clases reconocen modelo 22 como Smart Pro v1 y modelo 24
como Smart Pro v2 en la página `0x50`; `TrainerFEC` también reconoce esos modelos.
`ConstantesSensors` confirma esos IDs. [E1–E3, E9, E10]

### Bluetooth clásico: evidencia negativa limitada

No se encontraron `BluetoothSocket`, `createRfcomm…`, `startDiscovery` ni
`ACTION_FOUND` en `sources/com/bkool`. Las rutas estudiadas usan escaneo LE/GATT
o ANT. Por tanto **no hay evidencia de control RFCOMM/SPP en estos controladores**;
no es una prueba universal de que ningún firmware Bkool pueda tener Bluetooth clásico.

## 2. UUID y secuencia de conexión BLE

Valores literales de `TrainerManager` [E5]. El servicio propietario tiene
**`f03eee01`**, mientras sus características empiezan por **`f03ee0…`**;
no son prefijos intercambiables.

| Función | UUID completo | Uso observado |
|---|---|---|
| Servicio Cycling Power | `00001818-0000-1000-8000-00805f9b34fb` | detección y telemetría alternativa |
| Cycling Power Measurement | `00002a63-0000-1000-8000-00805f9b34fb` | notificaciones de potencia y datos opcionales |
| Servicio Device Information | `0000180a-0000-1000-8000-00805f9b34fb` | información del rodillo |
| Hardware Revision | `00002a27-0000-1000-8000-00805f9b34fb` | lectura de texto, convertido con `Integer.decode` a `tipoTrainer` |
| Firmware Revision | `00002a26-0000-1000-8000-00805f9b34fb` | lectura de texto de versión |
| Servicio de configuración Bkool | `f03eee01-4910-473c-be46-960948c2f59c` | contiene las tres características propietarias |
| Configuración / control | `f03ee002-4910-473c-be46-960948c2f59c` | destino de los mensajes de control |
| Magnitudes | `f03ee006-4910-473c-be46-960948c2f59c` | notificaciones de telemetría propietaria |
| Estado | `f03ee004-4910-473c-be46-960948c2f59c` | notificaciones de estado |
| CCCD | `00002902-0000-1000-8000-00805f9b34fb` | suscripción a notificaciones |
| Servicio DFU reconocido | `00001530-1212-efde-1523-785feabcd123` | se detecta y registra; no es el canal normal de control |

Los wrappers también identifican anuncios de mantenimiento mediante constantes de
`com/bkool/sensors/tech/ble/devices/trainer_dfu/TrainerManagerDFU.java:82–84`:
`00000002-0000-1000-8000-00805f9b34fb` y
`0000fe59-1212-efde-1523-785feabcd123` (este último es el literal de esta APK,
no una normalización al UUID base Bluetooth). Son rutas DFU separadas, no
UUID adicionales necesarios para regular resistencia.

Secuencia confirmada en E4/E5:

1. `connectDevice(type=3)` llama al `TrainerManager` del rodillo.
2. `connectGatt(context, false, callback)`; en API ≥23 añade transporte `2` (LE).
3. Al recibir estado conectado con status 0, llama a `discoverServices()`.
4. Localiza las características de la tabla. Lee hardware; después firmware,
   y continúa con `readCharacteristicsTrainner()`.
5. Prefiere notificaciones de Magnitudes si existe; en su ausencia usa `2a63`.
   Configura notificación local y escribe `ENABLE_NOTIFICATION_VALUE` en CCCD
   (valor Android `01 00`). Después de escribir el CCCD de Magnitudes, configura
   de la misma manera Estado si está presente.
6. Los cambios de pendiente/ERG/resistencia usan `mConfigCharacteristic`.
   `writeCharacteristic(str, false)` selecciona tipo de escritura `1`
   (`WRITE_TYPE_NO_RESPONSE`). El parámetro `true` seleccionaría tipo `2`.

Fragmento literal de E5:

```java
bluetoothGattCharacteristic.setWriteType(z ? 2 : 1);
bluetoothGattCharacteristic.setValue(fromHexString(str));
if (this.mBluetoothGatt != null) {
    this.mBluetoothGatt.writeCharacteristic(bluetoothGattCharacteristic);
}
```

No se ha encontrado un intercambio de autenticación de cuenta en esa secuencia,
ni una petición de control FTMS. La existencia del servicio Cycling Power no
basta para afirmar que se pueda controlar el dispositivo: debe estar presente
la característica propietaria de configuración. La app original retorna sin
escribir si esa característica es nula. [E5]

**Límite del análisis:** leer servicios GATT es distinto de reproducir la conexión
completa de Bkool Mobile: esta última sí escribe CCCD. Nada de esa secuencia se
ha ejecutado en el rodillo durante esta investigación.

## 3. Mensajes de pendiente, ERG y resistencia

### BLE y ANT propietario: formatos confirmados

En esta sección los índices de byte empiezan en 0; todos los valores de los
mensajes están en hexadecimal. `FF` representa el byte Java `-1`.
`LE16(x)` significa byte bajo seguido de byte alto. Las fórmulas reproducen
las conversiones y truncamientos de la APK; no añaden validación de límites.

Para BLE, `H = FF` si `tipoTrainer <= 23`, o `H = 25` si `tipoTrainer > 23`.
No se envían pendiente, ERG ni resistencia mientras `tipoTrainer == -1`.
El `25` es **hexadecimal** (37 decimal), no el modelo 25. Su significado interno
no está demostrado; se confirma su posición y la condición que lo elige. [E4]

| Operación | Ocho bytes BLE | Conversión |
|---|---|---|
| Pendiente | `33 H FF FF FF gL gH FF` | `g = (int)(((float)pendiente + 200.0f) * 100.0f)`; `gL,gH = LE16(g)` |
| Potencia ERG | `31 H FF FF FF FF pL pH` | `p = vatios * 4`; `pL,pH = LE16(p)` |
| Resistencia lineal | `30 H FF FF FF FF FF r` | `r = (nivel * 2) & FF` |

La pendiente está expresada en **porcentaje**: `EntrenamientoFragment` entrega
`slopeTarget` al controlador y la registra con `%`; para guardar el dato divide
por 100. La potencia se registra en W. [E12]

Fragmento literal de pendiente BLE [E4, `changeBKOOLTraineSlope()`]:

```java
byte[] bArr = {51, this.mTrainerManager.getTipoTrainer() > 23 ? (byte) 37 : (byte) -1, -1, -1, -1, 0, 0, -1};
int i = (int) ((((float) d) + 200.0f) * 100.0f);
bArr[5] = (byte) (i & 255);
bArr[6] = (byte) ((i >>> 8) & 255);
this.mTrainerManager.writeCharacteristic(UtilSensors.toHexString(bArr), false);
```

Ejemplos **calculados estáticamente**, no transmitidos, para la variante BLE
con `H=FF`:

| Entrada | Payload calculado |
|---|---|
| Pendiente 0 % | `33 FF FF FF FF 20 4E FF` |
| Pendiente +5 % | `33 FF FF FF FF 14 50 FF` |
| Pendiente −5 % | `33 FF FF FF FF 2C 4C FF` |
| ERG 200 W | `31 FF FF FF FF FF 20 03` |
| Nivel de resistencia 25 | `30 FF FF FF FF FF FF 32` |

En `TrainerBkoolPro1.genericRequest()` los mismos tres opcodes usan `H=FF`;
en `TrainerBkoolPro2.genericRequest()` usan `H=25`, sin consultar el hardware.
La pendiente toma el último byte del segundo argumento: el adaptador ANT le
entrega 255, por lo que resulta `FF`. La resistencia se duplica en
`BkoolSensorAntPlus` **antes** de entrar en `genericRequest`; no se duplica de nuevo
allí. Después se llama a `sendBroadcast()` → `AntChannel.setBroadcastData()`.
No es una escritura BLE ni se usa `sendAcknowledged()` en esos métodos. [E1, E2, E8, E9]

**No confirmado:** rango útil y respuesta real de resistencia, significado exacto
de `H`, necesidad de repetición, aceptación por un firmware concreto y tratamiento
de valores fuera de rango. Las fórmulas por sí solas no prueban estos extremos.

### `TrainerFEC`: interfaz ANT+ confirmada; serialización externa

`genericRequest()` llama a `AntPlusFitnessEquipmentPcc` [E3]:

```java
case TrackResist:
    return ((AntPlusFitnessEquipmentPcc) this._pcc).getTrainerMethods().requestSetTrackResistance(new BigDecimal(((Float) objArr[0]).floatValue()), new BigDecimal(((Float) objArr[1]).floatValue()), requestResultReceiver);
```

| Operación | Método del SDK / datos observados | IPC local del SDK |
|---|---|---|
| Pendiente | `requestSetTrackResistance(grade, rollingResistanceCoefficient, receiver)`; el adaptador pasa pendiente y `255.0f` | `20009`; Bundle `decimal_grade`, `decimal_rollingResistanceCoefficient` |
| ERG | `requestSetTargetPower(watts, receiver)` | `20004`; `decimal_targetPower` |
| Resistencia | `requestSetBasicResistance(value, receiver)`; recibe `nivel * 2` del adaptador Bkool | `20002`; constante `…decimalTOTALRESISTANCE` |
| Viento | `requestSetWindResistance(...)` | `20006` en la sobrecarga usada |
| Usuario/bicicleta | `requestSetUserConfiguration(...)` | objeto del SDK |

E13 construye `Bundle` y E14 envía `Message` mediante `mPluginMsgr.send(message)`
a un servicio Android. **Los números 20002/20004/20009 son identificadores IPC,
no páginas de radio.** La serialización FE-C final reside en el servicio ANT+
externo y no queda demostrada por esta APK. No debe afirmarse que el SDK envíe
literalmente los arrays de Pro1/Pro2, ni reinterpretar o corregir silenciosamente
la duplicación de resistencia o el valor 255 del coeficiente: podrían ser
convenciones de esa versión o errores de la app; falta verificar el servicio.

La semejanza con páginas FE-C `0x30/0x31/0x33` es una **inferencia de formato**
para las rutas propietarias. El uso del perfil FE-C en `TrainerFEC` sí está
confirmado por las clases y métodos del SDK.

### Configuración de usuario y estado

La conexión original puede acompañarse de configuración de usuario. BLE genera
`37 uL uH FF bL bH 70 x`, con peso de usuario ×100 en bytes 1–2, peso de bicicleta
×500 en 4–5, byte 6 fijo a 112 decimal y byte 7 opcional (0 por defecto).
`EntrenamientoFragment` usa `pesoUsuario/1000` y 8 para la bicicleta. Las variantes
ANT propietarias construyen la misma distribución a partir de `UserConfig`.
Las unidades kg para esos pesos están apoyadas por el uso de la app, pero el
significado físico del byte fijo `70` y del byte opcional no queda validado
por el rodillo; E11 relaciona este último con una tabla de relaciones de cambio.
[E1, E2, E4, E8, E11, E12]

También existe `Block`, opcode `F1`, para hardware >23, con byte 1 `FF` o `C0`;
Pro2 incorpora además `RequestBlocked` con página de solicitud `46`.
Esto prueba que hay lógica de bloqueo/estado, **no que exista un desbloqueo con
servidor ni que sea necesario bloquear para controlar**. [E2, E4, E8]

Se localizaron rutas de DFU separadas y métodos de cambio a DFU. No se incluyen
como parte de la secuencia de control propuesta ni se han ejecutado.

### Ritmo de envío observado en la aplicación

`EntrenamientoFragment` retrasa los cambios 500 ms y cancela el envío pendiente
al recibir otro cambio. `checkRefreshDataRoller()` incrementa un contador y
reenvía pendiente/ERG al alcanzar cinco si no está en pausa. El temporizador se programa en la línea 748 con `Constants.TIME_TO_SAVE_VALUES`,
definido como 1000 ms en `com/bkool/bkoolmobile/beans/Constants.java:20`; por tanto
la intención de la app es refrescar aproximadamente cada cinco segundos, más el
retardo de envío. Esto no demuestra un intervalo obligatorio impuesto por el rodillo.
Al finalizar la vista intenta resistencia 0; ERG con objetivo 0 también deriva
a resistencia 0. [E12]

## 4. Telemetría y mensajes entrantes

**Confirmado en el parser BLE** [E5]:

- Magnitudes: `ByteBuffer` little endian; primer `uint16` = potencia, segundo
  `uint16` = velocidad, último byte = cadencia; `FF` se convierte a −1.
  No se ha establecido la longitud total obligatoria solo a partir de ese parser.
- `TrainerManagerCallbacksImpl.java` convierte la velocidad de Magnitudes con
  `valor / 1000 * 3.6`; esto apoya que sea mm/s y que el resultado sea km/h.
- `2a63`: lee potencia en offset 2 y flags en offset 0; interpreta datos opcionales
  de revoluciones de rueda/biela para velocidad y cadencia.
- Estado: toma el primer byte y publica máscaras literales `1`, `2`, `4`, `8`,
  **22 y 50 decimales**. Las dos últimas no son bits individuales; no se han
  corregido a supuestos valores `0x10/0x20`. Los nombres de evento incluyen
  `IN_USE`, `VIRTUAL_SPEED`, `SPEED_TOO_LOW`, `SPEED_TOO_FAST`, `NEED_CONFIG_USER`
  y `BLOCKED` en E10, pero no bastan para validar el mapa físico de bits.

**Confirmado en Pro1/Pro2** [E1, E2]:

- Extraen ocho bytes de datos del mensaje ANT extendido, no del anuncio BLE.
- Página `10`: distancia acumulada (byte 3) y velocidad LE16 (bytes 4–5),
  convertida con `*0.001*3.6`.
- Página `19`: cadencia (byte 2) y potencia de 12 bits (byte 5 + nibble bajo del 6).
- Página `50`: modelo LE16 (bytes 6–7); 22 decimal = Pro v1; 24 decimal = Pro v2.
- Pro2 reconoce adicionalmente página `F0`, pero solo registra la trama como estado.

Los parsers muestran lo que la app interpreta; no sustituyen capturas de radio.

## 5. Comunicación local y dependencia de servidores

**Hechos confirmados:**

1. Los parámetros de pendiente, potencia y resistencia llegan desde la vista de
   entrenamiento a `ManagerBkoolSensors.sendValueToTrainer()` y después a BLE o
   ANT según `sensorUsed`. No se agrega credencial de usuario a los payloads.
2. BLE termina en `BluetoothGatt.writeCharacteristic()`; ANT propietario en
   `AntChannel.setBroadcastData()`; FE-C en IPC a ANT+ Plugins Service.
3. El parámetro de red privada V2 está incluido en la APK. No se observó una
   descarga de clave de sesión en esos controladores.
4. La APK también usa servidores: `LoginTaskBkoolApi.doInBackground()` realiza
   un POST HTTPS de autenticación y procesa tokens; `CheckLastFirmwareBkoolApi`
   consulta por HTTPS información de firmware. Son funciones distintas del
   transporte del rodillo. [E15]

**Conclusión inferida:** un cliente como OpenBkool puede implementar la comunicación
local con el protocolo que realmente ofrezca el rodillo, sin reproducir login,
API de sesiones ni actualizaciones. En ANT+ necesitará radio ANT y una pila/servicio
compatible; un adaptador BLE por sí solo no proporciona ANT. En BLE, disponer de
`1818` sin `f03ee002` permite observar datos, pero no prueba capacidad de control.

**Pendiente de confirmar:** publicidad y GATT reales, revisión de hardware y
firmware, disponibilidad del control al estar offline, semántica de bloqueo y
necesidad de configuración de usuario. No se ha probado la aplicación original
en modo avión, ni descartado dependencias de cuenta en sus pantallas de entrada.
No se deduce del análisis que haga falta actualizar firmware.

## 6. Artefactos dudosos de JADX y verificación

El Java normal de `ManagerBkoolSensors.sendValueToTrainer()` aparenta poner `i=0`
antes del `switch`, lo que haría inaccesibles los otros comandos. La salida
**simple**, líneas 516–545, mantiene `switch(r10)`, donde `r10` es el argumento
original. Por tanto no se toma aquella asignación como comportamiento demostrado.

El Java normal de `BkoolSensorAntWrapper.assignChannel()` aparenta retornar `null`
tras configurar un canal no destinado a escaneo. La salida simple también tiene
saltos ambiguos entre bloques de excepciones. La salida **fallback**, desde línea
749, permite comprobar el camino normal: tras `setSearchTimeout`, cae en `Laa`,
configura ID/RF, y alcanza `Lf4: return r7`. No se concluye que el controlador ANT
esté inoperante a partir del Java reestructurado.

Fragmento de instrucciones de esa salida fallback:

```text
r7.setPeriod(r9)
...
r7.setSearchTimeout(r8, r9)
Laa:
...
r7.setChannelId(r9)
r7.setRfFrequency(r10)
...
Lf4:
    return r7
```

La lectura de hardware en `TrainerManager.onCharacteristicRead()` también tiene
advertencias de extracción de `finally`; el camino exitoso de lectura hardware →
firmware → notificaciones es visible, pero no se ha validado cada camino de error.

Comandos útiles para revisar las evidencias sin ejecutar la app:

```sh
rg -n 'changeBKOOL|writeCharacteristic|fromString' \
  research/jadx/sources/com/bkool/sensors/tech/ble
rg -n 'TrackResist|TargetPower|BasicResistance|sendBroadcast' \
  research/jadx/sources/com/bkool/sensors/tech/ant
rg -n 'BluetoothSocket|createRfcomm|startDiscovery|ACTION_FOUND|00001826|00002ad9' \
  research/jadx/sources/com/bkool
```

La ausencia de coincidencias en el último comando es evidencia negativa limitada
al código Bkool descompilado, no una certificación de todos los recursos o firmware.

## 7. Exclusión de Git y siguiente fase

`.gitignore` excluye APK en `research/`, la salida `research/jadx/` (incluidas
las verificaciones) y proyectos `*.jadx`. La documentación se conserva en `docs/`.
En este entorno `.git/` está vacío y no es un repositorio utilizable: no se puede
comprobar el índice real con `git ls-files` ni retirar archivos ya versionados.
Se comprobó la coincidencia de las reglas en un repositorio temporal.
Si alguno de esos artefactos estuviese ya seguido en otro checkout, `.gitignore`
no lo retiraría del índice ni del historial.

La siguiente fase debe seguir siendo de observación: comparar anuncio y UUID GATT
exportados de nuestro rodillo con esta tabla e identificar hardware/firmware.
La selección entre ANT propietario, ANT+ FE-C y BLE depende de esa evidencia real.
Esta investigación documenta los comandos, pero no autoriza ni implementa su envío.
