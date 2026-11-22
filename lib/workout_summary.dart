import 'package:flutter/material.dart';

import 'trainer_session.dart';
import 'slope_presentation.dart';

class WorkoutSummary extends StatelessWidget {
  const WorkoutSummary({
    super.key,
    required this.report,
    required this.trainer,
    this.slopeIntent,
  });
  final SlopeUiIntent? slopeIntent;
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
        ...trainingAvailability(report),
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
        ManualOrderSummary(report: report, intent: slopeIntent),
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
  const ManualOrderSummary({super.key, required this.report, this.intent});
  final Map<String, Object?> report;
  final SlopeUiIntent? intent;
  @override
  Widget build(BuildContext context) {
    final state = SlopePresentation.fromReport(report, intent: intent);
    final pending = report['clientPendingManualPercent'] as num?;
    return Semantics(
      liveRegion: true,
      child: Card(
        key: const ValueKey('slopeSummary'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Control: ${switch ((report['manualControl'] as Map?)?['state']) {
                  'inactive' => 'Inactivo',
                  'available' => 'Disponible',
                  'active' => 'Activo',
                  'stopping' => 'Deteniendo',
                  'stopped' => 'Detenido',
                  'suspended' => 'Suspendido',
                  'error' => 'Error',
                  _ => 'Esperando estado nativo',
                }}',
                key: const ValueKey('manualControlState'),
              ),
              if (state.trialStatus != null)
                Text(
                  state.trialStatus!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              Text(
                '${state.finished || state.stopping || state.expired ? 'Última pendiente ordenada' : 'Pendiente ordenada'}: ${state.apiPercent != null && state.apiPercent! > 0 ? '+' : ''}${SlopePresentation.percent(state.apiPercent)} %',
                key: const ValueKey('requestedSlope'),
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                'Seleccionada: ${state.requested != null && state.requested! > 0 ? '+' : ''}${SlopePresentation.percent(state.requested)} %',
                key: const ValueKey('selectedSlope'),
              ),
              if (state.finished &&
                  state.stopResult == 'zero_api_returned_unconfirmed')
                const Text(
                  'Control finalizado · Se solicitó 0 % · Resistencia actual desconocida',
                ),
              if (state.pending)
                const Text('Solicitud pendiente de respuesta del controlador.')
              else if (pending != null)
                Text(
                  'Cambio pendiente · ${SlopePresentation.percent(pending)} %',
                ),
              if (state.unrecordedIntent)
                const Text(
                  'Solicitud sin registro en el controlador. Revisa el diagnóstico; no se confirma su envío.',
                ),
              const SizedBox(height: 8),
              Text(state.apiStatus, key: const ValueKey('slopeApiStatus')),
              if (state.apiError != null)
                Text(
                  state.apiError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (state.rejected)
                const Text(
                  'Última solicitud rechazada; no se ha enviado esa orden.',
                ),
              if (state.stopStatus != null) Text(state.stopStatus!),
              if ((report['manualControl'] as Map?)?['state'] == 'error')
                const Text(
                  'Control bloqueado por error · Resistencia física actual desconocida.',
                ),
              const Text('Aplicación física no confirmada por el protocolo.'),
              if (state.finished || state.stopping || state.expired)
                const Text(
                  'No se asume que el rodillo haya vuelto físicamente a 0 %.',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

List<Widget> trainingAvailability(Map<String, Object?> report) {
  if (report['running'] != true) return const [];
  final telemetry = report['telemetry'] as Map?;
  final manual = report['manualControl'] as Map?;
  return [
    if (report['antLink'] == 'receiving') const Text('Conectado por ANT'),
    if (telemetry?['partial'] == true)
      const Text(
        'Telemetría parcial · las métricas ausentes se muestran con —',
      ),
    if (manual?['state'] == 'suspended')
      const Text(
        'Control suspendido · inicia otra conexión para volver a autorizarlo',
      )
    else if (manual?['enabled'] == true)
      const Text('Control autorizado'),
    if (report['backgroundAuthorized'] == true)
      Text(
        report['appInBackground'] == true
            ? 'Sesión activa en segundo plano'
            : 'Sesión en segundo plano habilitada · DETENER en la notificación',
      )
    else
      const Text('Sesión solo en primer plano'),
  ];
}
