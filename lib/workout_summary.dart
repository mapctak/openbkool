import 'package:flutter/material.dart';

import 'trainer_session.dart';

class WorkoutSummary extends StatelessWidget {
  const WorkoutSummary({
    super.key,
    required this.report,
    required this.trainer,
  });
  final Map<String, Object?> report;
  final SavedTrainer trainer;
  @override
  Widget build(BuildContext context) {
    final t = report['telemetry'] as Map? ?? const {};
    String value(String key, int decimals) => t[key] is num
        ? (t[key] as num).toStringAsFixed(decimals).replaceAll('.', ',')
        : '—';
    final ms = (t['elapsedMs'] as num?)?.toInt() ?? 0;
    final seconds = ms ~/ 1000;
    final elapsed =
        '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    final state = connectionFor(report, trainer);
    final metrics = [
      ('Cadencia', '${value('cadenceRpm', 0)} RPM'),
      ('Velocidad', '${value('speedKmh', 1)} km/h'),
      (
        'Distancia',
        t['distanceM'] is num
            ? '${((t['distanceM'] as num) / 1000).toStringAsFixed(2).replaceAll('.', ',')} km'
            : '— km',
      ),
      ('Tiempo de sesión', elapsed),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (report['running'] != true && t.isNotEmpty)
          const Text('Últimos datos de la sesión'),
        Row(
          children: [
            const Icon(Icons.directions_bike, color: Color(0xFF008F70)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                trainer.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Chip(label: Text(connectionLabel(state))),
          ],
        ),
        Card(
          color: const Color(0xFF008F70),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Text(
                  'POTENCIA',
                  style: TextStyle(
                    color: Colors.white,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value('powerW', 0),
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  'W',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
              ],
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in metrics)
                SizedBox(
                  width: (box.maxWidth - 8) / 2,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.$1),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              m.$2,
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (t['distancePartial'] == true)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Distancia parcial: hubo interrupciones en la recepción.',
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class ManualOrderSummary extends StatelessWidget {
  const ManualOrderSummary({super.key, required this.report});
  final Map<String, Object?> report;
  @override
  Widget build(BuildContext context) {
    final manual = report['manualControl'] as Map? ?? const {};
    num? requested;
    String? api;
    num? apiPercent;
    for (final event in report['manualControlEvents'] as List? ?? const []) {
      if ((event['event'] == 'request' || event['event'] == 'api_attempt') &&
          event['requestedPercent'] is num) {
        requested = event['requestedPercent'] as num;
      }
      if (event['event'] == 'api_returned' || event['event'] == 'api_error') {
        api = event['event'] as String;
        apiPercent = event['requestedPercent'] as num?;
      }
    }
    final percent = requested ?? manual['lastSubmittedPercent'] as num?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pendiente solicitada: ${percent == null ? '—' : percent.toStringAsFixed(1).replaceAll('.', ',')} %',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              api == 'api_returned'
                  ? 'Orden enviada a la API ANT: ${apiPercent?.toStringAsFixed(1).replaceAll('.', ',') ?? '—'} %'
                  : api == 'api_error'
                  ? 'Error al enviar la orden a ANT'
                  : 'Sin orden enviada a ANT',
            ),
            if ((manual['lastResult'] as Map?)?['event'] == 'rejected')
              const Text(
                'Última solicitud rechazada; no se ha enviado esa orden.',
              ),
            const Text('Aplicación física no confirmada por el protocolo.'),
          ],
        ),
      ),
    );
  }
}
