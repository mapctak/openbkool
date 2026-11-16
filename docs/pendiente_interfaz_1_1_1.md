# Pendiente solicitada y resultado de envío — OpenBkool 1.1.1

Corrección de presentación en `feature/control-ant`, versión **1.1.1+4**.
No cambia protocolo, transporte ANT, codificación, restricciones ni parada.

## Causa concreta de la discrepancia

La interfaz 1.1 usaba tres elementos diferentes:

| Elemento anterior | Fuente | Significado real |
|---|---|---|
| `0 %` entre los botones − y + | `const Text('0 %')` en `lib/training.dart` | Acción para **solicitar** 0 %. Su etiqueta nunca debía cambiar. No era un indicador. |
| Dato detallado «Última pendiente entregada a la API» | `manualControl.lastSubmittedPercent` | Última orden cuyo envío retornó de la API; puede diferir de la solicitud actual. |
| Resumen inferior «Pendiente solicitada» | Eventos `request` y `api_attempt` en `ManualOrderSummary` | Historial de solicitudes y de intentos, incluyendo antes el 0 % automático de parada. |

`submitted` (ahora denominado `stepBasePercent`) tomaba
`lastSubmittedPercent ?? 0` **solo para calcular** el siguiente paso de los
botones. No representaba una medición física de pendiente. El único `0 %` fijo
en la vista libre era la etiqueta del botón de vuelta a cero. La combinación
de una etiqueta aparentemente indicativa arriba y un estado variable debajo
producía la contradicción visual descrita.

Había además dos problemas reales de presentación:

1. El resumen esperaba que llegara un snapshot o retornara el MethodChannel;
   no mostraba inmediatamente la intención del usuario si la API tardaba.
2. El recorrido de `api_attempt` incluía el 0 % de parada como si fuera una
   selección manual nueva, pudiendo ocultar la última solicitud de la prueba.

Ninguno de esos datos confirmaba que el rodillo estuviera físicamente a 0 %.
La telemetría disponible no proporciona una confirmación de aplicación de esa
consigna. Un retorno correcto de API tampoco confirma entrega al rodillo.

## Presentación corregida

- Un único panel de pendiente en la zona principal, junto a potencia y antes
  de las métricas secundarias. Se elimina su duplicado inferior.
- «Pendiente solicitada» representa la última selección manual. Antes de una
  primera solicitud muestra `—`, sin inventar una pendiente física inicial.
- El botón central se denomina **«Solicitar 0 %»**, dejando claro que es una acción.
- El resultado de envío es otra línea: «Orden enviada a la API ANT: X %», error
  de API o ausencia de orden. Puede mostrar una orden anterior mientras la
  solicitud nueva está pendiente o fue rechazada; las fuentes no se fuerzan a
  coincidir.
- Se mantiene «Aplicación física no confirmada por el protocolo».
- La vista de diagnóstico detallado utiliza el mismo componente, conservando
  todos los eventos, valores crudos, JSON, CSV y datos de seguridad.

`lib/slope_presentation.dart` concentra la interpretación visual; ni codifica
tramas ni modifica snapshots de Kotlin. `SlopeUiIntent` es una intención efímera
local vinculada al UUID de sesión. Al pulsar −/0/+ se presenta inmediatamente
con «Solicitud pendiente de respuesta del controlador». El mismo callback
`manualAction('setManualSlope', percent: ..., expectedSessionId: ...)` se invoca
una sola vez, con los mismos valores que antes.

Al llegar eventos nuevos de esa sesión prevalecen los datos nativos. Si no se
registra la solicitud, se informa de falta de respuesta sin presentarla como
enviada. La intención no se guarda en preferencias, no autoriza control y se
ignora en una sesión con otro UUID. Los cálculos de los pasos siguen basados
en la última entrega retornada por API; no se recalcula ni cambia la política
de envío desde el valor visual pendiente.

## Parada y caducidad

El componente distingue la **última solicitud manual** del **intento de parada**:

