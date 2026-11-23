import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ant_trainer_search.dart';
import 'trainer_session.dart';
import 'training.dart';
import 'spinning.dart';
import 'workout_dashboard.dart';

const emerald = Color(0xFF008F70);
typedef AdvancedBuilder = Widget Function(
  TrainerSession session,
  VoidCallback close,
);

class OpenBkoolShell extends StatefulWidget {
  const OpenBkoolShell({
    super.key,
    required this.advancedBuilder,
    this.session,
  });
  final AdvancedBuilder advancedBuilder;
  final TrainerSession? session;
  @override
  State<OpenBkoolShell> createState() => _OpenBkoolShellState();
}

class _OpenBkoolShellState extends State<OpenBkoolShell>
    with WidgetsBindingObserver {
  late final session = widget.session ?? TrainerSession();
  bool advanced = false, visited = false;
  bool initialized = false;
  bool trainingRouteOpen = false;
  bool catalogOpen = false;
  Timer? connectionRetry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session.addListener(scheduleConnectionRetry);
    unawaited(restoreConnection());
  }

  Future<void> restoreConnection() async {
    await session.restore();
    if (!mounted) return;
    if (widget.session == null) {
      try {
        await session.training.attachToTraining();
      } catch (_) {
        // The connection attempt reports transport errors through the controller.
      }
    }
    if (!mounted) return;
    initialized = true;
    connectFromHome();
  }

  bool get canConnectFromHome {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        initialized &&
        !advanced &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        ModalRoute.of(context)?.isCurrent == true &&
        !session.loading &&
        !session.locked &&
        !session.readOnly &&
        session.training.snapshot['resourcesReleased'] != false &&
        session.training.snapshot['status'] != 'stopping_zero_unconfirmed' &&
        session.preferenceError == null &&
        session.connection != TrainerConnection.connecting;
  }

  void connectFromHome() {
    if (!canConnectFromHome ||
        session.training.snapshot['clientErrorCode'] ==
            'training_service_blocked' ||
        session.training.snapshot['status'] == 'cleanup_failed') {
      return;
    }
    connectionRetry?.cancel();
    connectionRetry = null;
    unawaited(session.connect(checkOnly: true));
  }

  void scheduleConnectionRetry() {
    if (!canConnectFromHome || connectionRetry != null) return;
    final report = session.training.snapshot;
    final status = report['status'] as String?;
    if (status?.startsWith('link_lost:') != true &&
        !const {
          'user_finish',
          'program_completed',
          'check_timeout',
          'radio_search_timeout',
          'disconnected',
          'disconnect_trainer',
          'connection_idle_timeout',
          'channel_death',
          'channel_closed',
          'radio_service_disconnected',
        }.contains(status)) {
      return;
    }
    connectionRetry = Timer(const Duration(seconds: 15), () {
      connectionRetry = null;
      connectFromHome();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshFromService());
    } else {
      connectionRetry?.cancel();
      connectionRetry = null;
    }
  }

  Future<void> refreshFromService() async {
    if (!initialized) return;
    await session.training.refreshTraining();
    if (connectionRetry == null) connectFromHome();
  }

  @override
  void dispose() {
    connectionRetry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(scheduleConnectionRetry);
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  Future<void> showAdvanced() async {
    setState(() {
      visited = true;
      advanced = true;
    });
    if (session.readOnly ||
        (session.training.commandBusy && !session.training.running)) {
      await session.disconnect();
    }
  }

  void closeAdvanced() {
    setState(() => advanced = false);
    connectFromHome();
  }

  Future<void> openTraining({String? programId, String? resumeId}) async {
    if (trainingRouteOpen ||
        (resumeId != null &&
            (!session.training.running ||
                session.training.snapshot['sessionId'] != resumeId)) ||
        (programId != null && session.locked)) {
      return;
    }
    trainingRouteOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => TrainingPage(
            session: session,
            programId: programId,
            resumeOnly: resumeId != null,
          ),
        ),
      );
    } finally {
      trainingRouteOpen = false;
      scheduleConnectionRetry();
    }
  }

  Future<void> openSpinning() async {
    if (catalogOpen || session.locked) return;
    catalogOpen = true;
    try {
      final catalog = session.training.spinningCatalog();
      final id = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => SpinningSelector(catalog: catalog)),
      );
      if (mounted && id != null && !session.locked) {
        await openTraining(programId: id);
      }
    } finally {
      catalogOpen = false;
    }
  }

  Future<void> exportLastWorkout(String id, bool csv) async {
    try {
      final json = csv
          ? null
          : await session.training.exportJson(id, finalized: true);
      final text = csv
          ? await session.training.exportCsv(id)
          : json == null
          ? null
          : const JsonEncoder.withIndent('  ').convert(json);
      if (text == null) throw StateError('Informe no disponible');
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Informe copiado')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo copiar el informe')),
        );
      }
    }
  }

  Widget workoutCard() {
    final report = session.training.snapshot;
    final program = report['spinning'] as Map?;
    final spinning = report['workoutMode'] == 'spinning';
    final grade = spinning
        ? (program?['currentGrade'])
        : (report['manualControl'] as Map?)?['lastRequestedPercent'];
    final stopping =
        session.training.manualStopping ||
        report['status'] == 'stopping_zero_unconfirmed';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ENTRENAMIENTO EN CURSO',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(spinning ? 'Spinning' : 'Libre'),
            if (program != null) Text(program['name'] as String),
            Text(
              '${workoutTime(report['trainingElapsedMs'] as num? ?? 0)} · Pendiente ${slopeLabel(grade as num?)}',
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: stopping || report['sessionId'] is! String
                      ? null
                      : () => openTraining(
                          resumeId: report['sessionId'] as String,
                        ),
                  child: const Text('VOLVER AL ENTRENAMIENTO'),
                ),
                TextButton(
                  onPressed: stopping || report['sessionId'] == null
                      ? null
                      : () => session.stopWorkout(
                          expectedId: report['sessionId'] as String,
                        ),
                  child: Text(stopping ? 'DETENIENDO…' : 'DETENER'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> chooseTrainer() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => TrainerSelectionPage(session: session)),
    );
  }

  Future<void> openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Ajustes')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const Icon(Icons.directions_bike),
                title: const Text('Rodillo seleccionado'),
                subtitle: Text(
                  '${session.selected.name}\n${session.selected.id}',
                ),
                onTap: chooseTrainer,
              ),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Diagnósticos avanzados'),
                subtitle: const Text(
                  'BLE, ANT, mensajes, control y exportaciones',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(showAdvanced());
                },
              ),
            ],
          ),
        ),
      ),
    );
    connectFromHome();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) => PopScope(
      canPop: !advanced,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) closeAdvanced();
      },
      child: IndexedStack(
        index: advanced ? 1 : 0,
        children: [
          Scaffold(
            appBar: AppBar(
              title: const Text('OpenBkool'),
              actions: [
                IconButton(
                  tooltip: 'Ajustes',
                  onPressed: openSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              session.selected.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConnectionBadge(state: session.connection),
                        ],
                      ),
                    ),
                  ),
                  if (session.loading) const LinearProgressIndicator(),
                  if (session.preferenceError != null)
                    const Text('No se pudo leer el rodillo guardado.'),
                  const SizedBox(height: 10),
                  if (session.training.running &&
                      session.training.snapshot['trainingServiceActive'] !=
                          false)
                    workoutCard()
                  else ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.bolt, color: emerald),
                        title: const Text(
                          'ENTRENAMIENTO LIBRE',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: session.loading || session.locked
                            ? null
                            : openTraining,
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.directions_bike,
                          color: emerald,
                        ),
                        title: const Text(
                          'SPINNING',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: session.loading || session.locked
                            ? null
                            : openSpinning,
                      ),
                    ),
                    if (session.lastWorkout case final workout?)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(workout.outcome ?? 'Último entrenamiento'),
                        trailing: PopupMenuButton<bool>(
                          tooltip: 'Exportar último entrenamiento',
                          onSelected: (csv) =>
                              unawaited(exportLastWorkout(workout.id, csv)),
                          itemBuilder: (_) => [
                            if (workout.hasCsv)
                              const PopupMenuItem(
                                value: true,
                                child: Text('Copiar CSV'),
                              ),
                            const PopupMenuItem(
                              value: false,
                              child: Text('Copiar JSON'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (visited)
            widget.advancedBuilder(session, closeAdvanced)
          else
            const SizedBox.shrink(),
        ],
      ),
    ),
  );
}

