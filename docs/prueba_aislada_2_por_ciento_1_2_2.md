# Prueba aislada +2 % — OpenBkool 1.2.2+13

> Histórico: +2 fue probado posteriormente por el usuario. Estado vigente de
> +3 habilitado y +4 bloqueado:
> [pendientes_experimentales_1_2_3.md](pendientes_experimentales_1_2_3.md).

Rama `feature/control-ant`. +2 % disponible exclusivamente desde Ajustes →
Diagnósticos avanzados → Pendientes experimentales, con doble confirmación.
Entrenamiento ordinario conserva máximo +1 %. +3 % y continuo siguen bloqueados.

## Condición de recuperación cumplida y alcance

En esta conversación el usuario confirmó expresamente que, en su bicicleta
fijada al Smart Pro v1 de fricción, comprobó con carga baja ya validada que puede
dejar de pedalear, permanecer estable y dejar detenerse la rueda sin intervención
de una orden ANT ni del timeout. Esta es **observación física comunicada por el
usuario**, no una medición realizada por OpenBkool ni una garantía de liberación
del freno. El rodillo opone resistencia; no impulsa la bicicleta.

Esa comprobación satisface la condición previa de salida del esfuerzo descrita
en [recuperacion_prueba_2_por_ciento.md](recuperacion_prueba_2_por_ciento.md).
Si cambia el montaje, hay arrastre de pedales, inestabilidad o duda sobre esta
salida, no autorizar el ensayo; comprobar primero la recuperación en carga baja.
La aplicación exige confirmar otra vez esta condición y el consentimiento por
sesión. No guarda una autorización reutilizable ni infiere conexión de un ID
recordado. No exige provocar desconexiones ANT bajo carga.

## Implementación y límites

- Modo nativo `isolated_two_percent`: máximo **30 s desde la activación**, como
  la prueba actual. No se alarga al cambiar de pendiente.
- Requiere `confirmed=true` y `experimentalConfirmed=true`; el modo ordinario
  rechaza +2 incluso si llega el indicador adicional. Activar no transmite.
- Conserva identidad seleccionada/configurada/recibida 30064/112/5, fabricante
  67 y modelo 22 de la conexión actual, canal específico válido y telemetría
  fresca; conserva bloqueo ante pérdidas, segundo plano y cancelación de cola.
- Permite 0/0,5/1 y una única solicitud +2 por sesión; rechaza 1,5, 2,5, +3 y
  superiores. Se consume el permiso al intentar la API, incluso si falla. Un
  rechazo previo por tasa/enlace no ejecuta esa API. No hay reenvíos periódicos.
- El botón + pasa de 1 a 2 en este modo (no inventa el nivel 1,5); − vuelve de
  2 a 1. Tras intentar +2 quedan bloqueados nuevos aumentos en esa pantalla;
  siguen disponibles disminución, LLANO y Detener según el estado del enlace.
- LLANO solicita `33 FF FF FF FF 20 4E FF` y conserva la sesión. Detener cancela
  nuevas órdenes, intenta una pendiente cero si es admisible y cierra mediante
  la secuencia existente. **No se añade básica cero** `30 ... 00`.
- +2 conserva la codificación original `33 FF FF FF FF E8 4E FF`. Se reutiliza
  el codificador contrastado offline; `encodeManualSlope` sigue limitado a +1.
- JSON conserva pendiente solicitada, última API aceptada, payload, errores,
  modo/consentimiento adicional, permiso +2 consumido y motivo/resultado de
  parada. API aceptada/TX no confirman recepción ni resistencia física.

## Instrucciones de la primera prueba física

1. Mantener el montaje donde se comprobó la recuperación, con apoyo y acceso
   al aislamiento externo sin acercarse a partes móviles. No considerar un
   corte eléctrico garantía de resistencia cero ni tocar fijaciones bajo carga.
2. Abrir Pendientes experimentales, conectar 30064/112/5 y esperar a identificación
   completa y enlace disponible. Seleccionar **+2,0 % · experimental**.
3. Pulsar Habilitar prueba de este nivel; confirmar preparación y después
   recuperación y autorización específica de +2. Cancelar si no se cumplen
   las condiciones. No se envía ningún objetivo al confirmar.
4. Con pedaleo suave, usar + para 0,5, 1 y finalmente 2; respetar aproximadamente
   un segundo entre pulsaciones (limitador existente). Una única solicitud +2.
5. Tras unos **3 s** en +2, pulsar **LLANO 0 %**, observar si disminuye y pulsar
   **Detener control**. Los 3 s son instrucción supervisada, no un temporizador
   nuevo. El máximo automático total sigue siendo 30 s. No esperar al timeout
   como método de demostrar reducción.
6. Si no disminuye, falla un envío o se pierde enlace: detener la prueba,
   dejar de aportar esfuerzo y esperar estable a la rueda detenida mediante la
   recuperación ya comprobada. No insistir con incrementos ni provocar cortes
   ANT. Aislar externamente si procede, sin presuponer liberación; no reanudar
   hasta comprobar el estado con rueda inmóvil.
7. Exportar JSON y CSV existentes; anotar por separado sensación de aumento,
   reducción tras LLANO, resultado de Detener y cualquier anomalía. No repetir
   +2 sin revisar este primer registro. +3 no queda autorizado por esta prueba.

## Verificación

Pruebas con callbacks/canales simulados, sin comandos reales. Cubren doble
consentimiento, cancelación del diálogo, ausencia de envío al activar, paso
1→2, identidad/modelo/enlace, permiso único, límites, fallo API y parada a 30 s.
Se conservan suites existentes de segundo plano, desconexión, cola y sincronía.
Resultados: `flutter analyze` sin incidencias, 67 pruebas Flutter y 81 Kotlin
correctas. Tras adaptar los diálogos desplazables, se repitieron las cinco
pruebas de la pantalla experimental, incluida vista 360×640, y el análisis:
correctos. `flutter build apk --debug` completado; Gradle muestra avisos de
deprecación existentes, sin errores. `git diff --check` correcto.

APK: `build/app/outputs/flutter-apk/openbkool-1.2.2-13-debug.apk`.

La respuesta mecánica de +2, su reducción y la parada con este nivel quedan
pendientes de esta primera prueba física. No se certifica una resistencia segura
por el mero retorno de API, cero solicitado o cierre del canal.
