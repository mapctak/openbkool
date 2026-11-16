# Recuperación y preparación del ensayo aislado +2 %

> Informe histórico de preparación 1.2.1. El usuario confirmó posteriormente
> la salida independiente del esfuerzo en este montaje. El estado vigente y la
> autorización aislada 1.2.2 se describen en
> [prueba_aislada_2_por_ciento_1_2_2.md](prueba_aislada_2_por_ciento_1_2_2.md).

Revisión: 2026-11-16, rama `feature/control-ant`, base 1.2.1+12.

**Decisión: +2 % y +3 % siguen bloqueados.** Se ha identificado la orden original
de resistencia básica cero, pero no una garantía de liberación mecánica ni una
recuperación independiente comprobada en esta unidad. Se conserva la pantalla
experimental y su previsualización offline; no se conecta su candidato +2 % al
transporte. La parada de producción sigue solicitando **pendiente cero**, máximo
+1 %, 30 segundos y activación expresa. No se añaden refrescos periódicos.

## 1. Evidencia exacta de resistencia básica cero

Fuentes relativas a `research/jadx/sources/`, excluidas de Git. APK y SHA256,
ruta Pro1 y verificación del despacho DEX: [limites_smart_pro_v1.md](limites_smart_pro_v1.md).

| Paso original | Referencia verificable |
|---|---|
| Solicitud de parada `sendValueToTrainer(2, 0.0d)` | `com/bkool/bkoolmobile/fragments/EntrenamientoFragment.java:638,1109`; ERG objetivo cero también en `1075–1079`. |
| Caso 2 convierte el argumento a entero y llama a `changeBKOOLTrainerLinealResistance` | `com/bkool/sensors/ManagerBkoolSensors.java:726–730`; caso 0 (`713–718`) es pendiente. El `i=0` espurio de JADX se contrastó con DEX en el informe anterior. |
| El wrapper de sensor pasa `Integer.valueOf(i * 2)` a `BasicResistance` | `com/bkool/sensors/tech/ant/BkoolSensorAntPlus.java:232–237`. Para cero, argumento final = 0. |
| Pro1 construye `{48,-1,-1,-1,-1,-1,-1,(byte)(value & 255)}` | `.../tech/ant/devices/TrainerBkoolPro1.java:223–224`. |
| Se envía como broadcast | Pro1 `:251` → `BkoolSensorAntWrapper.java:547–553` → `AntChannel.setBroadcastData(bArr)`. El wrapper captura errores y solo los registra. |

Payload ANT de ocho bytes, **sin** ID de mensaje ni número de canal:

```text
Resistencia básica cero: 30 FF FF FF FF FF FF 00
Pendiente cero actual:   33 FF FF FF FF 20 4E FF
Candidato +2 %:          33 FF FF FF FF E8 4E FF
```

`0x30` selecciona la ruta de **resistencia básica**; no es una variante de la
pendiente `0x33`. La conversión original x2 es compatible con resolución de
medio punto porcentual de resistencia básica, pero no demuestra una equivalencia
física entre ese porcentaje y la pendiente. `0x33` usa
`int((percentFloat + 200f) * 100f)`, LE16 en bytes 5–6. Los `FF` no son campos
de confirmación. No se infiere un rango físico de básica a partir de un byte.

**Compatibilidad demostrada estáticamente:** la clase Pro1 implementa ambas
rutas. El wrapper elige Pro1 para tipo 112/modo público 1 (`:666–672`), utilizado
por el Smart Pro v1 identificado como fabricante 67/modelo 22. Esto prueba el
soporte en la aplicación original; no que esta unidad haya recibido/aplicado
`30...00`. Pro2 usa byte 1 `25`, red privada y órdenes de bloqueo adicionales;
no se copian a Pro1 (`TrainerBkoolPro2.java:224–253`).

## 2. Cambio de modo y secuencia original de parada

