# Ensayo +3 % y preparación bloqueada de +4 % — 1.2.3+14

Rama `feature/control-ant`. **+3 % habilitado para una prueba física aislada,
con confirmación por sesión. +4 % permanece bloqueado en interfaz y Kotlin.**
Entrenamiento libre/control ordinario mantienen máximo +1 %; continuo bloqueado.

## Evidencia y codificación

El usuario comunica que en 1.2.2+13 observó aumento de resistencia al pasar de
+1 a +2 y reducción al solicitar LLANO. El JSON registró aceptación de +2 por
la API y la parada terminó a nivel de aplicación. Es observación física del
usuario, no confirmación de recepción/aplicación del protocolo. Se conserva
la recuperación independiente comprobada en este montaje y documentada en
[prueba_aislada_2_por_ciento_1_2_2.md](prueba_aislada_2_por_ciento_1_2_2.md).

Fórmula original Pro1: `int((percentFloat + 200f) * 100f)`, LE16 en bytes 5–6
de página 0x33. Referencia: `research/jadx/sources/com/bkool/sensors/tech/ant/devices/TrainerBkoolPro1.java:213–217`.
La ruta original admite estos objetivos en su UI −5..+15, paso 0,5; véase
[limites_smart_pro_v1.md](limites_smart_pro_v1.md). No certifica carga calibrada
ni máximo físico del firmware.

| Objetivo | Entero | LE16 | Payload |
|---|---|---|---|
| +3 % | 20300 | 4C 4F | `33 FF FF FF FF 4C 4F FF` |
| +4 % (solo offline) | 20400 | B0 4F | `33 FF FF FF FF B0 4F FF` |

Se amplía el codificador **offline** hasta 4, contrastado con Float original y
16 bits. El codificador manual normal sigue limitado a 0/0,5/1.

## Autorización y límites

- `isolated_three_percent` requiere activación expresa y confirmación adicional
  de recuperación y autorización de +3. Activar no transmite.
- Admite 0/0,5/1 y una única solicitud +3. El intento de API consume el permiso
  incluso si falla. Un rechazo anterior por frecuencia/enlace no lo consume.
  No se permiten +2 ni +4 en esa sesión; +2 conserva su propio modo aislado.
- No se cambia de modo con control activo ni se rearma una sesión detenida.
  Máximo 30 s desde activación, sin renovar plazo con cada orden. Limitador de
  1 s y deduplicación conservados; ningún refresco automático.
- Identidad seleccionada/configurada/recibida 30064/112/5, fabricante 67/modelo
  22 de esta conexión, canal dedicado y telemetría fresca obligatorios.
- LLANO, Detener, cancelación de cola, errores, desconexión y segundo plano
  conservan sus protecciones. La parada sigue intentando pendiente cero si
  procede antes de cerrar; no se añade básica cero ni se modifica firmware.

El selector +4 muestra candidato y motivo, pero no permite activar ni enviar.
**No existe modo nativo `isolated_four_percent`** ni aprobación guardada que lo
habilite. API +3 aceptada, telemetría o reinicio no desbloquean +4. Tras observar
y revisar respuesta física/retorno/parada de +3, se necesita una autorización
posterior explícita y revisar la habilitación de +4. Esta APK no transmite +4.

## Procedimiento en Galaxy S20

1. Mantener el montaje donde se verificó la salida independiente del esfuerzo.
   Si cambió o no se puede dejar de pedalear y permanecer estable hasta detener
   la rueda sin ANT/app, no autorizar. Preparar apoyo y acceso al aislamiento
   externo; cortar alimentación no garantiza liberar el freno.
2. Ajustes → Diagnósticos avanzados → Pendientes experimentales. Conectar,
   esperar identificación completa y seleccionar **+3,0 % · experimental**.
3. Confirmar preparación y después recuperación y autorización de un único +3.
   No se transmite al confirmar; entonces empieza el plazo de 30 s.
4. Pedaleo suave: + solicita 0,5, 1 y finalmente 3, dejando al menos un segundo
   entre pulsaciones. No pasa por +2 ni niveles 1,5/2,5. Tras intentar +3 quedan
   bloqueados nuevos aumentos en esa pantalla; siguen disminución y parada.
5. Tras unos **3 s**, solicitar **LLANO 0 %**, observar reducción y pulsar
   **Detener control**. Los 3 s son instrucción supervisada, no otro temporizador.
   El timeout total de 30 s no garantiza duración mecánica ni resistencia cero.
6. Si no disminuye, hay error o pérdida de enlace, detener el ensayo, dejar de
   aportar esfuerzo y esperar estable a rueda inmóvil usando la recuperación
   comprobada. No insistir con incrementos, provocar cortes ANT bajo carga ni
   manipular partes móviles/fijaciones. Comprobar estado antes de reanudar.
7. Exportar JSON y CSV existentes; anotar aparte aumento percibido, reducción
   tras LLANO y parada. Revisar el primer registro antes de repetir. No autoriza +4.

Se muestran pendiente seleccionada/ordenada, tiempo, resultado API, enlace,
diagnóstico de canal y parada. JSON añade objetivo aislado/permiso consumido y
conserva solicitudes, payloads, retornos, errores y motivo de parada.
**Resistencia física no confirmada por ANT**, incluido después de solicitar cero.

## Validación

Canales simulados: consentimiento, modo ordinario, permiso único, límites,
bloqueo de +4 aun tras aceptar +3, modo inmutable, tasa, timeout, identidad,
enlace, fallo API, parada manual, pantalla/segundo plano y no reactivación.
Interfaz: cancelación, confirmación, paso 1→3, bloqueo tras intento y diálogo
adaptable 360×640. Tests existentes de cola y sincronía conservados.
Sin comandos reales durante las pruebas automatizadas.

Resultados: `flutter analyze` limpio; **68 pruebas Flutter y 87 Kotlin correctas**.
Tras reforzar el test de no desbloqueo de +4 después de API +3 aceptada, se
repitieron las seis pruebas de la pantalla experimental: correctas.
`flutter build apk --debug` completado. Gradle muestra avisos existentes de
deprecación/acceso nativo, sin errores. `git diff --check` correcto.

APK: `build/app/outputs/flutter-apk/openbkool-1.2.3-14-debug.apk`.
Sin transmisiones reales ni cambios en `main`. La respuesta física de +3 y
cualquier validación de +4 siguen pendientes; no se afirma haberlas probado.
