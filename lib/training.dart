import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ant_trainer_search.dart';

class TrainingPage extends StatefulWidget {
  const TrainingPage({
    super.key,
    required this.controller,
    this.searchController,
    this.onExport,
  });
  final AntTrainerSearchController controller;

  final AntTrainerSearchController? searchController;
  final Future<void> Function()? onExport;
  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  Map<String, Object?> selected = const {
    'protocol': 'BKOOL_V1_PUBLIC',
    'deviceNumber': 30064,
    'deviceType': 112,
    'transmissionType': 5,
  };
  String keyOf(Map d) =>
      '${d['deviceNumber']}:${d['deviceType']}:${d['transmissionType']}';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final r = c.snapshot;
      final choices = <String, Map<String, Object?>>{keyOf(selected): selected};
      for (final value
          in widget.searchController?.snapshot['devices'] as List? ??
              const []) {
        final d = Map<String, Object?>.from(value as Map);
        if (d['protocol'] == 'BKOOL_V1_PUBLIC' &&
            d['deviceType'] == 112 &&
            d['transmissionType'] != null) {
          choices[keyOf(d)] = d;
        }
      }
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
                'BKOOL_V1_PUBLIC · telemetría y preparación de conexión. Los comandos permanecen bloqueados.',
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
                    : () => c.start('training', device: selected),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar entrenamiento'),
              ),
              OutlinedButton.icon(
                onPressed: c.running && !c.commandBusy ? c.stop : null,
                icon: const Icon(Icons.stop),
                label: const Text('Finalizar entrenamiento'),
              ),
              if (widget.searchController != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text('1. Buscar rodillos ANT'),
                  onPressed: c.running || c.commandBusy
                      ? null
                      : () async {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => AntTrainerSearchPage(
                                controller: widget.searchController!,
                                onExport: widget.onExport ?? () async {},
                              ),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                ),
              DropdownButtonFormField<String>(
                initialValue: keyOf(selected),
                decoration: const InputDecoration(
                  labelText: '2. Seleccionar rodillo (ID / tipo / transmisión)',
                ),
                items: [
                  for (final e in choices.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.key)),
                ],
                onChanged: c.running || c.commandBusy
                    ? null
                    : (value) => setState(() => selected = choices[value]!),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('3. Conectar y entrenar (sin comandos)'),
                onPressed: c.running || c.commandBusy
                    ? null
                    : () => c.start('training_connected', device: selected),
              ),
              Text(
                'Canal: ${r['channelMode'] ?? 'sin abrir'} · identidad: ${r['connectionState'] ?? 'sin verificar'}',
              ),
              const Text(
                'Control manual de pendiente: deshabilitado en esta versión',
              ),
              const Slider(
                value: 0,
                min: 0,
                max: 1,
                divisions: 100,
                label: '0 %',
                onChanged: null,
              ),
              const FilledButton(
                onPressed: null,
                child: Text('Aplicar pendiente (bloqueado)'),
              ),
              const Text(
                'Cerrar el canal NO garantiza resistencia cero. Para detenerte, deja de pedalear antes de desmontar. No se transmite ninguna orden de parada.',
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