- La creación de la vista solicita básica cero (`EntrenamientoFragment:435`).
  OpenBkool no copia esta inicialización: conserva la prohibición de transmitir
  al entrar. El botón original Finalizar (`453–454`) llama a
  `onEnterButtonClicked:596–598`: pausa y abre el diálogo de guardar. Esa llamada
  no envía cero directamente; la solicitud identificada está en `onDestroy`.
- Autopausa: tras diez muestras con potencia cero, pone `mPaused=true`, solicita
  básica cero y reinicia valores de la vista (`EntrenamientoFragment:622–640`).
- Destrucción: solicita básica cero en `onDestroy:1109` y luego llama
  `stopSession:1111`; este cancela el Timer (`803–809`).
- ERG a cero: el callback envía básica cero en lugar de potencia objetivo cero
  (`1075–1079`). Seleccionar pendiente cero sigue usando `TrackResist`.
- No aparece un paquete previo independiente de selección de modo Pro1: el
  cambio de tipo de orden es la selección observada. `Block/RequestBlocked`
  solo registran que no son necesarios (`Pro1:238–242`). No hay acuse de modo
  ni de freno. `disconnect:199–201` cierra/desasigna sin neutralizar por sí solo.

No es una parada transaccional: el envío de pendiente/ERG tiene Handler de
500 ms; `stopSession/onDestroy` no lo cancelan expresamente. El broadcast puede
fallar sin propagarse al llamador. No se copia esta posible carrera ni se
sustituye la secuencia actual por básica cero. Una futura evaluación separada
de `30...00` necesitará autorización, observación física y diagnóstico propio;
**no es la recuperación independiente**, pues también depende de ANT.

## 3. Reenvío de cinco segundos: lo probado y lo desconocido

El Timer se programa cada 1000 ms (`EntrenamientoFragment:747–748`,
`beans/Constants.java:20`). Durante sesión no pausada,
`checkRefreshDataRoller:602–616` incrementa el contador y al llegar a cinco
vuelve a llamar al cambio de pendiente o ERG. Cada cambio cancela el Handler
anterior, programa otro a 500 ms y reinicia el contador (`1031–1045,1058–1071`).
Por tanto hay **refresco normal del objetivo**, aproximadamente cada cinco
segundos, con temporización Android no exacta y coalescencia de cambios.

| Conclusión | Certeza |
|---|---|
| La app vuelve a solicitar la consigna durante la sesión | Confirmada por el código anterior. |
| Puede renovar/reafirmar el objetivo del receptor | Hipótesis compatible, sin observar el firmware. |
| Es obligatorio para mantener resistencia o evita un watchdog concreto | No demostrado; no se encuentra un contrato ni timeout del firmware. |
| El freno vuelve a cero al cesar envíos | No demostrado. Tampoco lo demuestra cerrar el canal. |

ANTLib especifica emisión broadcast del esclavo en una siguiente ventana TX,
sin confirmación de recepción/aplicación. No atribuye a ese dato una caducidad
de resistencia. Véanse las fuentes oficiales y límites del búfer en
[auditoria_buffer_ant_1_1_7.md](auditoria_buffer_ant_1_1_7.md).
No se añade ningún reenvío de resistencia al modo físico.

## 4. Recuperación independiente: evidencia y comprobación pendiente

