# Control prolongado de carga baja — OpenBkool 1.3.2+17

## Decisión técnica (16 de noviembre de 2026)

Se habilita **una primera sesión física prolongada supervisada, exclusivamente
0 % y +0,5 %**, mediante `manual_low_load` en la pantalla existente
`ManualRidePage`. No caduca a los 30 segundos. Requiere activación y consentimiento
específico por sesión; abrir la pantalla o confirmar no transmite una pendiente.
El usuario elige cuándo finalizar y puede solicitar LLANO o DETENER CONTROL.
No se habilita por defecto un controlador: el perfil está seleccionado, pero
siempre hay que conectarse, verificar identidad y autorizar antes de ordenar.

Esto es una decisión experimental limitada, **no una demostración del orden RF
ni una certificación de parada mecánica**. Se apoya en la respuesta física
comunicada a carga baja, el ensayo 1.3.1 de refresco/parada, las protecciones
simuladas y la salida independiente del esfuerzo que el usuario ya comprobó en
su montaje: dejar de pedalear, permanecer estable y esperar a que pare la rueda.
Ese procedimiento limita la exposición al esfuerzo; no demuestra liberar el
freno ni restablecer físicamente una resistencia determinada. No se exige
provocar una desconexión bajo carga.

`manual_session` (−5 % a +15 %) y el antiguo `continuous` siguen bloqueados.
La codificación completa, en pasos de 0,5 %, permanece implementada y probada;
no se generaliza a todo el rango la validación física de algunos valores. El
control normal conserva +1 % y 30 s; los diagnósticos aislados y el ensayo
`refresh_trial_30s` conservan sus límites. No hay cambios de firmware, RF,
período, codificación de resistencia ni secuencia de parada de producción.

## Qué demuestra el JSON del Galaxy S20

Fuente: extracto aportado por el usuario de la sesión
`b284b966-5c8f-454d-aa77-f737ef1a8a55`, versión 1.3.1. Identidad seleccionada,
configurada, leída de ANT y recibida: **30064/112/5**, fabricante 67/modelo 22.
Las marcas siguientes son `android_elapsedRealtime_ms`, no horas RF:

| Hecho registrado | Tiempo monotónico (ms) |
|---|---:|
| Autorización sin enviar | 968289101 |
| Entrada/retorno API +0,5 % inicial | 968295997 / 968295999 |
| Entrada/retorno primer refresco | 968301550 / 968301551 |
| Entrada/retorno segundo refresco | 968306566 / 968306567 |
| Intención de parada / procesamiento serial | 968309468 / 968309470 |
| Entrada/retorno API pendiente cero | 968309472 / 968309473 |
| Solicitud/retorno API cierre | 968310985 / 968310988 |
| CHANNEL_CLOSED / estado detenido | 968311407 / 968311421 |

Entre entradas de envío hay **5553 y 5016 ms**. El cero retorna 5 ms después de
la invalidación; el cierre se pide 1512 ms después del retorno de cero, y
CHANNEL_CLOSED llega 1939 ms después de la intención de parada. No hay nuevas
llamadas de pendiente después del cero en este registro; cola de aplicación
vacía, objetivos invalidados y recursos liberados. Esto demuestra la secuencia
**de aplicación/API en ese ensayo**, no el contenido ni orden de la radio.
Los cuatro TX no identifican payload. El TX posterior al cero no certifica
que fuera cero, ni excluye que fuera un contenido anterior.

### Página recibida 0x11

Los bytes completos sí están disponibles en el JSON:

| UTC | Payload recibido del rodillo |
|---|---|
| 16:43:48.971 | `11 FF FF FF 20 4E 00 34` |
| 16:43:58.971 | `11 FF FF FF 52 4E 00 34` |
| 16:44:03.969 | `11 FF FF FF 52 4E 00 34` |

Los bytes **4–5** (índices desde cero) pasan de 0x4E20=20000 a 0x4E52=20050.
Coinciden numéricamente con el campo de la orden 0x33, que está en bytes **5–6**:
`(pendiente + 200) × 100`. La coincidencia temporal respalda la **hipótesis de
un ajuste reportado o eco de consigna**, pero no identifica su semántica exacta,
ni constituye ACK de un comando ni medición de resistencia aplicada. No existe
una página 0x11 recibida después del cero de parada en este extracto; no se puede
asegurar que volvió a 20000. Durante el cierre la ruta de recepción de la sesión
ya finalizada tampoco ofrece una observación completa del tráfico externo.

Evidencias del código descompilado local (no redistribuido):

- `research/jadx/sources/com/bkool/sensors/tech/ant/devices/TrainerBkoolPro1.java:59–169`:
  el receptor trata 0x10, 0x19 y 0x50; no interpreta 0x11 como pendiente aplicada.
- El mismo archivo, líneas 213–217: fórmula y bytes de TrackResist 0x33;
  líneas 223–224: BasicResistance 0x30. Son modos distintos.
