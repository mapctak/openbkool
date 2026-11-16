# Spinning guiado — OpenBkool 1.2.0+11

Rama `feature/control-ant`. Nueva entrada **Sesiones de spinning** en Inicio,
con cuatro programas de 15–30 minutos. Es una guía de objetivos y tiempos:
**ningún cambio de intervalo transmite pendiente ni habilita resistencia**.
El modo continuo físico permanece bloqueado. El control manual existente sigue
requiriendo activación expresa, máximo +1 % y ventana de 30 segundos.

## Sesiones predefinidas

Todos los objetivos son porcentajes de pendiente guiada, no órdenes ANT ni
confirmaciones de resistencia real. Se usan exclusivamente 0 %, +0,5 % y +1 %.

### Spinning suave — 15 minutos

| Intervalo | Fase | Duración | Pendiente objetivo |
|---|---|---:|---:|
| 1 | Calentamiento | 3 min | 0 % |
| 2 | Trabajo | 4 min | +0,5 % |
| 3 | Recuperación | 2 min | 0 % |
| 4 | Trabajo | 4 min | +0,5 % |
| 5 | Recuperación | 2 min | 0 % |

### Spinning progresivo — 20 minutos

| Intervalo | Fase | Duración | Pendiente objetivo |
|---|---|---:|---:|
| 1 | Calentamiento | 4 min | 0 % |
| 2 | Trabajo | 4 min | +0,5 % |
| 3 | Trabajo | 4 min | +1 % |
| 4 | Recuperación | 2 min | +0,5 % |
| 5 | Trabajo | 4 min | +1 % |
| 6 | Recuperación | 2 min | 0 % |

### Spinning por intervalos — 25 minutos

| Intervalo | Fase | Duración | Pendiente objetivo |
|---|---|---:|---:|
| 1 | Calentamiento | 5 min | 0 % |
| 2, 4, 6, 8, 10 | Trabajo (cada uno) | 2 min | +1 % |
| 3, 5, 7, 9, 11 | Recuperación (cada uno) | 2 min | 0 % |

La secuencia es calentamiento y cinco repeticiones de trabajo/recuperación;
no se agrupan todos los trabajos antes de las recuperaciones.

### Spinning de resistencia — 30 minutos

| Intervalo | Fase | Duración | Pendiente objetivo |
|---|---|---:|---:|
| 1 | Calentamiento | 5 min | 0 % |
| 2 | Trabajo | 8 min | +0,5 % |
| 3 | Recuperación | 2 min | 0 % |
| 4 | Trabajo | 10 min | +1 % |
| 5 | Recuperación | 5 min | 0 % |

## Interfaz y uso

1. Para ver telemetría, usar **Conectar rodillo** desde Inicio. Eso no arma el
   control de resistencia. La guía también funciona sin conectar y muestra «—»
   en las métricas, explicando que no hay datos activos.
2. Abrir **Sesiones de spinning**, elegir un programa y pulsar **Iniciar sesión**.
   Elegir una tarjeta no inicia el reloj ni la comunicación ANT.
3. La pantalla muestra objetivo destacado, fase/intervalo actual y siguiente,
   tiempo total transcurrido/restante, restante del intervalo, progreso y potencia,
   velocidad y cadencia de la conexión existente.
4. **Pausar/Reanudar** solo controla el tiempo guiado. Pausar no solicita llano,
   no modifica el objetivo físico ni confirma que el rodillo haya reducido carga.
5. **Finalizar** termina la guía y solicita cerrar la conexión ANT activa usando
   el método existente. Salir con Atrás también finaliza/cierra si hay conexión;
   si no se confirma el cierre se conserva la pantalla para poder reintentarlo.

El objetivo se llama **Pendiente objetivo**. Separadamente se muestra **Última
pendiente ordenada al rodillo (API)**, tomada del último éxito manual de esa
conexión, nunca del programa. No se fabrica 0 % si no existe esa información.
La resistencia física sigue explícitamente no confirmada. Las métricas solo se
muestran como actuales mientras el reporte nativo está activo y recibiendo;
la frescura individual continúa gestionada por el decodificador existente.

Los botones se mantienen al pie, con distribución adaptable; las métricas usan
Wrap para pantallas estrechas. Se probaron layouts Flutter de 360×640 (S7 como
referencia de anchura) y 412×915 (S20 como referencia), sin afirmar una prueba
física de esta APK en esos teléfonos.

## Separación del motor y ANT

- `lib/spinning_program.dart`: programas, fases y duraciones; listas inmutables,
  validación de duración positiva y pasos/rango de objetivo. Se pueden modificar
  las listas de programas sin cambiar pantallas ni transporte.
