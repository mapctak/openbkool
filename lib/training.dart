import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ant_trainer_search.dart';
import 'manual_control_status.dart';
import 'trainer_session.dart';
import 'workout_summary.dart';

class TrainingPage extends StatefulWidget {
  const TrainingPage({
    super.key,
    required this.controller,
    this.searchController,
    this.onExport,
    this.simple = false,
    this.stopOnExit = true,
    this.initialDevice,
    this.onDeviceSelected,
  });
  final bool simple, stopOnExit;
  final Map<String, Object?>? initialDevice;
  final Future<void> Function(Map<String, Object?>)? onDeviceSelected;
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
  @override
  void initState() {
    super.initState();
    if (widget.initialDevice != null) {
      selected = Map<String, Object?>.from(widget.initialDevice!);
    }
  }

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
      final manual = r['manualControl'] as Map? ?? const {};
      final enabled = manual['enabled'] == true;
      final activation = ManualActivationStatus.fromReport(
        r,
        commandBusy: c.commandBusy,
        stopping: c.manualStopping,
      );
      final link = manual['link'] as Map? ?? const {};
      final channelIdentity = r['channelIdentity'] as Map? ?? const {};
      String identity(Object? value) => value is Map
          ? '${value['deviceNumber']}/${value['deviceType']}/${value['transmissionType']}'
          : 'pendiente';
      final sessionId = r['sessionId'] as String?;
      final submitted =
          (manual['lastSubmittedPercent'] as num?)?.toDouble() ?? 0;
      final remaining = ((manual['remainingMs'] as num?)?.toInt() ?? 0) ~/ 1000;
      String number(String key, int decimals) =>
          t[key] is num ? (t[key] as num).toStringAsFixed(decimals) : '—';
      final signal = switch (t['signal']) {
        'receiving' => 'Recibiendo',
        'signal_lost' => 'Señal perdida: datos no disponibles',
        'disconnected' => 'Rodillo desconectado',
        _ => 'Esperando al rodillo (hasta 30 s)',
      };
      return PopScope(
        canPop: !widget.stopOnExit || (!c.running && !c.commandBusy),
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          await c.stop();
          if (context.mounted && !c.running) Navigator.of(context).pop();
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              widget.simple ? 'Entrenamiento libre' : 'Entrenamiento',
            ),
          ),
          bottomNavigationBar:
              c.running && (enabled || manual['everEnabled'] == true)
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton.icon(
                      onPressed: manual['stopped'] == true || c.manualStopping
                          ? null
                          : () => c.manualAction(
                              'stopManualTest',
                              expectedSessionId: sessionId,
                            ),
                      icon: const Icon(Icons.stop_circle),
                      label: const Text('Detener prueba'),
                    ),
                  ),
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.simple && c.commandBusy)
                const LinearProgressIndicator(),
              if (widget.simple)
                WorkoutSummary(
                  report: r,
                  trainer: SavedTrainer.fromMap(selected),
                ),
              if (!widget.simple) ...[
                const Text(
                  'BKOOL_V1_PUBLIC · telemetría. Control solo para 30064/112/5, modelo 22, tras activación explícita.',
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
              ],
              if (!widget.simple || !c.running)
                FilledButton.icon(
                  onPressed: c.running || c.commandBusy
                      ? null
                      : () => c.start('training_connected', device: selected),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar entrenamiento'),
                ),
              OutlinedButton.icon(
                onPressed: c.running && !c.commandBusy ? c.stop : null,
                icon: const Icon(Icons.stop),
                label: const Text('Finalizar entrenamiento'),
              ),
              if (!widget.simple) ...[
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
                    labelText:
                        '2. Seleccionar rodillo (ID / tipo / transmisión)',
                  ),
                  items: [
                    for (final e in choices.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.key)),
                  ],
                  onChanged: c.running || c.commandBusy
                      ? null
                      : (value) async {
                          final device = choices[value]!;
                          try {
                            await widget.onDeviceSelected?.call(device);
                            if (mounted) setState(() => selected = device);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.link),
                  label: const Text('Solo telemetría (sin control)'),
                  onPressed: c.running || c.commandBusy
                      ? null
                      : () => c.start('training', device: selected),
                ),
                Text(
                  'Canal: ${r['channelMode'] ?? 'sin abrir'} · identidad: ${r['connectionState'] ?? 'sin verificar'}',
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Control manual',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Prueba limitada a 30 s y a 0–1 %. La recepción de telemetría permanece activa.',
              ),
              CheckboxListTile(
                title: const Text('Habilitar prueba de resistencia'),
                value: enabled,
                onChanged: activation.canChange
                    ? (value) async {
                        if (value != true) {
                          await c.manualAction(
                            'stopManualTest',
                            expectedSessionId: sessionId,
                          );
                          return;
                        }
                        final accepted = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Activar control real ANT'),
                            content: const Text(
                              'Se podrán enviar pendientes 0 %, 0,5 % y 1 % al rodillo 30064/112/5. Detener intentará solicitar 0 % antes de cerrar, sin garantizar su aplicación ni una resistencia segura. Si hay una reacción inesperada, deja de pedalear y espera a que se detenga la rueda. La activación caduca en 30 segundos.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Habilitar prueba'),
                              ),
                            ],
                          ),
                        );
                        if (accepted == true && mounted) {
                          await c.manualAction(
                            'enableManualTest',
                            confirmed: true,
                            expectedSessionId: sessionId,
                          );
                        }
                      }
                    : null,
              ),
              Text(
                widget.simple
                    ? activation.message
                    : '${activation.canChange ? 'Estado' : 'Activación bloqueada'} [${activation.code}]: ${activation.message}',
                key: const ValueKey('manualActivationReason'),
              ),
              if (!widget.simple)
                Text(
                  'Diagnóstico de control v2 · Kotlin: ${r['controlDiagnosticsVersion'] ?? 'pendiente'}',
                ),
              if (!widget.simple)
                ExpansionTile(
                  title: const Text('Condiciones actuales de seguridad'),
                  children: [
                    SelectableText(
                      'Sesión: ${sessionId ?? 'sin confirmar'}\n'
                      'ID seleccionado: ${identity(channelIdentity['selected'])}\n'
                      'ID configurado: ${identity(channelIdentity['configured'])}\n'
                      'ID leído del adaptador: ${identity(channelIdentity['adapterReadback'])}\n'
                      'ID recibido: ${identity(channelIdentity['lastReceived'])} · coincidencia completa: ${channelIdentity['allMatch'] ?? 'pendiente'}\n'
                      'Error al leer ID del canal: ${channelIdentity['readbackError'] ?? 'ninguno'}\n'
                      'Canal: ${r['channelMode'] ?? 'sin abrir'} · identidad: ${r['connectionState'] ?? 'sin verificar'}\n'
                      'Canal específico: ${link['dedicated'] ?? 'sin datos'} · abierto: ${link['channelOpen'] ?? 'sin datos'} · radio disponible: ${link['radioAvailable'] ?? 'sin datos'}\n'
                      'ID verificado: ${link['identityVerified'] ?? 'sin datos'}\n'
                      'Fabricante: ${link['manufacturerId'] ?? 'pendiente'} · modelo: ${link['modelNumber'] ?? 'pendiente'}\n'
                      'Edad de señal: ${link['signalAgeMs'] ?? '-'} ms · telemetría válida: ${link['telemetryFresh'] ?? 'sin datos'}\n'
                      'Bloqueos Kotlin: ${manual['blockingReasons'] ?? manual['unavailableReason'] ?? 'sin datos'}\n'
                      'Operación en curso: ${c.commandBusy} · actualización: ${r['updatedAt'] ?? 'pendiente'}',
                    ),
                  ],
                ),
              if (enabled) Text('Tiempo restante: $remaining s'),
              if (!widget.simple)
                Text(
                  'Última pendiente entregada a la API: ${manual['lastSubmittedPercent'] ?? 'ninguna'} %. Aplicación física SIN confirmar.',
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton(
                    onPressed: enabled && !c.commandBusy && submitted > 0
                        ? () => c.manualAction(
                            'setManualSlope',
                            percent: submitted - 0.5,
                            expectedSessionId: sessionId,
                          )
                        : null,
                    style: widget.simple
                        ? OutlinedButton.styleFrom(
                            minimumSize: const Size(80, 64),
                            textStyle: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                          )
                        : null,
                    child: const Text('−'),
                  ),
                  OutlinedButton(
                    onPressed: enabled && !c.commandBusy
                        ? () => c.manualAction(
                            'setManualSlope',
                            percent: 0,
                            expectedSessionId: sessionId,
                          )
                        : null,
                    style: widget.simple
                        ? OutlinedButton.styleFrom(
                            minimumSize: const Size(80, 64),
                            textStyle: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                          )
                        : null,
                    child: const Text('0 %'),
                  ),
                  OutlinedButton(
                    onPressed: enabled && !c.commandBusy && submitted < 1
                        ? () => c.manualAction(
                            'setManualSlope',
                            percent: submitted + 0.5,
                            expectedSessionId: sessionId,
                          )
                        : null,
                    style: widget.simple
                        ? OutlinedButton.styleFrom(
                            minimumSize: const Size(80, 64),
                            textStyle: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                          )
                        : null,
                    child: const Text('+'),
                  ),
                ],
              ),
              if (widget.simple) ManualOrderSummary(report: r),
              const Text(
                'Detener prueba solicita 0 % solo si la radio sigue disponible y después cierra el canal. Ni enviar 0 % ni cerrar garantizan una resistencia segura. No hay recuperación automática del control: reconecta y habilita una nueva prueba.',
              ),
              if (widget.simple)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => TrainingPage(
                        controller: c,
                        searchController: widget.searchController,
                        initialDevice: selected,
                        stopOnExit: false,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.tune),
                  label: const Text('Diagnóstico detallado del entrenamiento'),
                ),
              if (!widget.simple && manual['lastResult'] != null)
                SelectableText('Resultado: ${manual['lastResult']}'),
              if (!widget.simple)
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await Clipboard.setData(
                        ClipboardData(
                          text: const JsonEncoder.withIndent('  ').convert({
                            ...r,
                            'manualActivationUi': {
                              'code': activation.code,
                              'canChange': activation.canChange,
                              'commandBusy': c.commandBusy,
                              'manualStopping': c.manualStopping,
                            },
                          }),
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Diagnóstico de entrenamiento JSON copiado',
                            ),
                          ),
                        );
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error al exportar JSON: $error'),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Exportar diagnóstico JSON'),
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
              if (!widget.simple)
                Text(
                  'Recursos liberados: ${r['resourcesReleased'] ?? 'sin confirmar'}',
                ),
              if (r['clientError'] != null)
                SelectableText('ERROR: ${r['clientError']}'),
              if (r['csvError'] != null)
                SelectableText('ERROR CSV: ${r['csvError']}'),
              if (!widget.simple)
                for (final e
                    in (r['events'] as List? ?? const []).reversed.take(100))
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