```text
Última pendiente solicitada: 1,0 %
Orden de parada enviada a la API ANT: 0,0 %
Parada: solicitud de 0 % entregada a la API; aplicación física sin confirmar.
No se asume que el rodillo haya vuelto físicamente a 0 %.
```

Un `api_attempt` con `stopRequest=true` ya no sobrescribe la selección manual.
Se muestran el estado nativo («Deteniendo prueba», «Prueba finalizada» o
«Prueba caducada (30 s)») y `stopResult`, incluyendo error o imposibilidad de
solicitar 0 %. Si no hay historial de solicitud manual al terminar, el valor
se conserva desconocido, en lugar de inferirlo del 0 % de `lastSubmittedPercent`.

No se añaden envíos de parada desde Flutter ni se cambia el margen de cierre.
El watchdog, la solicitud condicional de 0 %, el cierre y los errores siguen
siendo responsabilidad del controlador Kotlin actual. La UI desactiva también
los botones al recibir `remainingMs <= 0`, incluso antes del siguiente tick
nativo; esto no amplía el plazo ni sustituye la validación del backend.

Continúan intactos: activación expresa por sesión, rango 0–1 %, pasos de 0,5,
30 segundos máximos, identificación exacta, frescura de datos, deduplicación,
tratamiento de errores y parada controlada. No se modifica firmware ni ERG.

## Pruebas

Las pruebas de interfaz cubren:

- 0 %, 0,5 % y 1 % en el único indicador principal.
- Actualización **antes** de completar una respuesta simulada de la API.
- Etiqueta inequívoca «Solicitar 0 %» y panel único por pantalla.
- Solicitud pendiente/rechazada frente a último envío retornado por API.
- Parada explícita: última solicitud manual y 0 % de parada separados.
- Caducidad a 30 s, controles desactivados y ausencia de envíos UI automáticos.
- Estado de cierre sin suponer retorno físico a cero.
- Intención de otra sesión ignorada y errores sin acuse inventado.
- Acceso al diagnóstico detallado y regresión del resto de la aplicación.

Las pruebas Kotlin existentes comprueban que el protocolo y las restricciones
siguen iguales. Todos los transportes de pruebas son simulados: no se abre una
radio ni se envían comandos reales durante esta corrección. La comprobación
física de la nueva presentación queda pendiente en Galaxy S20/S7.

## Resultados locales (2026-11-15)

- `flutter analyze`: sin incidencias.
- `flutter test`: 39 pruebas correctas; incluye actualización antes de respuesta,
  0/0,5/1, panel único, parada, caducidad y regresión de diagnósticos.
- `cd android` y `./gradlew :app:testDebugUnitTest`: 46 pruebas correctas.
- `flutter build apk --debug`: correcto. APK:
  `build/app/outputs/flutter-apk/openbkool-1.1.1-4-debug.apk`.
- `aapt`: versión 1.1.1, versionCode 4, etiqueta OpenBkool, minSdk 24.
- `git diff --check`: correcto. Se mantiene la rama `feature/control-ant`.
- Comparación con Git: sin cambios en Kotlin, codificación ANT, transporte,
  controlador Dart de comunicación ni guardas de activación. Solo cambia la
  presentación y se añade el bloqueo visual de controles al llegar el plazo
  que ya imponía el backend. La etiqueta más explícita se adapta al ancho
  disponible sin recortar controles en la prueba de 360×640.

Para verificar en el S20, finalizar antes la sesión anterior, instalar esta APK
y abrir Entrenamiento libre. Debe verse un solo panel de pendiente junto a la
potencia y un botón **Solicitar 0 %**. Tras habilitación expresa, el panel refleja
cada solicitud inmediatamente y distingue su resultado de API. Al detener o
caducar indica la última solicitud manual y la solicitud de parada por separado,
sin declarar retorno físico a cero. No se instala la APK ni se realizan envíos
reales durante esta validación local.