class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key, required this.state});
  final TrainerConnection state;
  @override
  Widget build(BuildContext context) {
    final color = state == TrainerConnection.connected
        ? emerald
        : Colors.blueGrey;
    final label = switch (state) {
      TrainerConnection.connected => 'CONECTADO',
      TrainerConnection.connecting => 'CONECTANDO…',
      _ => 'DESCONECTADO',
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            state == TrainerConnection.connected
                ? Icons.check_circle
                : Icons.circle_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class TrainerSelectionPage extends StatelessWidget {
  const TrainerSelectionPage({super.key, required this.session});
  final TrainerSession session;
  Future<void> export(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ')
            .convert(session.search.snapshot),
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Búsqueda ANT copiada en JSON')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([session, session.search]),
    builder: (context, _) {
      final choices = <String, SavedTrainer>{
        session.selected.id: session.selected,
      };
      for (final item
          in session.search.snapshot['devices'] as List? ?? const []) {
        try {
          final d = SavedTrainer.fromMap(item as Map);
          choices[d.id] = d;
        } on FormatException {
          /* FE-C remains visible in advanced search; V1 connections only. */
        }
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Seleccionar rodillo')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'La selección se guarda en este teléfono. Elegir un rodillo no lo conecta ni activa el control.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: session.locked
                  ? null
                  : () async {
                      if (session.readOnly) await session.disconnect();
                      if (!context.mounted || session.readOnly) return;
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => AntTrainerSearchPage(
                            controller: session.search,
                            onExport: () => export(context),
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.search),
              label: const Text('Buscar rodillos'),
            ),
            if (session.locked)
              const Text(
                'Finaliza la sesión activa antes de cambiar de rodillo.',
              ),
            for (final trainer in choices.values)
              Card(
                child: ListTile(
                  title: Text(trainer.name),
                  subtitle: Text(
                    '${trainer.id}${trainer.id == session.selected.id ? ' · recordado' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: session.locked
                      ? null
                      : () async {
                          try {
                            await session.select(trainer);
                            if (context.mounted) Navigator.pop(context);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                ),
              ),
          ],
        ),
      );
    },
  );
}
