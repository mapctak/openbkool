import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ant_trainer_search.dart';
import 'trainer_session.dart';
import 'training.dart';

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

class _OpenBkoolShellState extends State<OpenBkoolShell> {
  late final session = widget.session ?? TrainerSession();
  bool advanced = false, visited = false;
  @override
  void initState() {
    super.initState();
    unawaited(session.restore());
    if (widget.session == null) {
      unawaited(restoreActiveTraining());
    }
  }

  Future<void> restoreActiveTraining() async {
    try {
      await session.training.attachToTraining();
      if (mounted &&
          session.training.running &&
          !session.checkRunning &&
          ModalRoute.of(context)?.isCurrent == true) {
        openTraining();
      }
    } catch (_) {
      // Starting a workout still reports channel errors through its normal UI.
    }
  }

  @override
  void dispose() {
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  void showAdvanced() {
    setState(() {
      visited = true;
      advanced = true;
    });
  }

  void openTraining() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => TrainingPage(session: session)),
    );
  }

  Future<void> chooseTrainer() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => TrainerSelectionPage(session: session)),
    );
  }

  void openSettings() {
    Navigator.of(context).push<void>(
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
                  showAdvanced();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) => PopScope(
      canPop: !advanced,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => advanced = false);
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
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session.selected.name,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                ConnectionBadge(state: session.connection),
                              ],
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 156),
                            child: TextButton(
                              onPressed: session.training.manualStopping
                                  ? null
                                  : session.checkRunning
                                  ? () => session.disconnect(cancelCheck: true)
                                  : session.loading ||
                                        session.locked ||
                                        session.preferenceError != null
                                  ? null
                                  : session.readOnly
                                  ? session.disconnect
                                  : () => session.connect(checkOnly: true),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  session.checkRunning
                                      ? 'Cancelar'
                                      : session.readOnly
                                      ? 'Desconectar'
                                      : 'Comprobar conexión',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (session.checkFeedback case final feedback?)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                      child: Semantics(liveRegion: true, child: Text(feedback)),
                    ),
                  if (session.loading) const LinearProgressIndicator(),
                  if (session.preferenceError != null)
                    const Text('No se pudo leer el rodillo guardado.'),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.bolt, color: emerald),
                      title: const Text(
                        'ENTRENAMIENTO LIBRE',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: session.loading || session.training.commandBusy
                          ? null
                          : openTraining,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (visited)
            widget.advancedBuilder(
              session,
              () => setState(() => advanced = false),
            )
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
        : state == TrainerConnection.error
        ? Theme.of(context).colorScheme.error
        : Colors.blueGrey;
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            state == TrainerConnection.connected
                ? Icons.check_circle
                : state == TrainerConnection.error
                ? Icons.error_outline
                : Icons.circle_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              connectionLabel(state),
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
