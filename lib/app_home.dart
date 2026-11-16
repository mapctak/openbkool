import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ant_trainer_search.dart';
import 'trainer_session.dart';
import 'training.dart';
import 'spinning.dart';
import 'manual_ride.dart';

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
      MaterialPageRoute(
        builder: (_) => TrainingPage(
          controller: session.training,
          searchController: session.search,
          simple: true,
          initialDevice: session.selected.toJson(),
          onDeviceSelected: (d) => session.select(SavedTrainer.fromMap(d)),
        ),
      ),
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
              const ListTile(
                leading: Icon(Icons.shield_outlined),
                title: Text('Control manual experimental'),
                subtitle: Text(
                  'Activación por sesión · 0–1 % · máximo 30 s. Cerrar el canal no garantiza resistencia segura.',
                ),
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
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/icon/openbkool.png',
                          width: 72,
                          height: 72,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tu próximo entrenamiento',
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text('Conecta. Pedalea. Disfruta.'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TU RODILLO',
                            style: TextStyle(
                              color: emerald,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            session.selected.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text('ANT · ${session.selected.id}'),
                          const SizedBox(height: 12),
                          ConnectionBadge(state: session.connection),
                          if (session.connection ==
                              TrainerConnection.disconnected)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Rodillo recordado. Aún no está conectado.',
                              ),
                            ),
                          if (session.connection == TrainerConnection.error)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'No se pudo mantener la conexión. Puedes finalizar y volver a conectar o buscar el rodillo.',
                              ),
                            ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: session.loading || session.locked
                                  ? null
                                  : session.connect,
                              icon: const Icon(Icons.link),
                              label: Text(
                                session.connection ==
                                        TrainerConnection.connected
                                    ? 'Rodillo conectado'
                                    : 'Conectar rodillo',
                              ),
                            ),
                          ),
                          if (session.training.running)
                            TextButton(
                              onPressed: session.training.commandBusy
                                  ? null
                                  : session.training.stop,
                              child: const Text('Desconectar rodillo'),
                            ),
                          TextButton.icon(
                            onPressed: session.loading || session.locked
                                ? null
                                : chooseTrainer,
                            icon: const Icon(Icons.search),
                            label: Text(
                              session.connection == TrainerConnection.error
                                  ? 'Buscar rodillos'
                                  : 'Cambiar o buscar rodillo',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (session.loading) const LinearProgressIndicator(),
                  if (session.preferenceError != null)
                    Text(
                      session.preferenceError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(20),
                      leading: const Icon(Icons.bolt, color: emerald, size: 32),
                      title: const Text(
                        'Entrenamiento libre',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      subtitle: const Text(
                        'Tu potencia, tu ritmo. Control manual opcional.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: session.loading ? null : openTraining,
                    ),
                  ),
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(20),
                      leading: const Icon(Icons.tune, color: emerald, size: 32),
                      title: const Text('Control manual 1.3'),
                      subtitle: const Text(
                        'Sesión supervisada 0/+0,5 % · duración a tu cargo',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: session.loading
                          ? null
                          : () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => ManualRidePage(
                                  controller: session.training,
                                  lowLoad: true,
                                  device: session.selected.toJson(),
                                ),
                              ),
                            ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(20),
                      leading: const Icon(
                        Icons.timer_outlined,
                        color: emerald,
                        size: 32,
                      ),
                      title: const Text(
                        'Sesiones de spinning',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      subtitle: const Text(
                        'Guías de 15–30 min · Sin resistencia automática',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              SpinningProgramsPage(session: session),
                        ),
                      ),
                    ),
                  ),
                  const Card(
                    child: ListTile(
                      contentPadding: EdgeInsets.all(20),
                      leading: Icon(Icons.route_outlined),
                      title: Text('Rutas GPX'),
                      subtitle: Text('Próximamente'),
                      trailing: Chip(label: Text('Pronto')),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'La conexión no activa la resistencia. Cada prueba requiere tu confirmación.',
                      textAlign: TextAlign.center,
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
          Text(
            connectionLabel(state),
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
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
