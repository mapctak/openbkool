import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ant_trainer_search.dart';

class TrainingPage extends StatelessWidget {
  const TrainingPage({super.key, required this.controller});
  final AntTrainerSearchController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller;
      final r = c.snapshot;
      final t = r['telemetry'] as Map? ?? const {};
      String number(String key, int decimals) =>
          t[key] is num ? (t[key] as num).toStringAsFixed(decimals) : '—';
      final signal = switch (t['signal']) {
        'receiving' => 'Recibiendo',
        'signal_lost' => 'Señal perdida: datos no disponibles',
        'disconnected' => 'Rodillo desconectado',
        _ => 'Esperando al rodillo (hasta 30 s)',
      };
      return PopScope(
        canPop: !c.running && !c.commandBusy,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          await c.stop();
          if (context.mounted && !c.running) Navigator.of(context).pop();
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Entrenamiento')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Bkool Smart Pro v1 · ID 30064 · tipo 112 · transmisión 5\nBKOOL_V1_PUBLIC · solo recepción',
              ),
              const SizedBox(height: 16),
              Text(c.running ? signal : 'Estado: ${r['status']}'),
              if (c.commandBusy) const LinearProgressIndicator(),
              for (final metric in [
                ('Velocidad', '${number('speedKmh', 1)} km/h'),
                ('Potencia', '${number('powerW', 0)} W'),
                ('Cadencia', '${number('cadenceRpm', 0)} RPM'),
                ('Distancia recorrida', '${number('distanceM', 0)} m'),
              ])
                Card(
                  child: ListTile(
                    title: Text(metric.$1),
                    trailing: Text(
                      metric.$2,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
              if (t['distancePartial'] == true)
                const Text(
                  'Distancia parcial: hubo una pérdida de señal o un salto ambiguo del contador.',
                ),
              const Text(
                'El primer contador es la referencia de 0 m. Una cifra ausente indica datos desconocidos o antiguos. Mantén la aplicación visible durante el entrenamiento.',
              ),
              FilledButton.icon(
                onPressed: c.running || c.commandBusy
                    ? null
                    : () => c.start('training'),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar entrenamiento'),
              ),
              OutlinedButton.icon(
                onPressed: c.running && !c.commandBusy ? c.stop : null,
                icon: const Icon(Icons.stop),
                label: const Text('Finalizar entrenamiento'),
              ),
              OutlinedButton.icon(
                onPressed: c.running || c.commandBusy || r['csvFile'] == null
                    ? null
                    : () async {
                        try {
                          final csv = await c.channel.invokeMethod<String>(
                            'exportCsv',
                          );
                          if (csv == null) {
                            throw StateError('Registro no disponible');
                          }
                          await Clipboard.setData(ClipboardData(text: csv));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('CSV copiado al portapapeles'),
                              ),
                            );
                          }
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error al exportar CSV: $error'),
                              ),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.copy),
                label: const Text('Exportar CSV al portapapeles'),
              ),
              Text(
                'Recursos liberados: ${r['resourcesReleased'] ?? 'sin confirmar'}',
              ),
              if (r['clientError'] != null)
                SelectableText('ERROR: ${r['clientError']}'),
              if (r['csvError'] != null)
                SelectableText('ERROR CSV: ${r['csvError']}'),
              for (final e in (r['events'] as List? ?? const []).reversed.take(
                100,
              ))
                SelectableText(
                  '${e['timestamp']} [${e['event']}] ${e['message']}',
                ),
            ],
          ),
        ),
      );
    },
  );
}