- `lib/spinning_engine.dart`: máquina `ready/running/paused/completed/finished`,
  reloj inyectable, intervalo actual/siguiente, tiempos y objetivos de salida.
  No importa Flutter, MethodChannel ni código ANT. Un adaptador futuro podría
  consumir esos datos, pero requerirá autorización y protecciones independientes;
  **no existe tal adaptador en esta entrega**.
- `lib/spinning.dart`: selección y sesión, reloj Stopwatch monótono y refresco de
  250 ms, lectura de la telemetría y del último envío manual. No contiene llamadas
  a `setManualSlope`, `enableManualTest` ni `prepareSlope`.
- `lib/app_home.dart`: nueva navegación, sin sustituir entrenamiento libre,
  Ajustes o diagnósticos avanzados. GPX sigue marcado como próximamente.

El tiempo se calcula desde el reloj, no sumando ticks: un frame retrasado salta
al intervalo correcto, y al llegar al total se limita exactamente a la duración
programada. Las pausas no cuentan como pedaleo guiado. Finalizar antes de tiempo
conserva lo transcurrido y elimina el objetivo activo. Un programa completado no
puede reanudarse desde su final: se elige una nueva sesión.

### Qué operaciones pueden ocurrir

| Acción | Efecto sobre ANT |
|---|---|
| Abrir catálogo, elegir programa, iniciar guía | Ninguno. |
| Cambiar intervalo, pausar o reanudar | Ninguno. |
| Completar el programa por tiempo | Ninguno; muestra «Programa completado». Se ofrece Finalizar para cerrar la conexión. |
| Finalizar, salir o pasar a segundo plano | Parada/cierre mediante la capa existente, si hay conexión activa. |

La última fila preserva las protecciones ya autorizadas. Si el usuario hubiese
armado previamente el control manual en otra pantalla, la capa nativa puede
intentar su único cero al finalizar; **no es una orden de intervalo**. No se
alteran ese código ni sus condiciones. Si solo se conectó para telemetría y nunca
se armó resistencia, la parada nativa omite cero como antes.

La guía de 15–30 minutos **no prolonga** una autorización manual de 30 segundos.
El acceso manual permanece en Entrenamiento libre; Spinning no incorpora una
nueva habilitación ni controles de transmisión. Para telemetría durante toda la
guía, conectar sin armar una prueba de resistencia. Si una prueba manual vence,
se mantiene su parada/cierre y la guía no reconecta ni la reactiva.

## Ciclo de vida, diagnóstico y límites

En segundo plano se pausa la guía y se solicita la parada nativa; Android mantiene
su protección `onStop`. Al volver no se reanuda automáticamente ni el reloj ni
ANT. Si la conexión terminó, se explica la ausencia de telemetría; una conexión
nueva requiere la navegación habitual. El reloj y el programa en curso son de
memoria: no hay recuperación de una guía tras matar el proceso. No se registra
ni se restaura una autorización de resistencia.

El diagnóstico JSON, los eventos ANT, la exportación CSV y todas sus pantallas
siguen en Ajustes → Diagnósticos avanzados. El CSV registra la telemetría de la
conexión existente: no se añaden columnas de intervalos ni un nuevo exportador
spinning. Tras Finalizar se puede volver a Inicio y exportar por las herramientas
habituales. No se modifica código Kotlin ni codificación en esta tarea.

## Validación

- `flutter analyze`: sin incidencias.
- `flutter test`: **62 pruebas correctas**. Incluye duración exacta 15/20/25/30,
  límites de objetivo, cada frontera de intervalo, pausa/reanudación, ticks
  atrasados, finalización anticipada/completa, navegación y tamaños de pantalla.
- La prueba de integración simulada cambia 0 → +0,5 → +1 mientras la última orden
  API permanece en 0, sin llamadas de pendiente/activación. Finalizar solo usa
  el cierre existente. Otra prueba verifica cero RPC al completar automáticamente
  la guía. Segundo plano pausa y cierra; regresar no reanuda.
- `./gradlew :app:testDebugUnitTest`: **72 pruebas correctas** de la capa ANT
  existente. Transporte simulado; sin comandos reales.
- `flutter build apk --debug`: correcto, versión **1.2.0+11**.
- APK: `build/app/outputs/flutter-apk/openbkool-1.2.0-11-debug.apk`.

Pendiente comprobar la nueva navegación y legibilidad en S7/S20 físicos. No hay
control automático, GPX, cambio de firmware, ampliación de pendiente ni permiso
para usar continuo físico.
