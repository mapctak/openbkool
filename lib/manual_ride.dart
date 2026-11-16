import 'dart:async';

import 'package:flutter/material.dart';

import 'ant_trainer_search.dart';
import 'manual_control_status.dart';
import 'slope_presentation.dart';
import 'training.dart';
import 'trainer_session.dart';

/// Same half-point domain as the original UI; no physical capability assertion.
final manualRideSlopes = List<double>.unmodifiable(
  List.generate(41, (i) => -5 + i * 0.5),
);

String ridePercent(num? value) => value == null
    ? '— %'
    : '${value > 0 ? '+' : ''}${value.toStringAsFixed(1).replaceAll('.', ',')} %';

class ManualRidePage extends StatefulWidget {
  const ManualRidePage({
    super.key,
    required this.controller,
    required this.device,
    this.refreshTrial = false,
    this.lowLoad = false,
  });
  final AntTrainerSearchController controller;
  final Map<String, Object?> device;
  final bool refreshTrial, lowLoad;

  @override
  State<ManualRidePage> createState() => _ManualRidePageState();
}

class _ManualRidePageState extends State<ManualRidePage>
    with WidgetsBindingObserver {
  double selected = 0;
  String? sessionId;
  bool backgroundStopRequested = false;
  late bool lowLoad;
  String get mode => widget.refreshTrial
      ? 'refresh_trial_30s'
      : lowLoad
      ? 'manual_low_load'
      : 'manual_session';
  String get policyKey => widget.refreshTrial
      ? 'refreshTrialPolicy'
      : lowLoad
      ? 'lowLoadPolicy'
      : 'manualSessionPolicy';
  List<double> get slopes =>
      widget.refreshTrial || lowLoad ? const [0, 0.5] : manualRideSlopes;

  @override
  void initState() {
    super.initState();
    lowLoad = widget.lowLoad && !widget.refreshTrial;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller.running && !backgroundStopRequested) {
      unawaited(widget.controller.stop(reason: 'screen_closed'));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      backgroundStopRequested = false; // Never arm, resume or send here.
    } else if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        widget.controller.running &&
        !backgroundStopRequested) {
      backgroundStopRequested = true;
      unawaited(widget.controller.stop(reason: 'app_background'));
    }
  }

  bool get usable {
    final c = widget.controller;
    final m = c.snapshot['manualControl'] as Map? ?? const {};
    return c.running &&
        (c.snapshot[policyKey] as Map?)?['physicalEnabled'] == true &&
        m['mode'] == mode &&
        m['enabled'] == true &&
        m['eligible'] == true &&
        !c.commandBusy &&
        !c.manualStopping &&
        !c.controlTransportUncertain &&
        (!widget.refreshTrial ||
            (m['remainingMs'] is num && (m['remainingMs'] as num) > 0));
  }

  Future<void> request(double value) async {
    if (!usable || !slopes.contains(value)) return;
    setState(() => selected = value);
    await widget.controller.manualAction(
      'setManualSlope',
      percent: value,
      expectedSessionId: sessionId,
    );
  }

  Future<void> authorizeSession() async {
    final c = widget.controller;
    final policy = c.snapshot[policyKey] as Map? ?? const {};
    if (policy['physicalEnabled'] != true) return;
    final sid = sessionId;
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          widget.refreshTrial
              ? 'Autorizar ensayo de reenvío'
              : lowLoad
              ? 'Autorizar sesión supervisada'
              : 'Iniciar control manual',
        ),
        content: Text(
          widget.refreshTrial
              ? 'Autorizo este ensayo de 30 segundos, solo 0 % y +0,5 %, con reenvíos del objetivo vigente cada 5 segundos. Activar no transmite. Usaré Detener control para comprobar la parada; si no disminuye la resistencia, dejaré de pedalear según la recuperación ya comprobada. API y TX no confirman aplicación física. No habilita el modo ilimitado.'
              : lowLoad
              ? 'Autorizo una sesión supervisada sin caducidad de 30 s, solo 0 % y +0,5 %, con reenvío cada 5 s. El orden de radio y la resistencia física no están confirmados. Mantendré accesible DETENER CONTROL y la salida independiente del esfuerzo ya comprobada. Detener, perder enlace o pasar a segundo plano finaliza el control; no se reactiva automáticamente. La página 0x11 no certifica resistencia aplicada.'
              : 'Autorizo esta sesión manual de −5 % a +15 %, sin caducidad fija. Las órdenes se refrescan aproximadamente cada 5 segundos. La API no confirma resistencia física. LLANO solicita pendiente cero; Detener finaliza el control sin garantizar resistencia cero.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              widget.refreshTrial
                  ? 'Autorizar ensayo'
                  : lowLoad
                  ? 'Autorizar sesión supervisada'
                  : 'Autorizar sesión',
            ),
          ),
        ],
      ),
    );
    if (consent == true && mounted) {
      await c.manualAction(
        'enableManualTest',
        confirmed: true,
        controlMode: mode,
        experimentalConfirmed: widget.refreshTrial || lowLoad,
        expectedSessionId: sid,
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller, r = c.snapshot;
      final m = r['manualControl'] as Map? ?? const {};
      final t = r['telemetry'] as Map? ?? const {};
      final policy = r[policyKey] as Map? ?? const {};
      final nativeAllowed = policy['physicalEnabled'] == true;
      final slope = SlopePresentation.fromReport(r);
      final activation = ManualActivationStatus.fromReport(
        r,
        commandBusy: c.commandBusy,
        stopping: c.manualStopping,
      );
      if (sessionId != r['sessionId']) {
        sessionId = r['sessionId'] as String?;
        selected = 0;
      }
      final elapsed =
          ((t['elapsedMs'] ?? m['elapsedControlMs'] ?? 0) as num).toInt() ~/
          1000;
      String metric(String key, String unit, [int decimals = 0]) {
        final value = t[key];
        return '${value is num ? value.toStringAsFixed(decimals) : '—'} $unit';
      }

      final active = m['enabled'] == true && m['mode'] == mode;
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
          appBar: AppBar(
            title: Text(
              widget.refreshTrial ? 'Reenvío y parada ANT' : 'Control manual',
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: usable && selected > slopes.first
                              ? () => request(selected - 0.5)
                              : null,
                          child: const Text(
                            '−',
                            style: TextStyle(fontSize: 30),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: usable ? () => request(0) : null,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text('LLANO 0 %'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: usable && selected < slopes.last
                              ? () => request(selected + 0.5)
                              : null,
                          child: const Text(
                            '+',
                            style: TextStyle(fontSize: 30),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        padding: const EdgeInsets.all(18),
                      ),
                      onPressed: c.running && !c.manualStopping
                          ? () => c.manualAction(
                              'stopManualTest',
                              expectedSessionId: sessionId,
                            )
                          : null,
                      icon: const Icon(Icons.stop_circle),
                      label: const Text('DETENER CONTROL'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!widget.refreshTrial)
                SwitchListTile(
                  key: const ValueKey('lowLoadProfile'),
                  title: const Text('Sesión supervisada 0/+0,5 %'),
                  subtitle: const Text(
                    'Sin límite fijo de duración. Desactivar solo previsualiza el rango original bloqueado.',
                  ),
                  value: lowLoad,
                  onChanged:
                      m['enabled'] == true || c.commandBusy || c.manualStopping
                      ? null
                      : (value) {
                          setState(() {
                            lowLoad = value;
                            selected = 0;
                          });
                        },
                ),
              if (lowLoad)
                const Text(
                  'Sesión prolongada supervisada · máximo +0,5 %. Orden de radio y aplicación física no confirmados. El rango completo permanece bloqueado.',
                ),
              if (!nativeAllowed)
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      lowLoad
                          ? 'Conecta el rodillo y espera las validaciones actuales del enlace antes de autorizar la sesión supervisada.'
                          : 'Preparado, bloqueado para uso físico. Falta validar la parada con reenvíos y el comportamiento del búfer ANT: no está garantizado que un incremento anterior no llegue después de solicitar cero.',
                    ),
                  ),
                ),
              Text(
                'Conexión: ${connectionLabel(connectionFor(r, SavedTrainer.fromMap(widget.device)))} · Control: ${switch (m['state']) {
                  'available' => 'Disponible',
                  'active' => 'Activo',
                  'stopping' => 'Deteniendo',
                  'stopped' => 'Detenido',
                  'error' => 'Error',
                  _ => 'Inactivo',
                }}',
              ),
              Text('Pendiente seleccionada: ${ridePercent(selected)}'),
              Text(
                'Pendiente ordenada: ${ridePercent(slope.apiPercent)}',
                style: Theme.of(context).textTheme.headlineMedium,
                key: const ValueKey('manualRideOrdered'),
              ),
              Text(slope.apiStatus),
              if (slope.apiError != null)
                Text(
                  slope.apiError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Text('Parada: ${slope.stopStatus ?? 'sin solicitud'}'),
              Text(
                widget.refreshTrial
                    ? 'API y eventos TX no confirman entrega ni aplicación física de un payload concreto.'
                    : 'Aplicación física no confirmada. Una pendiente negativa no implica impulso ni aceleración de la rueda.',
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        metric('powerW', 'W'),
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      Text(
                        '${metric('speedKmh', 'km/h', 1)} · ${metric('cadenceRpm', 'RPM')}',
                      ),
                      Text(
                        'Tiempo: ${elapsed ~/ 3600}:${((elapsed ~/ 60) % 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}',
                      ),
                    ],
                  ),
                ),
              ),
              DropdownButton<double>(
                key: const ValueKey('manualRideSlope'),
                isExpanded: true,
                value: selected,
                items: [
                  for (final value in slopes)
                    DropdownMenuItem(
                      value: value,
                      child: Text(ridePercent(value)),
                    ),
                ],
                onChanged: c.commandBusy || c.manualStopping
                    ? null
                    : (value) {
                        if (value == null) return;
                        if (active) {
                          unawaited(request(value));
                        } else {
                          setState(() => selected = value);
                        }
                      },
              ),
              Text(
                widget.refreshTrial
                    ? 'Ensayo acotado: máximo 30 s, solo 0 % y +0,5 %. Refresco aproximado de 5 s; no es un watchdog. Activar no transmite.'
                    : lowLoad
                    ? 'Solo 0 % y +0,5 %. Refresco cada 5 s; termina con DETENER CONTROL, pérdida de enlace o segundo plano. No hay reactivación automática ni caducidad de 30 s.'
                    : 'Rango de codificación original −5 % a +15 %. Respuesta física comunicada: 0 %, +0,5 %, +1 %, +2 % y +3 %. El selector en reposo solo previsualiza; no transmite.',
              ),
              if (widget.refreshTrial) ...[
                Text(
                  'Tiempo restante: ${m['remainingMs'] is num ? '${((m['remainingMs'] as num) / 1000).ceil()} s' : 'sin iniciar'}',
                ),
                FilledButton(
                  onPressed: usable ? () => request(0.5) : null,
                  child: const Text('Solicitar +0,5 %'),
                ),
                const Text(
                  'Detener invalida el objetivo y cancela refrescos. Las llamadas ya iniciadas y el búfer de radio no pueden retirarse de forma verificada.',
                ),
              ],
              if (!c.running)
                FilledButton.icon(
                  onPressed: c.commandBusy
                      ? null
                      : () => c.start(
                          'training_connected',
                          device: widget.device,
                        ),
                  icon: const Icon(Icons.link),
                  label: const Text('Conectar rodillo'),
                ),
              FilledButton(
                onPressed:
                    nativeAllowed &&
                        activation.canChange &&
                        m['enabled'] != true
                    ? authorizeSession
                    : null,
                child: Text(
                  widget.refreshTrial
                      ? 'Preparar ensayo de 30 s'
                      : lowLoad
                      ? 'Iniciar sesión supervisada'
                      : 'Autorizar sesión manual',
                ),
              ),
              if (nativeAllowed)
                Text(
                  active
                      ? 'Control activo. Usa DETENER CONTROL para finalizar.'
                      : activation.message,
                ),
              OutlinedButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        TrainingPage(controller: c, stopOnExit: false),
                  ),
                ),
                child: const Text('Registros JSON, CSV y diagnóstico'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
