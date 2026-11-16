# Pendientes experimentales — OpenBkool 1.2.1+12

Rama `feature/control-ant`. Se añade un diagnóstico por nivel para **30064/112/5,
fabricante 67/modelo 22**, con selección, resultado API, enlace, temporizador,
parada y exportación JSON. El control continuo permanece bloqueado y Spinning
sigue siendo exclusivamente guiado.

**Resultado de esta entrega: +2 % y +3 % preparados, pero bloqueados físicamente.**
Los niveles 0 %, +0,5 % y +1 % conservan la activación expresa y 30 segundos.
No se ha encontrado evidencia técnica primaria suficiente del rango útil
admitido por el firmware concreto del modelo 22. La fórmula y una prueba
matemática no son esa evidencia, por lo que no se amplía el máximo operativo.

## 1. Verificación del formato original

Referencias: [protocolo_bkool.md](protocolo_bkool.md), sección de mensajes ANT,
y fuentes JADX locales excluidas de Git:

- `research/jadx/sources/com/bkool/sensors/tech/ant/devices/TrainerBkoolPro1.java`,
  `genericRequest()`, caso `TrackResist`, líneas 213–218.
- `research/jadx/sources/com/bkool/sensors/tech/ant/BkoolSensorAntPlus.java`,
  `changeBKOOLTraineSlope()`, líneas 214–219, segundo argumento 255.
- `BkoolSensorAntWrapper.sendBroadcast()`, líneas 547–553: transporte existente
  `AntChannel.setBroadcastData`. No se cambia por acknowledged.

La fórmula original es:

```java
int grade = (int)((percent + 200.0f) * 100.0f);
// 33 FF FF FF FF grade_low grade_high FF
```

| Entrada | Entero decimal | Entero hexadecimal | Payload de ocho bytes |
|---|---:|---|---|
| 0 % | 20000 | 0x4E20 | `33 FF FF FF FF 20 4E FF` |
| +0,5 % | 20050 | 0x4E52 | `33 FF FF FF FF 52 4E FF` |
| +1 % | 20100 | 0x4E84 | `33 FF FF FF FF 84 4E FF` |
| +2 % | 20200 | 0x4EE8 | `33 FF FF FF FF E8 4E FF` |
| +3 % | 20300 | 0x4F4C | `33 FF FF FF FF 4C 4F FF` |

Los cinco valores coinciden exactamente con la aritmética Float original: son
enteros o medios puntos representables exactamente y el resultado entero cabe
en los dos bytes sin desbordamiento. Las pruebas reconstruyen el entero desde
los bytes y lo comparan con la fórmula original, no solo con una cadena copiada.

### Formato representable no equivale a rango admitido

El controlador original inspeccionado no impone un clamp en ese método, pero
eso **no prueba** que el firmware acepte cada entero representable ni cómo lo
traduzca en carga. El informe estático ya identifica como no confirmados el
rango útil, repetición, respuesta real y aceptación por firmware.

Se investigó información comercial sobre Smart Pro, pero no se obtuvo una
especificación primaria que vincule su rango con **modelo 22, BKOOL_V1_PUBLIC y
el firmware de este rodillo**. No se toman especificaciones de Smart Pro 2/3 ni
reseñas comerciales como autorización técnica del modelo 22. Tampoco se
extrapola el rango FE-C estándar a este controlador propietario.

`encodeSlopeCandidate()` amplía su límite **solo offline** de +2 a +3 %, con
valores finitos, no negativos y múltiplos de 0,5. Ese límite de cálculo no se
publica como capacidad del firmware. `encodeManualSlope()` conserva máximo +1 %.
Además, `ManualAntControl.request(2/3)` registra rechazo explícito
`experimental_level_not_authorized`, `apiCalled=false`: el formato puede ser
calculable y aun así no estar autorizado. Valores negativos, NaN, infinito,
precisión no admitida y valores superiores al límite offline se rechazan.

## 2. Pantalla de diagnóstico por nivel

Acceso: **Ajustes → Diagnósticos avanzados → Pendientes experimentales**.
No se conecta ni se arma automáticamente al abrirla.

- Selector de nivel: 0 / +0,5 / +1 / +2 / +3 %.
- +2 y +3 se pueden **seleccionar para inspeccionar** el candidato; su activación
  está deshabilitada y el motivo aparece explícitamente. Seleccionar no transmite.
- Se muestran seleccionada, última pendiente ordenada por la API, resultado del
  controlador, error si existe, estado de enlace/control, tiempo restante,
  resultado de parada y resistencia física no confirmada.
- [−] [LLANO 0 %] [+] y «Detener prueba» permanecen al pie. El aumento no supera
  el nivel elegido ni +1 %. Al estar armado no puede cambiarse el nivel de ensayo.
- Para niveles ya validados: conectar explícitamente, esperar todas las
  comprobaciones nativas y confirmar el diálogo «Activar prueba». La activación
  no transmite una pendiente: los botones requieren otra acción del usuario.
- LLANO conserva la ruta de solicitud manual; detener conserva la ruta única
  de cero/cierre del controlador, que puede intentar cero con canal válido aun
  sin telemetría reciente. Ninguna vía promete reducción física.
- Se mantienen bloqueo por enlace/identidad dudosos, error RPC, cancelación de
  cola, muerte/cierre del canal, timeout, salida y segundo plano. Regresar no
  reactiva la prueba. Cada ensayo nuevo necesita conexión y confirmación nuevas.

