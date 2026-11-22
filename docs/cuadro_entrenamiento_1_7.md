# Cuadro de entrenamiento libre en OpenBkool 1.7

El cuadro reúne el cronómetro, el selector de pendiente, velocidad, potencia, cadencia, distancia y perfil virtual. Las agujas se interpolan durante 260 ms y las cifras reflejan la última lectura válida. Al faltar una lectura, el instrumento muestra un guion y oculta la aguja. El selector ofrece incrementos de 0,5 % y acceso directo a las 41 consignas entre −5 % y +15 %. El control experimental requiere una autorización inicial para la identidad ANT, el fabricante y modelo, el rango y la versión de la política. Se guarda localmente y se puede revocar en Ajustes con el entrenamiento detenido. El menú de la pantalla da acceso a los informes y el botón inferior usa la parada nativa.

## Calentamiento automático

Al abrir Entrenamiento libre, el único servicio de entrenamiento abre el canal dedicado para la identidad exacta del rodillo guardado. Ajustes permite cambiar esa selección. Durante la búsqueda y la identificación, el cuadro muestra el estado y presenta la telemetría que entrega el servicio. El cronómetro usa el tiempo de la sesión nativa desde su creación.

El motor verifica el canal abierto, la identidad coincidente, fabricante 67, modelo 22, señal y telemetría recientes y el estado del servicio. Con autorización guardada, Flutter solicita la activación para el UUID actual. El calentamiento concluye al confirmar el estado activo y habilitado. La activación no envía una consigna. Durante el calentamiento el perfil usa la referencia virtual de 0 %, sin atribuirle una consigna al rodillo. Detener llama al mismo cierre nativo, incluso durante el arranque, y el servicio puede seguir buscando en segundo plano una vez activo.

## Perfil de elevación virtual

El origen es 0 km y 0 m. OpenBkool usa la distancia ANT acumulada como aproximación de la distancia horizontal. Cada incremento válido aporta `deltaDistancia × pendiente / 100` metros a la elevación. Por ejemplo, después de 500 m al 0 %, 200 m al +5 % y 100 m al −2 %, el perfil termina en 800 m y 8 m de elevación virtual.

La sesión Android guarda el perfil bajo el mismo UUID. En el hilo de sesión, cada intervalo se atribuye a la última consigna manual que retornó correctamente de la API al procesar la muestra. Se toma 0 % como referencia inicial. El tramo que cruza una transición se atribuye con esa misma regla, sin estimar el instante de respuesta mecánica. Una selección pendiente, descartada o rechazada carece de efecto sobre la gráfica y las selecciones nuevas nunca recalculan tramos anteriores. La aceptación de la API solo representa una referencia para la simulación.

Al faltar distancia válida, el perfil omite ese avance y conserva la cota acumulada al reanudar. También ignora duplicados y espera a superar la última distancia graficada después de un retroceso del contador. La parada o un error de API suspenden la integración. La sesión conserva hasta 512 puntos y reduce el historial por grupos, reteniendo extremos, primer y último punto de cada grupo. El gráfico adapta sus escalas al recorrido completo e incluye margen. El informe JSON contiene `virtualElevation` con tripletas de distancia en metros, elevación en metros e identificador de segmento, que permite marcar los cortes por falta de datos. El CSV mantiene su estructura.

Las capturas usan datos simulados. Queda pendiente comprobar en el Galaxy S20 la legibilidad y fluidez durante telemetría real, la búsqueda con la pantalla bloqueada, la recuperación de la sesión y del perfil al volver, y el informe final después de detener desde la notificación. La validación física de la versión anterior cubrió las pendientes positivas hasta +8 %. Las negativas y las superiores a +8 % siguen siendo experimentales.