El [manual original Classic/Pro, §2.7, reproducido en Manualzz](https://manualzz.com/doc/27236585/bkool-classic--pro-trainer-user-manual)
describe alimentación externa, fijación, piezas móviles y desconexión para
limpieza. **No especifica una liberación de emergencia del freno**, ni que
desenchufar o reiniciar borre la consigna. Se usa el texto original, no las FAQ
generadas por la web. El [manual del simulador, §15](https://static.keiser.com/media/BKOOL-Cylcling-Simulator-Manual.pdf?mtime=20171122122237)
describe dependencia de velocidad para obtener ciertas cargas, no una parada
de emergencia del firmware modelo 22.

**No se ha encontrado una liberación independiente documentada y garantizada.**
La propuesta siguiente es un procedimiento de salida del esfuerzo a comprobar,
no una afirmación de freno neutralizado:

1. Con montaje estable y carga baja ya validada, comprobar que se puede dejar
   de pedalear, mantener estabilidad y dejar que la rueda se detenga sin
   necesitar una orden de la app. Comprobar el desacoplamiento de los pedales
   de esta bicicleta; no presuponerlo por el tipo de rodillo.
2. Tener una persona de apoyo y acceso al interruptor externo de alimentación,
   sin acercarse a rueda/rodillo en movimiento. Si es necesario aislar la
   alimentación, hacerlo desde ese acceso; **aislamiento no significa freno
   liberado**. No manipular fijaciones ni desmontar bajo carga.
3. Con rueda inmóvil, evaluar el estado antes de cualquier reanudación. Si no
   se puede comprobar una salida estable del esfuerzo sin ANT, no hacer +2 %
   con ciclista; solicitar evaluación en banco/servicio técnico.

Registrar fecha, montaje/bicicleta, unidad 30064/112/5, responsable y observación
de esta comprobación. Actualmente **no consta realizada**; no se introduce
un checkbox que convierta una aceptación genérica en prueba mecánica.

## 5. Soporte y plan del único ensayo +2 % (no ejecutable todavía)

Ya existe `ExperimentalSlopesPage`, candidato offline +2 y diagnóstico JSON
de selección, API, enlace, parada y resistencia desconocida. Kotlin rechaza
+2/+3 incluso con sesión activada (`experimental_level_not_authorized`).
Se conserva esa barrera. El motivo histórico de rango no verificado se detalla
aquí: existe ruta de uso Pro1 en la app original, pero faltan recuperación y
respuesta física de esta unidad. No se habilita un nuevo transporte.

Especificación para una futura autorización revisada, **no instrucciones para
sortear el bloqueo actual**:

| Condición del ensayo aislado | Preparación / estado |
|---|---|
| Recuperación independiente documentada y comprobada | Pendiente; barrera previa obligatoria. |
| Apertura, ID seleccionado/configurado/recibido 30064/112/5; fabricante 67, modelo 22 de la conexión actual | Validaciones existentes; repetir en cada sesión. |
| Activación expresa nueva, sin envío al abrir | Existente para prueba actual; deberá extenderse específicamente al ensayo aislado. |
| Una sola solicitud +2 %, sin +3 ni refresco | Candidato offline disponible; autorización de transporte todavía bloqueada. |
| Ventana total propuesta ≤10 s desde activación, exposición +2 ≤3 s | Especificación futura, necesita temporizador dedicado probado; no sustituye los 30 s actuales. |
| LLANO y Detener siempre disponibles si enlace válido | Mantener protecciones actuales y cancelación de cola; nunca incremento automático. |
| No iniciar otro ensayo ni rearmar tras fallo | Nueva sesión y revisión explícita de registros, no reconexión automática. |

Después de cumplir esos requisitos y preparar el transporte aislado: verificar
primero la parada a carga conocida; activar expresamente el ensayo; una sola
solicitud +2 breve; solicitar llano, observar reducción y detener ya en llano.
Si no reduce, hay error o se pierde el enlace, abortar y aplicar la salida del
esfuerzo comprobada; no provocar deliberadamente cortes ANT bajo carga ni
insistir con nuevos incrementos. El límite temporal tampoco garantiza reducción.

Guardar JSON con tiempos, payloads de incremento/llano/parada, resultado de API,
TX/cierre si disponibles, identidad, telemetría y motivos de bloqueo/parada.
Añadir observación física por separado: API/TX no confirman respuesta mecánica.
Solo tras revisar retorno y recuperación de +2 se podrá plantear +3.

## 6. Validación de esta entrega

Se añaden pruebas **offline** en `RecoveryPreparationTest`: diferencia de bytes
básica/pendiente cero; ausencia de reenvíos automáticos durante 29 s; timeout a
30 s y conservación de la parada por pendiente cero; resistencia posterior
desconocida y rechazo de +2/+3. Se reutilizan las pruebas de fallos, pérdida de
enlace y cancelación de cola existentes. Ningún test abre una radio.

Resultados ejecutados el 2026-11-16:

- `flutter analyze`: sin incidencias.
- `flutter test`: 66 pruebas correctas.
- `./gradlew :app:testDebugUnitTest`: 77 pruebas, cero fallos/errores/omitidas.
  Gradle muestra avisos de deprecación de herramientas/plugins existentes.
- `git diff --check`: correcto. Rama `feature/control-ant`; APK original y
  fuentes JADX siguen excluidas de Git.

Solo se añaden este informe y dos pruebas de regresión; no se modifica la
implementación funcional existente. No hay cambios de codificación de
producción, firmware ni nueva APK. No se transmite al rodillo.

## 7. Condición concreta para avanzar

**Bloqueo físico actual:** no consta que, en el montaje real de esta bicicleta
y unidad, el usuario pueda cesar el esfuerzo y permanecer estable hasta que la
rueda se detenga **sin pulsar ningún control ni necesitar respuesta ANT**.
No falta conocer el paquete +2; tampoco se exige demostrar todo el rango del
firmware para plantear un ensayo acotado. Falta esa salida independiente.

**Comprobación siguiente:** en carga baja ya probada (0–1 %), con apoyo y montaje
estable, dejar de aportar esfuerzo sin solicitar llano/parada durante esa
observación; comprobar que los pedales se desacoplan, que puede mantenerse
estable y que la rueda se detiene. No apagar ANT ni provocar fallos bajo carga.
Si el timeout de 30 s o una orden de la aplicación interviene antes de completar
la observación, el resultado independiente queda inconcluso. No prolongar la
prueba intentando sostener más carga; valorar comprobación en banco. El corte
eléctrico accesible es aislamiento, no el criterio de éxito.

Registrar fecha, bicicleta/montaje, identidad, carga inicial, acciones y resultado.
**Criterio de paso:** salida estable del esfuerzo observada sin asistencia de
ANT/app y acceso preparado al aislamiento externo. **Criterio de rechazo:**
arrastre de pedales, inestabilidad, necesidad de una orden o resultado ambiguo.
La observación a carga baja no certifica +2 ni la liberación del freno; permite
revisar el ensayo siguiente sin exigir desconexiones con resistencia alta.

Después siguen pendientes **autorización específica de +2** e implementación
revisada del ensayo aislado: ≤10 s total, solicitud de retorno en ≤3 s desde el
envío +2, una sola orden +2, sin reenvíos. Son límites de solicitudes, no de
duración mecánica garantizada. La APK actual no admite +2: un registro favorable
no cambia sus límites automáticamente. +3 y continuo siguen bloqueados.

### Evaluación de básica cero y separación de acciones

**Formato y uso previsto en Pro1 justificados; eficacia física de parada no
verificada.** Básica cero puede ser candidata a una evaluación separada con
carga conocida, tras comprobar la salida independiente y autorizar esa prueba.
Hoy no sustituye la parada de producción ni se encadena con pendiente cero.
Faltaría observar cambio de comportamiento y reducción, y comprobar que no
reaparecen órdenes previas; ni API ni TX prueban por sí solos esos hechos.
No se exige básica cero como supuesto remedio para autorizar +2: la recuperación
previa debe funcionar sin ANT.

| Acción | Semántica actual |
|---|---|
| **LLANO 0 %** | Solicita pendiente cero (`33...20 4E FF`); continúa la sesión activada bajo sus límites. |
| **Detener control** | Bloquea nuevas órdenes, cancela la cola de la app, intenta una sola pendiente cero si procede y finaliza/libera recursos. Resistencia posterior desconocida. |

Esta revisión adicional solo modifica documentación. Se contrastaron otra vez
las llamadas originales y `ManualAntControl.stop`, sin cambios funcionales,
pantallas, paquetes, reenvíos, APK ni ejecución física. Los resultados de suites
anteriores permanecen en la sección 6; no se repiten por este cambio de texto.