La selección es un estado local de interfaz. Los envíos reales, errores,
pendientes ordenadas y paradas siguen siendo los del controlador Kotlin actual.
No se usa fabricante/modelo recordado como verificación de la conexión.

El JSON incluye `experimentalSlopePolicy` (diagnóstico nativo v7), con máximo
físico +1 %, `twoPercentEnabled=false`, `threePercentEnabled=false` y motivos.
La exportación de esta pantalla añade `experimentalSlopeSelection` con nivel,
selección, **candidatePayloadHex**, disponibilidad y bloqueo. El candidato no es
`payloadHex` de un envío: los envíos reales continúan en `manualControlEvents`.
El panel de transmisión existente conserva API/TX/cierre separados.

## 3. Condiciones antes de autorizar +2 %

Esta APK **no puede ejecutar una prueba física de +2 %**. El procedimiento
siguiente es una preparación condicionada para una revisión posterior:

1. Conseguir y revisar evidencia vinculada al controlador/firmware del modelo 22
   que admita +2 %, o una captura verificable del controlador original usando
   ese valor con el mismo modelo. Confirmar que no se confunde con Pro2, FE-C o
   una simple cifra de marketing de otra generación.
2. Revisar JSON y observación física de los ensayos 0/0,5/1, especialmente retorno
   a cero y parada; el éxito de API no certifica recepción ni neutralización.
3. Solo tras esa revisión, implementar una autorización experimental **aislada**
   de +2 para el diagnóstico, con tope de sesión y modo trial; no ampliar el
   máximo general, no permitirlo en continuo ni conectar objetivos de Spinning.
   No basta con cambiar un texto, el selector o una bandera JSON: hoy también
   bloquean el transporte nativo y el codificador operativo.
4. +3 seguirá bloqueado hasta revisar el resultado de +2, incluida la parada.
   Nunca se desbloquea por aceptar un paquete en la API ni por un test unitario.

No se guarda una aprobación automática entre sesiones ni se marca un nivel
como validado por haberlo seleccionado o exportado.

## 4. Procedimiento físico preparado para Galaxy S20

**Ahora solo pueden ejecutarse los controles de referencia hasta +1 %.** Para
+2 aplicar estos pasos únicamente cuando exista la autorización aislada del
punto anterior; no manipular manualmente las barreras de esta APK.

1. Rodillo estable, teléfono accesible y una nueva conexión con identidad,
   fabricante y modelo verificados en esta sesión. Revisar estado del enlace.
   Utilizar trial 30 s, nunca continuo, sin otras sesiones o cambios automáticos.
2. Pedaleo cómodo y suave; comprobar LLANO 0 %, respuesta de la API y reducción
   perceptible. Si ya es anómalo, no continuar el ensayo.
3. Activar expresamente el ensayo individual autorizado. Tras la autorización
   futura, solicitar **+2 % una sola vez**, brevemente (como guía, 3–5 segundos,
   no mantenerlo hasta el timeout), sin combinar inmediatamente con +3 ni
   aumentos repetidos. El formato por sí solo no predice la carga percibida.
4. Solicitar LLANO 0 %, esperar reducción perceptible y telemetría normal, luego
   detener ya en llano. Revisar último envío, cero de parada, cierre y errores.
   No probar una desconexión deliberada con resistencia elevada.
5. Si no reduce, hay carga inesperada, error o pérdida de enlace: **Detener
   prueba**, dejar de pedalear y dejar detenerse la rueda. No seguir aumentando,
   no insistir con comandos y no usar desconexiones deliberadas como ensayo.
   La aplicación puede no poder enviar cero; no garantiza resistencia neutra.
6. Exportar JSON y anotar por separado percepción mecánica, tiempos, incidencias
   y resultado de parada. Un retorno void o un evento TX no equivale a validación
   física. No realizar +3 hasta revisar expresamente esos resultados.

La rutina automática de seguridad conserva como máximo 30 s desde activación;
no es una recomendación de duración para mantener +2. Si se necesita repetir,
primero finalizar y revisar, después una conexión y confirmación nuevas.

## 5. Validación de esta entrega

- `flutter analyze`: sin incidencias.
- `flutter test`: **66 pruebas correctas**; selección +2/+3 sin autorización,
  confirmación expresa en niveles validados sin envío al armar, conservación del
  último éxito ante error, parada accesible y layouts S7/S20 simulados. Se conserva
  la prueba de Spinning sin órdenes automáticas.
- `./gradlew :app:testDebugUnitTest`: **75 pruebas correctas**; los cinco códigos
  comparados con Float original, formato, valores inválidos, autorización
  insuficiente incluso tras armar, y desconexión sin reintento. Se conservan los
  tests previos de cero, errores, carreras, cola, segundo plano y timeout.
- Transportes simulados: no se ha enviado ningún comando real en el desarrollo.
- `flutter build apk --debug`: correcto. **1.2.1+12**:
  `build/app/outputs/flutter-apk/openbkool-1.2.1-12-debug.apk`.

Se compila porque se añade una pantalla funcional y diagnóstico de rechazo,
no porque se haya autorizado un nivel superior. Firmware, bytes operativos de
0/0,5/1, parámetros ANT, BLE, telemetría, CSV, navegación y spinning conservados.
Pendiente validación física de la nueva pantalla y evidencia para abrir +2 %.
