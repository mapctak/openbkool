# Conexión ANT y elevación virtual en OpenBkool 1.7.5+29

## Propiedad de la conexión

Android mantiene un servicio en primer plano con notificación y un único
trabajador serial que posee el canal ANT. El coordinador de radio sigue
impidiendo que una búsqueda u otro diagnóstico abra un segundo canal en
paralelo. El estado publicado distingue desconectado, conectando, conectado en
solo lectura, entrenamiento conectado, parada y error.

**Comprobar conexión** abre el canal y verifica el ID ANT completo, fabricante
67 y modelo 22 con señal reciente. Inicio muestra conectado y ofrece
**Desconectar**. La comprobación carece de UUID de entrenamiento, temporizador y
consignas. Inicio, Ajustes, el bloqueo de pantalla y los cambios temporales de
aplicación comparten el enlace mientras Android mantenga el servicio. En solo
lectura, quitar la tarea o permanecer 15 minutos en segundo plano libera los
recursos. La notificación también permite cancelar o desconectar. El servicio
usa `START_NOT_STICKY` y Flutter reconstruye el estado a partir del servicio
vivo.

Al entrar en Entrenamiento libre, el trabajador valida el destino y la
vigencia de la identificación antes de reutilizar el canal. Si aún está
identificando el mismo rodillo, el entrenamiento puede usar ese canal y
esperar en calentamiento. Si el enlace preparado quedó obsoleto o corresponde
a otro rodillo, la operación explícita cierra el anterior y abre el requerido
solo después de liberar los recursos. Una pérdida real de señal invalida el
enlace aunque reaparezcan paquetes. La recuperación del control requiere una
nueva sesión. Los umbrales de supervisión ANT y las 41 consignas se conservan.

Cada entrenamiento crea su propio UUID, controlador, cola, cronómetro, contador
de distancia de sesión, perfil y CSV. El controlador puede armarse en cuanto
dispone de identidad y métricas recientes. La activación deja la transmisión
pendiente de una acción del usuario. El aviso de comienzo dura cinco segundos.

## Parada del entrenamiento

**Detener entrenamiento** y la acción equivalente de la notificación se
aplican al UUID de la sesión. Cancelar una comprobación se aplica al enlace de
solo lectura. Una acción de una sesión anterior se ignora si el UUID difiere.

La parada invalida la cola antes de procesar el cierre en el trabajador y
cancela el refresco de resistencia. El controlador conserva su intento único
de 0 % y el drenaje de 1,5 s cuando corresponden. El cronómetro y el perfil se
cierran con la sesión. El CSV y el JSON final quedan disponibles en el menú de
exportación. El servicio conserva en memoria hasta cuatro informes finalizados
para consultas por UUID y el CSV queda en el almacenamiento privado de la
aplicación.

El canal queda en solo lectura cuando la identificación y la señal siguen
vigentes y el controlador puede acreditar que ninguna consigna llegó a la API
ANT. Si hubo una consigna, un fallo de transmisión o una pérdida del enlace, se
cierra el canal. La API ANT carece de confirmación de vaciado del búfer y de
confirmación mecánica de la parada. [Auditoría del búfer ANT](auditoria_buffer_ant_1_1_7.md)

## Perfil virtual

Durante una interrupción se mantiene visible el último punto válido. Cuando
vuelve a haber distancia válida, el gráfico conserva la altura en el avance
incierto y reanuda la integración en los intervalos con datos válidos. El
identificador de segmento conserva esa discontinuidad de datos. La vista usa
un único trazo y un único relleno a lo largo del recorrido. El último punto
válido determina el extremo derecho y la escala horizontal. El historial
acotado conserva origen, último punto y extremos de elevación en recorridos
largos. Las mediciones ANT se registran por separado con sus valores originales.

## Verificación

| Comando | Resultado |
| --- | --- |
| `flutter analyze` | Sin incidencias |
| `flutter test` | 37 pruebas correctas |
| `./gradlew --no-daemon :app:testDebugUnitTest` | 101 pruebas correctas |
| `flutter build apk --debug` | `build/app/outputs/flutter-apk/app-debug.apk` |

La suite nativa se completó con un daemon nuevo después de que el daemon
reutilizado fallara al lanzar el proceso Flutter. ADB no mostró dispositivos
conectados.

Las pruebas automatizadas usan telemetría y llamadas ANT simuladas. Queda por
validar con un Bkool Smart Pro v1 y Android reales el bloqueo de pantalla, el
cambio de aplicación, el corte de señal durante control y la parada desde la
notificación. La resistencia física tras la solicitud de 0 % queda sin
confirmar.