- `TrainerBkoolPro2.java`: tampoco aporta una interpretación de 0x11.
- `TrainerFEC.java:59–61`: callback `onNewGeneralSettings` vacío.
- El [contrato oficial ANT+ General Settings](https://thisisant.developer.garmin.com/assets/APIassets/Android_ANT_plus_plugins_API/com/dsi/ant/plugins/antplus/pcc/AntPlusFitnessEquipmentPcc.IpcDefines.html)
  describe una inclinación opcional entre −100 y +100 %, resolución 0,01 %.
  No justifica trasladar automáticamente el offset propietario +200 al RX 0x11
  del Pro1: 20050 en centésimas sería 200,50 %, fuera de ese intervalo estándar.

Por ello se añade únicamente `telemetry.page11Observation`: payload íntegro,
`rawWordAtBytes4And5`, bytes, edad, marca monotónica y semántica no verificada.
`commandAcknowledgement=false` y `mechanicalConfirmation=false`. No se publica
un porcentaje aplicado inferido. No afecta al indicador de pendiente ordenada,
a la frescura de potencia/velocidad ni a las condiciones de habilitación.
La fixture `s20_refresh_1_3_1_page11.csv` conserva estas tres líneas reales;
no pretende ser el CSV completo del ensayo.

## Reenvío, carreras y parada

El nuevo perfil usa **el mismo trabajador serial y el mismo motor ya auditado**:
no se incorpora otro temporizador de órdenes. El heartbeat consulta el objetivo
vigente aceptado por la API cada ~5 s; antes de la primera orden no hay refrescos.
Un retraso produce como máximo una llamada, sin recuperar ticks acumulados.
Un cambio aceptado sustituye el objetivo y reinicia el intervalo. Se mantiene
el limitador de cambios de 1 s. No se pretende que el refresco sea un watchdog.

DETENER invalida atómicamente objetivos y cancela cola/heartbeat antes de esperar
al trabajador. Una IPC ya iniciada puede terminar: no se puede retirar ni se
confunde con una orden cancelada antes de entrar al SDK. Después se intenta una
sola **pendiente cero** si el enlace sigue abierto e identificado, se conserva
el drenaje de 1,5 s y se cierra/libera el canal. Un error de cero/cierre queda
visible; la resistencia física posterior sigue desconocida. No se añade
`30 FF FF FF FF FF FF 00` ni se cambia de modo de resistencia al detener.

Identificación completa actual, supervisión de señal/telemetría obsoleta y canal,
segundo plano, salida de pantalla, bloqueo tras comunicación incierta y activación
por nueva sesión siguen vigentes. Una reconexión o regreso a primer plano no
reanuda control ni pendiente. Si Android mata el proceso sin callback no se
puede garantizar enviar cero; no se promete lo contrario. LLANO solicita cero
y mantiene la sesión; DETENER la finaliza. Ambos permanecen en la barra inferior.

Las pruebas cubren parada antes/durante IPC de refresco, refresco retrasado,
objetivo sustituido, canal cerrado durante envío, fallo de cero, pérdida de
señal, segundo plano, ausencia de reactivación y cancelación de órdenes. Los
escenarios de carrera existentes siguen ejecutándose sobre el motor compartido;
se añaden consentimiento/rango nativos del perfil, dos horas simuladas y parada,
fallos/pérdida de enlace y una sesión Flutter con consentimiento, órdenes,
indicador API, tiempo superior a 30 s y prohibición de escalar perfil activo.
No se han enviado comandos físicos durante estas pruebas.

## Primera sesión y comprobación pendiente de radio

1. Usar el mismo montaje y recuperación independiente ya comprobados, carga
   baja y acceso inmediato al teléfono. No tener otra app controlando el rodillo.
2. Inicio → Control manual 1.3 → perfil **Sesión supervisada 0/+0,5 %**.
   Conectar y esperar verificación actual 30064/112/5, fabricante 67/modelo 22.
3. Leer y aceptar **Iniciar sesión supervisada**. Elegir +0,5 % expresamente.
   Comprobar pendiente ordenada, enlace y tiempo; continuar más de 30 s según
   tolerancia, sin elevar carga. Probar LLANO y luego DETENER; observar por
   separado la reducción física y exportar JSON/CSV. No hay parada fija a 30 s.
4. Si no baja o se pierde enlace, dejar de aportar esfuerzo y esperar estable
   a que pare la rueda. No insistir con incrementos ni confiar en un corte
   eléctrico para liberar el freno. Exportar el fallo y no reactivar esa sesión.

La incertidumbre concreta pendiente es **si el último cero fue emitido por RF
antes del cierre y si hubo objetivos anteriores transmitidos posteriormente**.
La resuelve una captura independiente capaz de observar la dirección
controlador→rodillo, no solo emisiones de telemetría. Registrar payloads 0x33,
identidad/dirección, tiempos sincronizados y al menos 15 s tras el cierre;
contrastar con `apiEnteredAtMs`, retorno, invalidación y CHANNEL_CLOSED. El
anclaje UTC/monotónico requiere calibración con el reloj del receptor. Debe
verse cero antes de cierre y ningún objetivo antiguo después; repetir parada,
cambio de objetivo próximo al refresco y segundo plano a carga baja. Una captura
favorable documenta esos casos, no crea una garantía general del SDK/firmware.
La respuesta mecánica debe anotarse independientemente de esa captura.

No se exige este instrumental para el experimento supervisado de carga baja
que se habilita aquí, aceptando expresamente su incertidumbre residual. **Sí
sigue faltando para justificar el desbloqueo general** la revisión de esos casos
de radio/parada y de la sesión prolongada física. No se desbloquea todo el rango
por recibir un eco, un TX, un retorno API o por completar esta sesión.

## Validación de entrega

`flutter analyze`: sin incidencias. `flutter test`: **83 pruebas correctas**.
`./gradlew :app:testDebugUnitTest`: **111 pruebas correctas**, sin fallos ni
omisiones. Canales simulados; se conservan pruebas del rango original, BLE,
telemetría, CSV, navegación y diagnósticos. `flutter build apk --debug`: correcta. Se mantienen avisos previos de Gradle/Java.

APK: `build/app/outputs/flutter-apk/openbkool-1.3.2-17-debug.apk`.
