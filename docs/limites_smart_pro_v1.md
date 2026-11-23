# Límites y parada del Smart Pro v1 — investigación

**Conclusión:** hay evidencia estática de que Bkool Mobile 1.12.0 permite solicitar
**+2 % y +3 % también por `TrainerBkoolPro1`**, no solo representarlos en bytes.
Su interfaz de pendiente admite **−5 a +15 %, paso 0,5 %**. Esto justifica
**preparar** un ensayo aislado de +2 %, condicionado a una recuperación
independiente comprobada. No demuestra el máximo ni la respuesta del firmware
de esta unidad. **No se desbloquean niveles ni se modifica OpenBkool.**

## 1. Evidencias de software y límites

Todas las rutas siguientes parten de `research/jadx/sources/` (fuentes locales
excluidas de Git). APK comprobada: `research/Bkool Mobile_1.12.0_Apkpure.apk`,
SHA256 `4d3b6da8ed92a8595f405655a759d084247573f74f1f2cbb85170f6eeea5fc85`.

| Evidencia | Referencia y consecuencia |
|---|---|
| Límite real de la interfaz original | `com/bkool/bkoolmobile/views/SessionForceView.java:20–22, 193–207`: cambio 0,5; clamp −5/+15; llama `onSlopeChanged(mSlopeValue)`. No hay tope +1. |
| Uso durante entrenamiento | `.../fragments/EntrenamientoFragment.java:119–122, 420–425`: el listener guarda el porcentaje y llama `changeBKOOLTrainerSlope`; la sesión de rodillo no introduce un límite por modelo. `beans/BMTarget.java:16` identifica `TYPE_SLOPE=2`. |
| Ruta hasta ANT | `EntrenamientoFragment.java:1031–1052` → `com/bkool/sensors/ManagerBkoolSensors.java:683, 694–718` → `.../tech/ant/BkoolSensorAntPlus.java:214–219`: usa el dispositivo ANT seleccionado; convierte Double a Float y pasa pendiente y 255 a `TrackResist`, para cualquier `AbstractAntPlusDevice`, incluido Pro1. |
| Selección explícita de Pro1 | `.../tech/ant/BkoolSensorAntWrapper.java:666–672`: tipo 112 + modo de búsqueda 1 crea `TrainerBkoolPro1`; modo 2 crea Pro2. Por tanto el camino anterior no se limita a FE-C/Pro2. |
| Conversión final Pro1 | `.../tech/ant/devices/TrainerBkoolPro1.java:213–224`: `grade=(int)((percent+200.0f)*100.0f)`; LE16 en bytes 5–6 de página `33`; resto `FF`. No valida/clampa rango, finitud ni desbordamiento. |
| Unidades y falso límite ±1 | `EntrenamientoFragment.java:1032` guarda pendiente/100 en la muestra. El filtro `−1..1` de `:766–768` corresponde a pendiente **estimada para la muestra en modo ERG**, no a un clamp de órdenes de ±1 %. |
| Otros controles, no intercambiables | `SessionForceView.java:16–18, 170–193`: objetivo ERG 0–4000 W, paso 5. `BkoolSensorAntPlus.java:223–237`: ERG pasa vatios; resistencia básica multiplica el entero por 2. `TrainerBkoolPro1.java:219–224`: ERG codifica W×4 en `31`, básica en un byte de `30`, sin clamps locales. Estos límites/órdenes no definen un rango de pendiente. |
| Configuración inicial | `EntrenamientoFragment.java:744` envía configuración de usuario/bicicleta; `BkoolSensorAntPlus.java:241–249` y Pro1 `:226–235` construyen `37`. La respuesta mecánica no depende necesariamente solo de la cifra de pendiente. |

**Alcance de la prueba:** desde cero, cuatro/seis incrementos de la vista producen
2/3 y alcanzan `TrackResist` si el conectado es Pro1. Es una ruta ejecutable
identificada estáticamente; no una captura de esa APK transmitiendo +2/+3 a esta
unidad ni una medición mecánica.

