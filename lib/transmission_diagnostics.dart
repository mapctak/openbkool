import 'package:flutter/material.dart';

import 'slope_presentation.dart';

class TransmissionDiagnostics extends StatelessWidget {
  const TransmissionDiagnostics({super.key, required this.report});
  final Map<String, Object?> report;
  @override
  Widget build(BuildContext context) {
    final audit = report['transmissionDiagnostics'] as Map?;
    if (audit == null) return const SizedBox.shrink();
    final manual = audit['lastManualOrder'] as Map?;
    final stop = audit['lastStopCommand'] as Map?;
    String percent(Map? entry) =>
        '${SlopePresentation.percent(entry?['requestedPercent'] as num?)} %';
    return ExpansionTile(
      title: const Text('Diagnóstico de transmisión ANT'),
      children: [
        Text('Última pendiente ordenada (API): ${percent(manual)}'),
        Text(
          'Última solicitud de parada: ${stop == null ? 'sin intento de envío' : percent(stop)}',
        ),
        Text(
          'Resultado API de parada: ${stop?['event'] ?? 'ninguno'} · ${audit['stopResult'] ?? 'pendiente'}',
        ),
        Text(
          'Canal utilizable: ${audit['channelUsable'] == true ? 'sí' : 'no'} · CHANNEL_CLOSED observado: ${audit['channelClosedEventAtMs'] != null ? 'sí' : 'no'}',
        ),
        Text(
          'Eventos TX observados: ${audit['txEventCount'] ?? 0}. No identifican qué pendiente llegó al rodillo.',
        ),
        const Text(
          'Resistencia física desconocida. Retorno de API, evento TX y cierre no confirman aplicación ni resistencia cero.',
        ),
      ],
    );
  }
}
