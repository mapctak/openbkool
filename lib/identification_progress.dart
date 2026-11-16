import 'package:flutter/material.dart';

/// Displays native monotonic timings. Never infers identity from a saved trainer.
class IdentificationProgress extends StatelessWidget {
  const IdentificationProgress({super.key, required this.report});
  final Map<String, Object?> report;
  @override
  Widget build(BuildContext context) {
    final timing = report['identificationTiming'] as Map?;
    if (timing == null) return const SizedBox.shrink();
    final marks = timing['milestonesMs'] as Map? ?? const {};
    String seconds(Object? ms) => ms is num
        ? '${(ms / 1000).toStringAsFixed(1).replaceAll('.', ',')} s'
        : 'pendiente';
    final waiting = timing['waiting'] == true;
    final reason = timing['waitingReason'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (waiting && reason != null) ...[
          Text(
            'Bloqueo: $reason',
            key: const ValueKey('identificationBlocker'),
          ),
          Text(
            'Esperando esta condición: ${seconds(timing['waitingForConditionMs'])} · Desde apertura: ${seconds(timing['waitingSinceChannelOpenMs'])}',
            key: const ValueKey('identificationWait'),
          ),
        ],
        const Text('Tiempos desde el inicio de esta conexión:'),
        Text(
          'Canal abierto: ${seconds(marks['channelOpen'])} · Primera telemetría: ${seconds(marks['firstTelemetry'])}',
        ),
        Text(
          'Identificación 0x50: ${seconds(marks['identificationComplete'])} · Control disponible: ${seconds(marks['controlAvailable'])}',
        ),
        if (waiting && reason == 'manufacturer_model_not_verified')
          const Text(
            'Esperando página 0x50 de esta conexión: fabricante 67 y modelo 22. La página 0x51 no sustituye esa verificación. No se envían solicitudes de identificación sin compatibilidad V1 confirmada.',
          ),
      ],
    );
  }
}