JADX muestra artefactos (`i=0`, variables duplicadas) en `sendValueToTrainer`.
Se contrastó su `classes.dex` con `dexdump -d`: 12 registros/3 argumentos,
`packed-switch v10` en offset de código `0x0097`; caso 0 → `0x012b`, llamada a
pendiente en `0x0134`; caso 2 → `0x0113`, llamada a resistencia básica en
`0x011b`. No se interpreta aquel `i=0` espurio como un cambio de todos los modos.
La tabla está en offset de archivo DEX `0x264d38`.

## 2. Rangos: tres evidencias distintas

| Nivel de certeza | Rango/puntos |
|---|---|
| **Probado físicamente por el usuario** en 30064/112/5, fabricante 67/modelo 22 | 0 %, +0,5 %, +1 %; aumento/reducción perceptibles. No demuestra una curva continua calibrada ni un máximo. |
| **Solicitable por la aplicación original** en su ruta Pro1 | −5..+15 %, paso 0,5; incluye +2/+3. Es límite de UI, no certificado del firmware. |
| **Posible pero no confirmado físicamente aquí** | +2/+3 y los demás valores de esa UI. No hay evidencia de que cada pendiente produzca exactamente esa carga ni de dónde satura el freno. |

Cálculo contrastado: 0→`20 4E`, 0,5→`52 4E`, 1→`84 4E`, 2→`E8 4E`,
3→`4C 4F`, dentro de `33 FF FF FF FF LL HH FF`. Los cinco casos coinciden con
Float original y caben en 16 bits. El campo binario **no convierte todos sus
valores representables en valores admitidos**. No se ha demostrado un límite
de firmware +15/+20 %, un rechazo de fuera de rango ni una política de saturación.

## 3. Pro1 frente a Pro2

Pro1 `connect():179–197` asigna red 0; Pro2 `connect():190–205`, red 1;
ambos usan tipo 112, RF40 y período32768. El wrapper documentado en
[protocolo_bkool.md](protocolo_bkool.md) configura PUBLIC frente a red privada.
La fórmula de pendiente es la misma, pero Pro1 usa byte 1 `FF` y Pro2 `25`
(hexadecimal, no modelo decimal 25) en `33/31/30` (`Pro2.java:224–238`).
Pro2 añade bloqueo `F1` y consulta de `F0` (`:249–253`), ausentes en Pro1.
Ambos decodificadores reconocen nombres para modelos 22/24; la clase elegida
por modo/red no se deduce únicamente del nombre comercial. No se trasladan
prestaciones de Pro2 al firmware de Pro1.

## 4. Mantenimiento y vuelta a llano

**Confirmado en el código:**

- Los cambios cancelan el Handler pendiente y se envían tras 500 ms
  (`EntrenamientoFragment.java:1033–1045`). Durante la sesión, el contador se
  refresca con Timer de 1000 ms (`:747–748`, `beans/Constants.java:20`) y
  `checkRefreshDataRoller():602–616` vuelve a solicitar pendiente/ERG al llegar
  a cinco si no está pausado: intención de refresco aproximado de 5 s.
- Seleccionar pendiente cero recorre la misma ruta `33 ... 20 4E FF`.
- Autopausa tras diez muestras de potencia cero y destrucción de la vista
  solicitan `sendValueToTrainer(2,0)` (`:622–641, :1109`): **resistencia básica
  cero**, página `30 FF FF FF FF FF FF 00`, no pendiente cero. Se verificó el
  despacho en DEX. ERG con objetivo cero hace lo mismo (`:1075–1080`).
- `TrainerBkoolPro1.disconnect():199–206` cierra/desasigna; no contiene por sí
  mismo una orden de neutralización ni un acuse mecánico.
