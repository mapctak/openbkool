# Interfaz OpenBkool 1.1

Trabajo en la rama **feature/control-ant**, sin modificar la rama main.
Versión Android: **1.1.0+3**. Fecha de desarrollo: 2026-11-15.

El usuario ha confirmado detección/telemetría ANT y un efecto físico perceptible
al solicitar 0 % y +1 % en el Smart Pro v1 30064/112/5. Este cambio transforma
la navegación y la presentación; esa observación física **no se convierte en una
confirmación de aplicación del protocolo** ni permite ampliar el rango de control.

## Inicio

La app abre una pantalla propia con nombre e icono originales de OpenBkool,
fondo claro, verde esmeralda #008F70, tarjetas blancas y botones grandes.

- Tarjeta del rodillo seleccionado, modelo e identidad completa.
- Estado separado: desconectado, conectando, conectado, desconectando o error.
- «Conectar rodillo»: conexión directa `training_connected` a la selección
  guardada, sin buscar de nuevo ni habilitar control de resistencia.
- «Entrenamiento libre»: abre los datos de la sesión compartida; no inicia
  conexión ni envía órdenes al entrar. Si aún no existe conexión, se puede
  solicitar explícitamente con «Iniciar entrenamiento».
- «Rutas GPX»: tarjeta informativa «Próximamente», sin navegación ni simulación.
- Ajustes permite elegir otro rodillo y acceder a **Diagnósticos avanzados**.

Si falla la conexión, se presenta error y acceso «Buscar rodillos». La búsqueda
sigue siendo explícita, utiliza el buscador secuencial actual y no se ejecuta
como reintento automático. Si hay una sesión aún activa hay que finalizarla
antes de seleccionar otro rodillo. Un fallo de limpieza mantiene las restricciones
nativas previas; no se ignora el bloqueo de canales del transporte.

## Selección local y estados

`SavedTrainer` es un perfil local, con 30064/112/5 y modelo 22 como selección
conocida inicial. El selector permite guardar manualmente cualquiera de los
candidatos BKOOL_V1_PUBLIC tipo 112 que devuelva la búsqueda. Los equipos FE-C
siguen visibles en el buscador avanzado; este rediseño no añade su conexión de
entrenamiento ni habilita Bkool V2 privado.

La selección se guarda mediante un canal nuevo, `openbkool/preferences`, en
`SharedPreferences` privado Android. Se guardan **solo** protocolo, número,
tipo, transmisión y metadatos opcionales de modelo/fabricante. No se guardan:

- Estado conectado, tramas de telemetría ni datos de autorización.
- UUID de sesión ni habilitación del control manual.
- Una condición que permita saltarse la identificación nativa del equipo.

Los metadatos recordados sirven para la etiqueta de la tarjeta, no para declarar
que se recibió página 0x50 en la sesión actual. La conexión envía la identidad al
controlador existente; las validaciones nativas siguen siendo obligatorias.

`connectionFor()` solo muestra **Conectado** si el snapshot nativo está activo,
tiene UUID, la identidad seleccionada coincide con la sesión, la identidad está
verificada y la señal está en `receiving`. Recordar el rodillo, terminar `start()`
o tener datos de una sesión anterior no cumplen esa condición. En reposo se
indica expresamente «Rodillo recordado. Aún no está conectado».

El guardado confirma la escritura antes de actualizar la selección en memoria.
Si falla, permanece la selección anterior y se informa del error. Una respuesta
antigua de carga no puede sobrescribir una selección más reciente. No hay
sincronización con servidores ni nuevos permisos de almacenamiento.

## Entrenamiento libre

Vista nueva sobre el controlador y decodificador existentes:

- Potencia destacada en una tarjeta esmeralda, W.
- Cadencia RPM, velocidad km/h, distancia km y tiempo HH:MM:SS en tarjetas.
- Estado de conexión, señal perdida y distancia parcial cuando corresponda.
- Tiempo **de sesión**, obtenido del reloj monótono nativo; no se presenta
  como tiempo exclusivo de pedaleo. Al cerrar se conserva el último registro.
- «Pendiente solicitada» separada de «Orden enviada a la API ANT: X %».
- Advertencia permanente: **Aplicación física no confirmada por el protocolo**.

La última solicitud puede diferir de la última orden retornada por la API,
por ejemplo si se rechazó por frecuencia o por pérdida de señal. Se muestran
valores separados y el rechazo; no se anuncia como enviada una solicitud
rechazada ni como aplicado un mero retorno de la API.

Los botones − / 0 % / + son grandes y mantienen exactamente sus callbacks,
incrementos y límites previos. El panel reutiliza la confirmación por sesión:

- Sin comandos al abrir, conectar, seleccionar, restaurar preferencias o navegar.
- Autorización explícita en la sesión actual y validaciones del canal, identidad,
  fabricante/modelo y frescura de telemetría.
- Rango 0–1 %, pasos 0,5 puntos, plazo de prueba 30 s.
- Deduplicación, errores y watchdog existentes sin modificación.
- «Detener prueba» visible y fijo durante la prueba; parada controlada existente.
- Salir de Entrenamiento libre ejecuta el cierre controlado antes de volver.

Los controles permanecen desactivados sin autorización y muestran la explicación
de disponibilidad en lenguaje legible. El detalle técnico se consulta aparte.
Ni el perfil recordado ni las observaciones físicas anteriores sustituyen los
guardas de la sesión. Enviar 0 % o cerrar no garantizan resistencia segura.

