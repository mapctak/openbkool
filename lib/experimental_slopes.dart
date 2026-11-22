import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import 'ant_trainer_search.dart';
import 'manual_control_status.dart';
import 'slope_presentation.dart';
import 'transmission_diagnostics.dart';
import 'workout_summary.dart';

/// Offline evidence, not a transport encoder or a firmware capability claim.
class ExperimentalSlopeLevel {
  const ExperimentalSlopeLevel(this.percent, this.hex, this.blockReason);
  final double percent;
  final String hex;
  final String? blockReason;
  bool get physicalEnabled => blockReason == null;
}

const experimentalSlopeLevels = [
  ExperimentalSlopeLevel(0, '33 FF FF FF FF 20 4E FF', null),
  ExperimentalSlopeLevel(0.5, '33 FF FF FF FF 52 4E FF', null),
  ExperimentalSlopeLevel(1, '33 FF FF FF FF 84 4E FF', null),
  ExperimentalSlopeLevel(2, '33 FF FF FF FF E8 4E FF', null),
  ExperimentalSlopeLevel(3, '33 FF FF FF FF 4C 4F FF', null),
  ExperimentalSlopeLevel(
    4,
    '33 FF FF FF FF B0 4F FF',
    'Bloqueado: requiere validar físicamente +3 % y una autorización posterior explícita. Ningún retorno de API lo desbloquea.',
  ),
];
String experimentalPercent(num? n) => n == null
    ? '— %'
    : '${n > 0 ? '+' : ''}${n.toStringAsFixed(1).replaceAll('.', ',')} %';

class ExperimentalSlopesPage extends StatefulWidget {
  const ExperimentalSlopesPage({super.key, required this.controller});
  final AntTrainerSearchController controller;
  @override
  State<ExperimentalSlopesPage> createState() => _ExperimentalSlopesPageState();
}

class _ExperimentalSlopesPageState extends State<ExperimentalSlopesPage> {
  int _level = 1;
  double? _selected;
  Future<void> _request(double percent, String? sessionId) async {
    // Native mode and per-session consent remain authoritative.
    if ((percent != 0 && !experimentalSlopeLevels[_level].physicalEnabled) ||
        percent < 0 ||
        percent > experimentalSlopeLevels[_level].percent ||
        !{
          0.0,
          0.5,
          1.0,
          experimentalSlopeLevels[_level].percent,
        }.contains(percent)) {
      return;
    }
    setState(() => _selected = percent);
    await widget.controller.manualAction(
      'setManualSlope',
      percent: percent,
      expectedSessionId: sessionId,
    );
  }

