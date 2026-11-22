import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'trainer_session.dart';
import 'workout_summary.dart';

final trainingSlopes = List<double>.unmodifiable(
  List.generate(41, (index) => -5 + index * 0.5),
);

String slopeLabel(num? value) => value == null
    ? '—'
    : '${value > 0 ? '+' : ''}${value.toStringAsFixed(1).replaceAll('.', ',')} %';

class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key, required this.session});

  final TrainerSession session;

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  double selected = 0;
  String? sessionId;

  Future<void> authorize(String id) async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Autorizar control de pendiente'),
        content: const Text(
          'Autorizo el rango de −5 % a +15 % para esta sesión. Las pendientes '
          'negativas y superiores a +3 % son experimentales. La respuesta física '
          'no está verificada para los 41 valores. Mantendré la app visible. '
          'La API y una solicitud de 0 % no garantizan la resistencia del rodillo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Autorizar sesión'),
          ),
        ],
      ),
    );
    if (consent == true && mounted) {
      await widget.session.training.authorizeControl(id);
    }
  }

  void request(double percent, {bool rapid = false}) {
    setState(() => selected = percent);
    unawaited(
      widget.session.training.requestSlope(
        percent,
        rapidAdjustment: rapid,
        sessionId: sessionId,
      ),
    );
  }

  Future<void> export({required bool csv}) async {
    final controller = widget.session.training;
    final id = controller.snapshot['sessionId'] as String?;
    if (id == null) return;
    final finalized = !controller.running;
    try {
      final report = csv
          ? null
          : await controller.exportJson(id, finalized: finalized);
      final data = csv
          ? await controller.exportCsv(id)
          : report == null
          ? null
          : const JsonEncoder.withIndent('  ').convert(report);
      if (data == null) throw StateError('Registro no disponible');
      await Clipboard.setData(ClipboardData(text: data));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              csv
                  ? 'CSV final copiado'
                  : 'JSON ${report?['recordState'] == 'final' ? 'final' : 'parcial'} copiado',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo exportar: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      final c = widget.session.training;
      final report = c.snapshot;
      final manual = report['manualControl'] as Map? ?? const {};
      final id = report['sessionId'] as String?;
      if (sessionId != id) {
        sessionId = id;
        selected = (manual['lastRequestedPercent'] as num?)?.toDouble() ?? 0;
        if (!trainingSlopes.contains(selected)) selected = 0;
      }
      final available =
          c.running &&
          id != null &&
          manual['eligible'] == true &&
          !c.manualStopping &&
          !c.controlTransportUncertain;
      final blocked = manual['unavailableReason'] as String?;
      final enabled = manual['enabled'] == true;
      final identification = report['identificationTiming'] as Map? ?? const {};
      final clientEvents = report['clientManualChanges'] as List? ?? const [];
      final lastClientEvent = clientEvents.isEmpty
          ? null
          : clientEvents.last as Map;
      final usable = available && enabled && c.acceptingManualChanges;
      final pending = c.pendingManualPercent;
      final accepted =
          (manual['lastManualApiSuccess'] as Map?)?['requestedPercent'] as num?;
      return PopScope(
        canPop: !c.running && !c.commandBusy,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop || c.manualStopping) return;
          await c.stop(reason: 'screen_closed');
          if (context.mounted && !c.running && !c.commandBusy) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('ENTRENAMIENTO LIBRE')),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: c.running && !c.manualStopping ? c.stop : null,
              icon: const Icon(Icons.stop),
              label: const Text('DETENER ENTRENAMIENTO'),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Entrena con OpenBkool visible. Bloquear la pantalla o cambiar de app detiene la sesión.',
              ),
              if (!c.running)
                FilledButton(
                  onPressed: widget.session.loading || widget.session.locked
                      ? null
                      : widget.session.connect,
                  child: const Text('Conectar rodillo por ANT'),
                ),
              if (c.running && !enabled && manual['stopped'] != true)
                FilledButton(
                  onPressed: available && !c.commandBusy
                      ? () => authorize(id)
                      : null,
                  child: const Text('Autorizar rango completo'),
                ),
              if (c.running && manual['state'] == 'suspended')
                const Text(
                  'Control suspendido por telemetría parcial. Vuelve a conectar para autorizar otra sesión.',
                )
              else if (c.running &&
                  blocked == 'manufacturer_model_not_verified')
                Text(
                  identification['manufacturerWaitLong'] == true
                      ? 'La identificación está tardando. Seguimos esperando una página 0x50 válida (fabricante 67, modelo 22).'
                      : 'Esperando fabricante y modelo del rodillo (página 0x50).',
                )
              else if (c.running && !available && blocked != null)
                Text('Control bloqueado · $blocked'),
              DropdownButton<double>(
                key: const ValueKey('trainingSlope'),
                isExpanded: true,
                value: selected,
                items: [
                  for (final value in trainingSlopes)
                    DropdownMenuItem(
                      value: value,
                      child: Text(slopeLabel(value)),
                    ),
                ],
                onChanged: usable
                    ? (value) {
                        if (value != null) request(value);
                      }
                    : null,
              ),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: usable && selected > -5
                        ? () => request(selected - 0.5, rapid: true)
                        : null,
                    child: const Text('−'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: usable ? () => request(0) : null,
                      child: const Text('LLANO 0 %'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: usable && selected < 15
                        ? () => request(selected + 0.5, rapid: true)
                        : null,
                    child: const Text('+'),
                  ),
                ],
              ),
              Text('Pendiente seleccionada · ${slopeLabel(selected)}'),
              if (pending != null)
                Text('Cambio pendiente · ${slopeLabel(pending)}'),
              Text(
                'Última pendiente aceptada por la API · ${slopeLabel(accepted)}',
              ),
              if (selected < 0 || selected > 3)
                const Text('Pendiente experimental'),
              if (lastClientEvent?['event'] == 'rejected_flat_pending')
                const Text(
                  'LLANO sigue pendiente. Espera su envío antes de solicitar otra pendiente.',
                ),
              if (manual['lastManualRejection'] case final Map rejection)
                Text(
                  rejection['requestedPercent'] == 0 &&
                          rejection['reason'] != 'flat_pending'
                      ? 'LLANO no se pudo enviar · ${rejection['reason']}'
                      : 'Orden rechazada · ${rejection['reason']}',
                ),
              if (manual['lastApiError'] case final Map error)
                Text(
                  error['requestedPercent'] == 0 && error['stopRequest'] != true
                      ? 'LLANO no se pudo confirmar en la API ANT · ${error['error']}'
                      : 'Error ANT · ${error['error']}',
                ),
              if (report['clientError'] case final String error) Text(error),
              if (manual['stopReason'] case final String reason)
                Text(
                  'Motivo de parada · ${reason == 'app_background' ? 'app en segundo plano' : reason}',
                ),
              if (manual['stopResult'] == 'zero_api_returned_unconfirmed')
                const Text(
                  '0 % solicitado al detener. Resistencia física sin confirmar.',
                ),
              WorkoutSummary(report: report, trainer: widget.session.selected),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: !c.running && report['csvFile'] != null
                        ? () => export(csv: true)
                        : null,
                    child: const Text('Copiar CSV'),
                  ),
                  TextButton(
                    onPressed: id != null ? () => export(csv: false) : null,
                    child: Text(
                      c.running ? 'Copiar JSON parcial' : 'Copiar JSON',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