- `stopSession():803–809` cancela el Timer; en la destrucción inspeccionada no
  se cancela expresamente el Handler de envío diferido de 500 ms. No se toma
  la parada de la app original como garantía frente a órdenes atrasadas.

**No demostrado:** que el refresco sea un keepalive obligatorio, que exista un
watchdog de 5 s, que el último objetivo se borre al cesar transmisiones o que
`30...00` equivalga mecánicamente a `33...20 4E`. El firmware podría mantener
consigna, caducar o cambiar de modo: son hipótesis. No se añade resistencia
básica cero a OpenBkool a partir de este hallazgo.

El contrato ANTLib 4.16, revisado en
[auditoria_buffer_ant_1_1_7.md](auditoria_buffer_ant_1_1_7.md), establece emisión
broadcast del esclavo en la siguiente ventana, sin acuse del receptor;
`close()` no equivale a `CHANNEL_CLOSED`. No especifica la reacción mecánica
cuando cesa el controlador. API aceptada, TX observado, cierre o corte eléctrico
no son pruebas de resistencia neutralizada.

## 5. Documentación del fabricante y recuperación independiente

El [manual BKOOL Classic/Pro, copia de la documentación del fabricante](https://manualzz.com/doc/27236585/bkool-classic--pro-trainer-user-manual),
§2.7, exige fijación correcta y no tocar la rueda en movimiento; describe
alimentación externa. No documenta rango ANT del modelo 22 ni una garantía de
liberación del freno al desenchufar. Se consultó el texto del manual, no sus FAQ
automáticas. El [manual del simulador BKOOL, §15](https://static.keiser.com/media/BKOOL-Cylcling-Simulator-Manual.pdf?mtime=20171122122237)
explica dependencia entre freno, velocidad y carga; tampoco especifica un
watchdog o recuperación mecánica de esta revisión de Pro1. Las cifras comerciales
de otras generaciones no resuelven estas cuestiones.

**Recuperación independiente a comprobar antes de +2:** verificar, con carga
baja ya validada, que esa bicicleta permite dejar de aportar esfuerzo sin que
la rueda arrastre los pedales, permanecer estable y dejar detenerse la rueda.
Tener una persona de apoyo y acceso al corte externo de alimentación, sin
acercarse a piezas móviles. El corte permite aislar eléctricamente, **no se
considera garantía de reducción**; no reanudar hasta comprobar el estado con
rueda detenida. No desmontar ni aflojar fijaciones bajo carga. Si no se puede
verificar esa salida del esfuerzo sin ANT/app, posponer la prueba con ciclista
y recurrir a evaluación en banco/servicio técnico.

## 6. Recomendación

**Sí procede preparar un ensayo individual +2**, ahora con evidencia de uso
previsto por el software Pro1 más sólida que la mera fórmula. **No procede aún
un desbloqueo automático ni una afirmación de rango físico seguro.** Primero
verificar la recuperación independiente anterior y revisar las paradas de los
niveles conocidos. Después, una futura autorización aislada permitiría:

1. Nueva conexión/identificación, confirmación expresa, trial ≤30 s y modo
   continuo bloqueado; empezar en llano con pedaleo suave.
2. Un solo +2 durante unos 3–5 s, sin +3; pedir llano y observar reducción,
   después detener ya en llano. No provocar desconexiones bajo carga.
3. Si no reduce o hay error: detener prueba, dejar de aportar esfuerzo, esperar
   rueda inmóvil y aplicar la recuperación independiente preparada; no insistir
   con incrementos ni asumir que otro paquete resolverá la situación.
4. Guardar JSON y observación física por separado. Revisar retorno, TX, cero y
   cierre sin confundirlos con aplicación. +3 permanece pendiente de esa revisión.

Se ha creado **solo este informe**: sin desbloqueos, cambios de protocolo,
firmware o protecciones; sin transmisión, APK nueva ni ejecución del rodillo.