  Future<void> _activate(String? sessionId) async {
    final level = experimentalSlopeLevels[_level];
    if (!level.physicalEnabled) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Prueba individual ${experimentalPercent(level.percent)}'),
        content: Text(
          level.percent >= 2
              ? 'Preparación experimental de ${experimentalPercent(level.percent)}, máximo 30 s. Todavía no se enviará ninguna pendiente. Se requiere una segunda confirmación de recuperación y autorización.'
              : 'Confirmo la prueba supervisada de un nivel ya validado, máximo 30 s y +1 %. Cero no confirma resistencia neutralizada. Si no percibes reducción, deja de pedalear y espera a que se detenga la rueda; no continúes aumentando.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Activar prueba'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    if (level.percent >= 2) {
      final extra = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text('Autorizar un único +${level.percent.toInt()} %'),
          content: Text(
            'He comprobado en este montaje que puedo dejar de pedalear y esperar estable a que se detenga la rueda sin ayuda de ANT ni del temporizador. Autorizo una única solicitud de +${level.percent.toInt()} %, sin reenvíos, dentro de 30 s. Solicitaré LLANO tras unos 3 s y después Detener control. Si no disminuye, dejaré de pedalear. La resistencia física no está confirmada. No realizaré esta prueba si ha cambiado el montaje o no se cumple la recuperación.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'Confirmar recuperación y autorizar +${level.percent.toInt()} %',
              ),
            ),
          ],
        ),
      );
      if (extra != true || !mounted) return;
    }
    if (mounted) {
      await widget.controller.manualAction(
        'enableManualTest',
        confirmed: true,
        controlMode: level.percent == 3
            ? 'isolated_three_percent'
            : level.percent == 2
            ? 'isolated_two_percent'
            : 'trial_30s',
        experimentalConfirmed: level.percent >= 2,
        expectedSessionId: sessionId,
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller, report = widget.controller.snapshot;
      final manual = report['manualControl'] as Map? ?? const {};
      final slope = SlopePresentation.fromReport(report);
      final status = ManualActivationStatus.fromReport(
        report,
        commandBusy: c.commandBusy,
        stopping: c.manualStopping,
      );
      final enabled = manual['enabled'] == true;
      final sid = report['sessionId'] as String?;
      final level = experimentalSlopeLevels[_level];
      final base = (slope.apiPercent ?? 0).toDouble();
      final remaining = manual['remainingMs'];
      final usable =
          enabled &&
          c.running &&
          manual['eligible'] == true &&
          !c.commandBusy &&
          !c.manualStopping &&
          !c.controlTransportUncertain &&
          remaining is num &&
          remaining > 0;
      return PopScope(
        canPop: !c.running && !c.commandBusy,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          await c.stop(reason: 'screen_closed');
          if (context.mounted && !c.running && !c.commandBusy) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Pendientes experimentales')),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: usable && level.physicalEnabled && base > 0
                        ? () => _request(base > 1 ? 1 : base - 0.5, sid)
                        : null,
                    child: const Text('−'),
                  ),
                  OutlinedButton(
                    onPressed: usable ? () => _request(0, sid) : null,
                    child: const Text('LLANO 0 %'),
                  ),
                  OutlinedButton(
                    onPressed:
                        usable &&
                            level.physicalEnabled &&
                            base < level.percent &&
                            (level.percent <= 1 ||
                                (manual['isolatedTargetAttempted'] != true &&
                                    manual['twoPercentAttempted'] != true &&
                                    manual['threePercentAttempted'] != true))
                        ? () => _request(
                            base == 1 && level.percent >= 2
                                ? level.percent
                                : base + 0.5,
                            sid,
                          )
                        : null,
                    child: const Text('+'),
                  ),
                  FilledButton.icon(
                    onPressed:
                        c.running &&
                            !c.manualStopping &&
                            manual['stopped'] != true
                        ? () => c.manualAction(
                            'stopManualTest',
                            expectedSessionId: sid,
                          )
                        : null,
                    icon: const Icon(Icons.stop_circle),
                    label: const Text('Detener control'),
                  ),
                ],
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...trainingAvailability(report),
              const Text(
                'Pruebas aisladas de +2 % o +3 %: doble confirmación, una única solicitud del nivel y máximo 30 s. +4 % y control continuo bloqueados.',
              ),
              DropdownButtonFormField<int>(
                key: const ValueKey('experimentalLevel'),
                initialValue: _level,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Nivel a evaluar'),
                items: [
                  for (var i = 0; i < experimentalSlopeLevels.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${experimentalPercent(experimentalSlopeLevels[i].percent)}${experimentalSlopeLevels[i].percent >= 2 && experimentalSlopeLevels[i].physicalEnabled
                            ? ' · experimental'
                            : experimentalSlopeLevels[i].physicalEnabled
                            ? ' · validado'
                            : ' · bloqueado'}',
                      ),
                    ),
                ],
                onChanged: enabled || c.commandBusy || c.manualStopping
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _level = value;
                            _selected = experimentalSlopeLevels[value].percent;
                          });
                        }
                      },
              ),
              Text(
                'Pendiente seleccionada: ${experimentalPercent(_selected ?? level.percent)}',
                key: const ValueKey('experimentalSelected'),
              ),
              Text(
                'Última pendiente ordenada: ${experimentalPercent(slope.apiPercent)}',
                key: const ValueKey('experimentalOrdered'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(slope.apiStatus),
              if (manual['lastResult'] is Map)
                Text(
                  'Resultado del controlador: ${(manual['lastResult'] as Map)['event']} · ${(manual['lastResult'] as Map)['reason'] ?? 'sin error declarado'}',
                ),
              if (slope.apiError != null)
                Text(
                  slope.apiError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Text(
                'Enlace: ${report['connectionState'] ?? 'sin conexión'} · Control: ${manual['state'] ?? 'inactivo'}',
              ),
              Text(
                'Tiempo restante: ${remaining is num ? '${(remaining / 1000).ceil()} s' : 'sin iniciar'}',
              ),
              Text('Parada: ${slope.stopStatus ?? 'sin solicitud'}'),
              const Text(
                'Resistencia física no confirmada. API aceptada no significa pendiente aplicada ni resistencia cero.',
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Candidato calculado: ${level.hex}'),
                      const Text(
                        'Representable en el formato; esto no demuestra el rango útil de este firmware.',
                      ),
                      if (level.blockReason != null)
                        Text(
                          level.blockReason!,
                          key: const ValueKey('experimentalBlocker'),
                        ),
                    ],
                  ),
                ),
              ),
              if (!c.running)
                FilledButton.icon(
                  onPressed: c.commandBusy
                      ? null
                      : () => c.start(
                          'training_connected',
                          device: const {
                            'protocol': 'BKOOL_V1_PUBLIC',
                            'deviceNumber': 30064,
                            'deviceType': 112,
                            'transmissionType': 5,
                          },
                        ),
                  icon: const Icon(Icons.link),
                  label: const Text('Conectar 30064/112/5'),
                ),
              FilledButton(
                onPressed: level.physicalEnabled && status.canChange && !enabled
                    ? () => _activate(sid)
                    : null,
                child: const Text('Habilitar prueba de este nivel'),
              ),
              Text(
                level.physicalEnabled
                    ? status.message
                    : 'Activación bloqueada para este nivel.',
              ),
              const Text(
                'Cada prueba de +2 % o +3 % requiere confirmar recuperación y consentimiento. No se combinan niveles experimentales en una sesión. +4 % exige validar físicamente +3 % y una autorización posterior explícita; nunca se desbloquea por un retorno de API.',
              ),
              const Text(
                'Abortar: Detener control intenta un único cero si aún es admisible y cierra. Si no reduce, deja de pedalear y deja detenerse la rueda; no insistas con incrementos ni desconectes deliberadamente para probar.',
              ),
              TransmissionDiagnostics(report: report),
              OutlinedButton(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: const JsonEncoder.withIndent('  ').convert({
                        ...c.snapshot,
                        'experimentalSlopeSelection': {
                          'levelPercent': level.percent,
                          'selectedPercent': _selected,
                          'candidatePayloadHex': level.hex,
                          'physicalEnabled': level.physicalEnabled,
                          'blockReason': level.blockReason,
                        },
                      }),
                    ),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Diagnóstico experimental copiado'),
                      ),
                    );
                  }
                },
                child: const Text('Exportar diagnóstico JSON'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