La prueba de control sigue siendo **experimental**: el timeout de 30 s conserva
el comportamiento previo de parada y cierre del canal. No se prolonga el control
para hacer entrenamientos largos. Sin activar la prueba, la recepción continua
mantiene su comportamiento anterior. No se implementa ERG, firmware ni GPX.

## Diagnósticos conservados

Ruta principal: **Ajustes → Diagnósticos avanzados**.

Se conserva `BleDiagnosticPage`, con sus pantallas enlazadas y el código previo:

- Escáner BLE sin filtros, selección manual y enumeración GATT.
- Diagnóstico ANT: hardware, servicios, canales y errores.
- Búsqueda secuencial FE-C y Bkool V1 público.
- Tramas hexadecimales, operaciones, eventos, identificación y control detallado.
- JSON combinado BLE/ANT/entrenamiento/control y JSON propio del entrenamiento.
- CSV de entrenamiento, exportable tras finalizar como antes.

El contenedor usa `IndexedStack` y monta los diagnósticos al visitarlos por primera
vez. Después conserva la misma instancia al volver a Inicio: sus observaciones,
registros y estado no se borran por navegar. Los controladores ANT pertenecen a
la sesión de la aplicación y se comparten con las pantallas, sin duplicar radios.
No se lanza escaneo BLE ni búsqueda ANT al iniciar la app.

Desde Entrenamiento libre también hay un acceso al diagnóstico detallado del
entrenamiento. Ese subpanel no toma posesión del ciclo de vida: volver de él a
los datos no detiene la sesión. Salir de la pantalla de entrenamiento principal
sí mantiene la parada. Las herramientas avanzadas pueden detener explícitamente
la sesión y conservan todos sus registros.

## Separación técnica y compatibilidad

| Componente | Responsabilidad |
|---|---|
| `lib/app_home.dart` | Inicio, Ajustes y selección manual |
| `lib/trainer_session.dart` | Perfil guardado y estado derivado de conexión |
| `lib/workout_summary.dart` | Métricas y estados de solicitud/API |
| `lib/training.dart` | Vista libre y panel detallado, con controles compartidos |
| `lib/main.dart` | Tema y diagnósticos previos, con controladores inyectados |
| `TrainerPreferences.kt`, `SavedTrainerRecord.kt` | Almacenamiento local validado |
| Controladores/decodificador/transporte ANT existentes | Sin cambios |

El único cambio en `MainActivity.kt` registra el canal de preferencias. No se
modifican `AntTrainerSearch.kt`, `ManualAntControl.kt`, `AntOperationTrace.kt`,
`BkoolTelemetry.kt`, el controlador Dart `ant_trainer_search.dart` ni los guardas
`manual_control_status.dart`. Tampoco se modifican UUID BLE, permisos, RF 40,
período 32768, codificación de páginas ni dependencias ANT/FlutterBluePlus.

Se conserva el mínimo Android existente (API 24). `SharedPreferences` está
soportado por esas versiones. No se añaden paquetes ni SDKs con un mínimo Android
mayor. Las vistas usan desplazamiento, tarjetas adaptables, botones accesibles
y cuadrícula de dos columnas. Se prueban dimensiones lógicas 360×640 para S7 y
se revisan capturas de 390×844; no equivalen a una nueva prueba física en S7/S20.

## Revisión visual

Estas capturas se generan con **datos simulados** para revisar el diseño. No son
capturas de una conexión real ni evidencia de respuesta del rodillo:

- [Inicio](images/inicio_openbkool_1_1.png).
- [Entrenamiento libre](images/entrenamiento_openbkool_1_1.png).

## Validación

Las pruebas nuevas cubren navegación a Ajustes/diagnósticos, mantenimiento de su
instancia, guardado y restauración de selección, errores de escritura, carrera
entre lectura y selección, estados recordado/conectando/conectado/error/cierre,
identidad de conexión directa, selección entre varios equipos y ausencia de
conexión automática. También comprueban la separación de pendiente solicitada y
retorno de API, dimensiones S7 y que consultar detalles no detiene la sesión,
pero salir del entrenamiento sí lo hace. Los tests usan almacenamiento y canales
simulados; el codec nativo de persistencia tiene pruebas Kotlin propias.

Se conserva íntegra la regresión de BLE, ANT, control manual y tramas capturadas.
No se ejecutan comandos ANT reales en los tests ni se instala la app durante
este trabajo. Queda pendiente probar instalación, selección persistente tras
matar/reabrir el proceso y una sesión física en ambos teléfonos con la UI nueva.

Resultados locales del 2026-11-15:

- `flutter analyze`: sin incidencias.
- `flutter test`: 33 pruebas correctas (21 previas y 12 de interfaz/estado).
- `cd android` y `./gradlew :app:testDebugUnitTest`: 46 pruebas correctas.
- `flutter build apk --debug`: compilación correcta.
- APK instalable con nombre propio:
  `build/app/outputs/flutter-apk/openbkool-1.1.0-3-debug.apk`.
- `aapt dump badging`: nombre OpenBkool, versión 1.1.0, versionCode 3,
  minSdk 24, targetSdk 36 (mínimo/objetivo Android conservados).
- `git diff --check`: correcto. Rama activa `feature/control-ant`.
- Comparación con Git de los controladores, transporte, decodificador y guardas
  ANT enumerados arriba: sin cambios. No se modifica ni se publica la rama main.
- Persisten avisos previos de deprecación Kotlin/AGP; no impiden las pruebas ni
  la compilación. No se realizaron transmisiones o pruebas físicas durante el
  rediseño. La revisión visual usa fuentes/icono de la aplicación y datos simulados.
