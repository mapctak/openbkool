# Cuadro de entrenamiento libre en OpenBkool 1.7

El cuadro reúne el cronómetro, el selector de pendiente, velocidad, potencia, cadencia, distancia y perfil virtual. Las agujas se interpolan durante 260 ms y las cifras reflejan la última lectura válida. Al faltar una lectura, el instrumento muestra un guion y oculta la aguja. Los botones recorren las 41 consignas entre −5 % y +15 % en pasos de 0,5 %. El menú de la pantalla da acceso a los informes y el botón inferior usa la parada nativa.

## Calentamiento automático

Al abrir Entrenamiento libre, el único servicio de entrenamiento abre el canal dedicado para la identidad exacta del rodillo guardado. Ajustes permite cambiar esa selección. Durante la búsqueda y la identificación, el cuadro muestra el estado y presenta la telemetría que entrega el servicio. Durante la preparación se muestra el tiempo de calentamiento.

El motor verifica el canal abierto, la identidad coincidente, fabricante 67, modelo 22, señal y telemetría recientes y el estado del servicio. Flutter solicita automáticamente la activación para el UUID actual. Al confirmarse el estado activo y habilitado, el cuadro muestra «¡COMIENZA EL ENTRENAMIENTO!» durante cinco segundos y el cronómetro de entrenamiento parte de cero. La activación no envía una consigna. Si la sesión termina sin transmitir una pendiente, el cierre tampoco solicita 0 %. Después de una consigna transmitida, se conserva la parada conservadora existente.

El JSON conserva `telemetry.elapsedMs` para el tiempo total, `warmupElapsedMs` para la preparación y `trainingElapsedMs` para el tiempo desde la activación hasta la parada. El CSV conserva su estructura y registra la transición en la fila `manual:enabled`, cuyo `elapsed_ms` indica el tiempo transcurrido desde el inicio de sesión. La distancia y el perfil incluyen los avances válidos del calentamiento, con una referencia virtual de 0 %. El servicio puede seguir buscando en segundo plano una vez activo.


## Perfil de elevación virtual

El origen es 0 km y 0 m. OpenBkool usa la distancia ANT acumulada como aproximación de la distancia horizontal. Cada incremento válido aporta `deltaDistancia × pendiente / 100` metros a la elevación. Por ejemplo, después de 500 m al 0 %, 200 m al +5 % y 100 m al −2 %, el perfil termina en 800 m y 8 m de elevación virtual.

La sesión Android guarda el perfil bajo el mismo UUID. En el hilo de sesión, cada intervalo se atribuye a la última consigna manual que retornó correctamente de la API al procesar la muestra. Se toma 0 % como referencia inicial. El tramo que cruza una transición se atribuye con esa misma regla, sin estimar el instante de respuesta mecánica. Una selección pendiente, descartada o rechazada carece de efecto sobre la gráfica y las selecciones nuevas nunca recalculan tramos anteriores. La aceptación de la API solo representa una referencia para la simulación.

Al faltar distancia válida, el perfil omite ese avance y conserva la cota acumulada al reanudar. También ignora duplicados y espera a superar la última distancia graficada después de un retroceso del contador. La parada o un error de API suspenden la integración. La sesión conserva hasta 512 puntos y reduce el historial por grupos, reteniendo extremos, primer y último punto de cada grupo. El gráfico conserva el origen y ajusta el eje horizontal hasta el último punto válido. Los cambios de segmento se unen con un trazo discontinuo entre puntos válidos de distancia creciente. El tramo de unión carece de sombreado y no añade muestras al registro. El informe JSON contiene `virtualElevation` con tripletas de distancia en metros, elevación en metros e identificador de segmento, que permite marcar los cortes por falta de datos. El CSV mantiene su estructura.

Las capturas usan datos simulados. Queda pendiente comprobar en el Galaxy S20 la legibilidad y fluidez durante telemetría real, la búsqueda con la pantalla bloqueada, la recuperación de la sesión y del perfil al volver, y el informe final después de detener desde la notificación. La validación física de la versión anterior cubrió las pendientes positivas hasta +8 %. Las negativas y las superiores a +8 % siguen siendo experimentales.


## Comprobación desde Inicio

«Comprobar conexión» utiliza la identidad guardada y ocupa el mismo servicio y la misma reserva de radio que el entrenamiento. Verifica el canal, la identidad exacta, la señal y fabricante 67/modelo 22 en una operación cancelable. Si la identificación no termina, la búsqueda tiene un límite adicional de 45 segundos desde que abre el canal. El resultado se muestra tras cerrar la radio. El modo de comprobación bloquea las órdenes de control y no crea un CSV de entrenamiento.

El servicio liga el canal al ciclo de vida y al identificador de la operación cuando lo abre. Mantenerlo preparado para otra sesión exigiría transferir ese estado y sus garantías de cierre. Por eso la comprobación termina y Entrenamiento libre abre una sesión propia.
