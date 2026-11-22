import 'workout_summary.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'spinning_engine.dart';
import 'spinning_program.dart';
import 'trainer_session.dart';
import 'slope_presentation.dart';

String spinningTime(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
String spinningGrade(num? p) => p == null
    ? '— %'
    : '${p > 0 ? '+' : ''}${p.toStringAsFixed(1).replaceAll('.', ',')} %';

class SpinningProgramsPage extends StatelessWidget {
  const SpinningProgramsPage({super.key, required this.session});
  final TrainerSession session;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sesiones de spinning')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Spinning guiado · Los objetivos no cambian automáticamente la resistencia.',
        ),
        for (final program in spinningPrograms)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const Icon(Icons.timer_outlined),
              title: Text(program.name),
              subtitle: Text(
                '${program.duration.inMinutes} minutos · ${program.intervals.length} intervalos · 0–1 %',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      SpinningSessionPage(program: program, session: session),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class SpinningSessionPage extends StatefulWidget {
  const SpinningSessionPage({
    super.key,
    required this.program,
    required this.session,
    this.engine,
  });
  final SpinningProgram program;
  final TrainerSession session;
  final SpinningEngine? engine;
  @override
  State<SpinningSessionPage> createState() => _SpinningSessionPageState();
}

class _SpinningSessionPageState extends State<SpinningSessionPage>
    with WidgetsBindingObserver {
  final _clock = Stopwatch();
  late final SpinningEngine engine;
  Timer? _timer;
  bool _ending = false;
  @override
  void initState() {
    super.initState();
    _clock.start();
    engine =
        widget.engine ??
        SpinningEngine(widget.program, now: () => _clock.elapsed);
    WidgetsBinding.instance.addObserver(this);
    if (engine.state == SpinningState.running) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      setState(engine.tick);
      if (engine.terminal) _timer?.cancel();
    });
  }

  void _pause() {
    setState(engine.pause);
    _timer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pause();
    }
    // Resume is always explicit; no automatic timer/ANT restart.
  }

  Future<void> _finish({bool pop = false}) async {
    if (_ending) return;
    _timer?.cancel();
    setState(() {
      engine.finish();
      _ending = true;
    });
    if (widget.session.training.running) {
      await widget.session.training.stop(
        reason: pop ? 'screen_closed' : 'user_finish',
      );
    }
    if (!mounted) return;
    setState(() => _ending = false);
    if (pop &&
        !widget.session.training.running &&
        !widget.session.training.commandBusy) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    engine.finish();
    _clock.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      final report = widget.session.training.snapshot;
      final telemetry = report['telemetry'] as Map? ?? const {};
      final manual = report['manualControl'] as Map? ?? const {};
      final slope = SlopePresentation.fromReport(report);
      final current = engine.current, next = engine.next;
      final terminal = engine.terminal;
      String metric(String key, int decimals) =>
          report['running'] == true &&
              telemetry['signal'] == 'receiving' &&
              telemetry[key] is num
          ? (telemetry[key] as num)
                .toStringAsFixed(decimals)
                .replaceAll('.', ',')
          : '—';
      return PopScope(
        canPop:
            !widget.session.training.running &&
            !widget.session.training.commandBusy &&
            !_ending,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_finish(pop: true));
        },
        child: Scaffold(
          appBar: AppBar(title: Text(widget.program.name)),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (!terminal)
                    FilledButton.icon(
                      onPressed: _ending
                          ? null
                          : () {
                              if (engine.state == SpinningState.running) {
                                _pause();
                              } else {
                                setState(() {
                                  if (engine.state == SpinningState.ready) {
                                    engine.start();
                                  } else {
                                    engine.resume();
                                  }
                                });
                                _schedule();
                              }
                            },
                      icon: Icon(
                        engine.state == SpinningState.running
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                      label: Text(switch (engine.state) {
                        SpinningState.running => 'Pausar',
                        SpinningState.paused => 'Reanudar',
                        _ => 'Iniciar sesión',
                      }),
                    ),
                  OutlinedButton.icon(
                    onPressed: _ending ? null : () => _finish(),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(_ending ? 'Finalizando…' : 'Finalizar'),
                  ),
                ],
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'SPINNING GUIADO · Sin control automático de resistencia',
              ),
              Text(connectionLabel(widget.session.connection)),
              if (!widget.session.training.running)
                const Text(
                  'Sin telemetría activa. Puedes seguir la guía; conecta el rodillo desde Inicio para ver datos en directo.',
                ),
              if (engine.state == SpinningState.paused)
                const Text(
                  'Guía en pausa. Pausar no solicita llano ni confirma la resistencia física.',
                ),
              if (terminal)
                Text(
                  engine.state == SpinningState.completed
                      ? 'Programa completado'
                      : 'Sesión finalizada',
                ),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  Text(
                    'Transcurrido: ${spinningTime(engine.elapsed)}',
                    key: const ValueKey('spinningElapsed'),
                  ),
                  Text(
                    'Restante: ${spinningTime(engine.remaining)}',
                    key: const ValueKey('spinningRemaining'),
                  ),
                ],
              ),
              LinearProgressIndicator(
                value:
                    engine.elapsed.inMilliseconds /
                    widget.program.duration.inMilliseconds,
              ),
              Card(
                color: const Color(0xFF008F70),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text(
                        'Pendiente objetivo',
                        style: TextStyle(color: Colors.white, fontSize: 20),
                      ),
                      Text(
                        spinningGrade(current?.targetPercent),
                        key: const ValueKey('spinningTarget'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        current == null
                            ? 'Sin objetivo activo'
                            : '${current.phase.label} · Intervalo ${engine.intervalIndex! + 1}/${widget.program.intervals.length}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      if (current != null)
                        Text(
                          'Quedan ${spinningTime(engine.intervalRemaining)}',
                          style: const TextStyle(color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
              Text(
                'Próximo intervalo: ${next == null ? 'ninguno' : '${next.phase.label} · ${spinningGrade(next.targetPercent)} · ${spinningTime(next.duration)}'}',
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Última pendiente ordenada al rodillo (API): ${spinningGrade(slope.apiPercent)}',
                        key: const ValueKey('spinningOrdered'),
                      ),
                      Text(
                        'Control manual: ${manual['enabled'] == true ? 'activado expresamente; conserva su límite de 30 s' : 'no activo'}',
                      ),
                      const Text(
                        'Resistencia física no confirmada. El objetivo guiado no es una orden enviada.',
                      ),
                    ],
                  ),
                ),
              ),
              ...trainingAvailability(report),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metric('Potencia', '${metric('powerW', 0)} W'),
                  _metric('Velocidad', '${metric('speedKmh', 1)} km/h'),
                  _metric('Cadencia', '${metric('cadenceRpm', 0)} RPM'),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'El control manual sigue disponible en Entrenamiento libre: activación expresa, 0–1 % y máximo 30 s. El modo continuo permanece bloqueado.',
              ),
              const Text(
                'Finalizar o salir cierra la conexión ANT activa con las protecciones existentes. Completar los intervalos no envía ninguna pendiente.',
              ),
              ExpansionTile(
                title: const Text('Programa completo'),
                children: [
                  for (final interval in widget.program.intervals)
                    ListTile(
                      title: Text(interval.phase.label),
                      subtitle: Text(
                        '${spinningTime(interval.duration)} · ${spinningGrade(interval.targetPercent)}',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget _metric(String label, String value) => SizedBox(
    width: 145,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            FittedBox(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
