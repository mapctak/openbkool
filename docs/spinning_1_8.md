# Spinning en OpenBkool 1.8.0+32

[Vista previa del selector renderizado en Flutter](spinning-selector.png)

## Catálogo

Cada fila identifica seis programas de distinta dificultad. Para cada duración `D` y nivel `N`, el ID estable es `spinning-v1-D-N` y el nombre es «Etiqueta del nivel · D min». Cada celda indica el número de pares esfuerzo-recuperación del bloque principal. La duración seleccionada incluye calentamiento físico y vuelta a la calma.

| Duración | Nivel 1 · Muy suave | Nivel 2 · Suave | Nivel 3 · Moderado | Nivel 4 · Intenso | Nivel 5 · Exigente | Nivel 6 · Muy exigente |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 min | 2 | 3 | 3 | 4 | 4 | 5 |
| 15 min | 4 | 5 | 6 | 7 | 7 | 8 |
| 20 min | 5 | 6 | 8 | 10 | 10 | 11 |
| 30 min | 8 | 10 | 12 | 15 | 15 | 17 |
| 45 min | 12 | 15 | 18 | 22 | 23 | 26 |

| Nivel | Pico | Proporción de esfuerzo | Recuperación |
| ---: | ---: | ---: | ---: |
| 1 | +2 % | 40 % | +0,5 % |
| 2 | +3 % | 45 % | +0,5 % |
| 3 | +4 % | 50 % | +0,5 % |
| 4 | +5,5 % | 55 % | +1,5 % |
| 5 | +7 % | 60 % | +1,5 % |
| 6 | +8 % | 65 % | +1,5 % |

El calentamiento físico dura el mayor valor entre 90 segundos y seis segundos por minuto de programa. Sus dos mitades se ejecutan a +0,5 % y +1 %. La vuelta a la calma dura el mayor valor entre 60 segundos y cuatro segundos por minuto, con dos mitades a +0,5 % y 0 %. El bloque principal reparte los segundos restantes entre los pares de la tabla. El esfuerzo se redondea hacia abajo al segundo y la recuperación ocupa el resto del par. Los esfuerzos previos al último repiten pico menos 1, 0,5 y 0 puntos. El último alcanza siempre el pico. La dificultad describe la pendiente solicitada y la estructura temporal.

## Una sesión y un controlador

El servicio Android acepta una sola petición de arranque o transferencia a la vez. El trabajador serial incorpora el programa del catálogo al crear el UUID y rechaza iniciar otra modalidad mientras la sesión posee el canal. Inicio reconstruye el estado del servicio y usa ese mismo UUID al volver o al detener. El botón de Inicio, el del cuadro y la notificación convergen en la parada nativa. El resumen final de Inicio permite copiar los informes del último entrenamiento observado.

La selección y la vista previa leen el catálogo nativo. **INICIAR SPINNING** solicita una sesión. El calentamiento ANT precede al cronómetro y a la primera consigna. El trabajador activa el controlador cuando el canal, la identidad, la compatibilidad, la telemetría y el servicio cumplen sus comprobaciones. El programa y el cronómetro empiezan con esa activación. El aviso visual de cinco segundos se muestra en el cuadro de entrenamiento.

El planificador toma el tiempo monotónico transcurrido y busca el intervalo vigente. Solicita su pendiente por la cola del controlador existente, omite pendientes consecutivas iguales y descarta los intervalos saltados tras un retraso. El reloj y el trabajador pertenecen al servicio Android. Al completar la duración, al detener o al perder el enlace, se cancela la programación y se ejecuta la parada conservadora. Una recuperación de señal requiere un nuevo inicio explícito para volver a transmitir.

El JSON añade modalidad, catálogo del programa, intervalos visitados, tiempo efectivo y motivo de finalización. Los intervalos visitados representan decisiones del planificador. Las solicitudes y los resultados de la API quedan registrados en el CSV y JSON existentes. La confirmación mecánica sigue siendo desconocida.

## Verificación

| Comando | Resultado |
| --- | --- |
| `flutter analyze` | Sin incidencias |
| `flutter test` | 41 pruebas correctas |
| `./gradlew :app:testDebugUnitTest --no-daemon` | 106 pruebas correctas |
| `flutter build apk --debug` | APK de depuración |

Las pruebas cubren la estructura de los 30 programas, el salto al intervalo vigente, la ausencia de consignas redundantes, las barreras del controlador, la reentrada y la parada asociada al UUID. ADB no detectó dispositivos conectados. Queda pendiente repetir en el Galaxy S20 con el rodillo los cambios de intervalo con pantalla bloqueada, las pausas del proceso, la parada desde la notificación y el corte real de señal durante Spinning.
