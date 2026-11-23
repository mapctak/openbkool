import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'trainer_session.dart';
import 'workout_dashboard.dart';

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

class _TrainingPageState extends State<TrainingPage>
    with WidgetsBindingObserver {
  double selected = 0;
  String? sessionId;

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

  bool starting = false;
  bool pendingEntry = true;
  bool cancelled = false;
  String? announcedSession;
  Timer? startBanner;
  bool showStart = false;
  String? activationAttempt;
  bool checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final session = widget.session;
    if (isActive(session.training.snapshot)) {
      announcedSession = session.training.snapshot['sessionId'] as String;
    }
    session.addListener(scheduleWarmup);
    scheduleWarmup();
    pendingEntry = !session.training.running;
    if (pendingEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || cancelled) return;
        setState(() => pendingEntry = false);
        unawaited(connect());
      });
    }
  }

  @override
  void dispose() {
    startBanner?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(scheduleWarmup);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) scheduleWarmup();
  }

  bool readyForControl(Map<String, Object?> report) =>
      report['running'] == true &&
      report['mode'] != 'training_connection_check' &&
      report['sessionId'] is String &&
      report['trainingServiceActive'] == true &&
      connectionFor(report, widget.session.selected) ==
          TrainerConnection.connected &&
      // Kotlin already checks channel, exact identity, 67/22 and freshness.
      (report['manualControl'] as Map?)?['eligible'] == true &&
      !widget.session.training.manualStopping &&
      !widget.session.training.controlTransportUncertain;

  bool isActive(Map<String, Object?> report) {
    final manual = report['manualControl'] as Map?;
    return readyForControl(report) &&
        manual?['enabled'] == true &&
        manual?['state'] == 'active';
  }

  void scheduleWarmup() {
    if (checking) return;
    checking = true;
    scheduleMicrotask(() {
      checking = false;
      if (mounted) unawaited(checkWarmup());
    });
  }

  Future<void> checkWarmup() async {
    final session = widget.session;
    final c = session.training;
    final report = c.snapshot;
    if (cancelled || session.loading || !readyForControl(report)) return;
    final id = report['sessionId'] as String;
    if (isActive(report)) {
      if (announcedSession == id) return;
      startBanner?.cancel();
      setState(() {
        announcedSession = id;
        showStart = true;
      });
      startBanner = Timer(const Duration(seconds: 5), () {
        setState(() => showStart = false);
      });
    } else if (!c.commandBusy &&
        activationAttempt != id &&
        (report['manualControl'] as Map)['everEnabled'] != true) {
      setState(() => activationAttempt = id);
      await c.activateControl(id);
    }
  }

  Future<void> connect() async {
    final session = widget.session;
    if (starting ||
        session.loading ||
        session.locked ||
        session.preferenceError != null) {
      return;
    }
    setState(() {
      starting = true;
      cancelled = false;
      activationAttempt = null;
      showStart = false;
    });
    try {
      await session.connect();
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Future<void> stop() async {
    setState(() {
      cancelled = true;
      showStart = false;
    });
    final controller = widget.session.training;
    await controller.stop(
      expectedId: controller.snapshot['connectionActionId'] as String?,
    );
  }

  Future<void> retry() async {
    final controller = widget.session.training;
    if (controller.running) {
      await stop();
      if (!mounted ||
          controller.running ||
          controller.controlTransportUncertain) {
        return;
      }
    }
    await connect();
  }

  String? connectionError(Map<String, Object?> report) {
    final session = widget.session;
    if (cancelled &&
        session.training.running &&
        session.training.controlTransportUncertain) {
      return 'No se confirmó la parada. Pulsa Detener para reintentar.';
    }
    if (session.preferenceError != null && !session.training.running) {
      return 'No se pudo leer el rodillo guardado. Revisa Ajustes.';
    }
    final manual = report['manualControl'] as Map?;
    if (session.training.running && manual?['state'] == 'suspended') {
      return 'Control suspendido. Reintenta la conexión.';
    }
    final link = manual?['link'] as Map?;
    final manufacturer = link?['manufacturerId'];
    final model = link?['modelNumber'];
    if (session.training.running &&
        ((manual?['blockingReasons'] as List?)?.contains('wrong_target') ==
                true ||
            (manufacturer != null && manufacturer != 67) ||
            (model != null && model != 22))) {
      return 'Rodillo no compatible con el control. Revisa Ajustes.';
    }
    if (session.connection != TrainerConnection.error) return null;
    if (session.training.running) return 'Señal ANT interrumpida.';
    return switch (report['clientErrorCode']) {
      'training_service_blocked' || 'permission_request_failed' =>
        'Revisa los permisos y las notificaciones de OpenBkool.',
      'training_service_failed' || 'training_not_visible' =>
        'Android no pudo iniciar el servicio de entrenamiento.',
      'ant_busy' => 'ANT está ocupado. Espera a que termine el cierre.',
      _ =>
        report['status'] == 'radio_search_timeout'
            ? 'No se encontró el rodillo guardado.'
            : 'No se pudo conectar. Revisa el rodillo, ANT y los permisos.',
    };
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
        selected =
            (c.pendingManualPercent ?? manual['lastRequestedPercent'] as num?)
                ?.toDouble() ??
            0;
        if (!trainingSlopes.contains(selected)) selected = 0;
      }
      final available = id != null && readyForControl(report) && !cancelled;
      final error = starting && !c.running ? null : connectionError(report);
      final active = available && isActive(report);
      final activationFailed =
          available &&
          !active &&
          (manual['lastResult'] as Map?)?['event'] == 'activation_rejected';
      final warmingUp =
          !cancelled &&
          !active &&
          !c.manualStopping &&
          (pendingEntry || starting || c.running) &&
          error == null;
      final usable = active && c.acceptingManualChanges;
      final telemetry = report['telemetry'] as Map? ?? const {};
      final distance = telemetry['distanceM'] as num?;
      final meters = distance != null && distance.isFinite && distance >= 0
          ? distance.toDouble()
          : 0.0;
      final trainingElapsed = report['trainingElapsedMs'] as num?;
      final elapsed = trainingElapsed ?? (telemetry['elapsedMs'] as num? ?? 0);
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.outlined(
            tooltip: 'Disminuir pendiente',
            onPressed: usable && selected > trainingSlopes.first
                ? () => request(selected - 0.5, rapid: true)
                : null,
            icon: const Icon(Icons.remove, size: 26),
            style:
                IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: dashboardAccent,
                  disabledForegroundColor: const Color(0xff75878a),
                  backgroundColor: const Color(0xff163b34),
                  disabledBackgroundColor: const Color(0xff252e31),
                ).copyWith(
                  side: WidgetStateProperty.resolveWith(
                    (states) => BorderSide(
                      color: states.contains(WidgetState.disabled)
                          ? const Color(0xff384446)
                          : dashboardAccent,
                    ),
                  ),
                ),
          ),
          SizedBox(
            width: 66,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  slopeLabel(selected),
                  key: const ValueKey('trainingSlope'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          IconButton.outlined(
            tooltip: 'Aumentar pendiente',
            onPressed: usable && selected < trainingSlopes.last
                ? () => request(selected + 0.5, rapid: true)
                : null,
            icon: const Icon(Icons.add, size: 26),
            style:
                IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: dashboardAccent,
                  disabledForegroundColor: const Color(0xff75878a),
                  backgroundColor: const Color(0xff163b34),
                  disabledBackgroundColor: const Color(0xff252e31),
                ).copyWith(
                  side: WidgetStateProperty.resolveWith(
                    (states) => BorderSide(
                      color: states.contains(WidgetState.disabled)
                          ? const Color(0xff384446)
                          : dashboardAccent,
                    ),
                  ),
                ),
          ),
        ],
      );
      Widget label(String value) => Text(
        value,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.25,
          color: dashboardMuted,
        ),
      );
      final instruments = Row(
        children: [
          Expanded(
            child: WorkoutDial(
              label: 'VELOCIDAD',
              unit: 'km/h',
              maximum: 65,
              accent: const Color(0xff70cfff),
              decimals: 1,
              value: c.running ? telemetry['speedKmh'] as num? : null,
            ),
          ),
          Expanded(
            child: WorkoutDial(
              label: 'POTENCIA',
              unit: 'W',
              maximum: 800,
              accent: const Color(0xfff9bd6a),
              value: c.running ? telemetry['powerW'] as num? : null,
            ),
          ),
          Expanded(
            child: WorkoutDial(
              label: 'CADENCIA',
              unit: 'rpm',
              maximum: 160,
              accent: dashboardAccent,
              value: c.running ? telemetry['cadenceRpm'] as num? : null,
            ),
          ),
        ],
      );
      Widget profile(double height) => DecoratedBox(
        decoration: BoxDecoration(
          color: dashboardPanel,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label('PERFIL DE ELEVACIÓN VIRTUAL'),
              const SizedBox(height: 6),
              ElevationChart(
                key: ValueKey(id),
                height: height,
                points: report['virtualElevation'] as List? ?? const [],
                distanceMeters: meters,
              ),
            ],
          ),
        ),
      );
      return Theme(
        data: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: dashboardInk,
          colorScheme: ColorScheme.fromSeed(
            seedColor: dashboardAccent,
            brightness: Brightness.dark,
          ),
        ),
        child: Scaffold(
          appBar: AppBar(
            title: const Text(
              'ENTRENAMIENTO LIBRE',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
            ),
            backgroundColor: dashboardInk,
            actions: [
              PopupMenuButton<bool>(
                tooltip: 'Exportar entrenamiento',
                enabled: id != null,
                onSelected: (csv) => unawaited(export(csv: csv)),
                itemBuilder: (_) => [
                  if (!c.running && report['csvFile'] != null)
                    const PopupMenuItem(value: true, child: Text('Copiar CSV')),
                  PopupMenuItem(
                    value: false,
                    child: Text(
                      c.running ? 'Copiar JSON parcial' : 'Copiar JSON',
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Center(
              heightFactor: 1,
              child: FilledButton.icon(
                onPressed:
                    (c.running || (starting && !cancelled)) && !c.manualStopping
                    ? stop
                    : null,
                icon: const Icon(Icons.stop_rounded),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    c.manualStopping ? 'DETENIENDO…' : 'DETENER ENTRENAMIENTO',
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: const Color(0xff653337),
                  foregroundColor: const Color(0xffffe2e1),
                  textStyle: const TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                  ),
                ),
              ),
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                children: [
                  Builder(
                    builder: (context) {
                      final phase = active && showStart
                          ? '¡COMIENZA EL ENTRENAMIENTO!'
                          : warmingUp
                          ? 'CALENTAMIENTO'
                          : 'TIEMPO DE ENTRENAMIENTO';
                      final clock = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 30,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  phase,
                                  key: const ValueKey('trainingPhase'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: active && showStart
                                        ? dashboardAccent
                                        : dashboardMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .65,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              workoutTime(elapsed),
                              style: const TextStyle(
                                fontSize: 32,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      );
                      final slope = Column(
                        children: [label('PENDIENTE'), controls],
                      );
                      return constraints.maxWidth >= 320
                          ? Row(
                              children: [
                                Expanded(child: clock),
                                const SizedBox(width: 8),
                                slope,
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [clock, slope],
                            );
                    },
                  ),
                  if (activationFailed ||
                      (c.running && c.controlTransportUncertain))
                    const Text('No se pudo activar el control.'),
                  if (error != null && (!cancelled || c.running)) ...[
                    Text(error, style: const TextStyle(color: dashboardMuted)),
                    if (!cancelled && widget.session.preferenceError == null)
                      TextButton(
                        onPressed: c.commandBusy ? null : retry,
                        child: const Text('Reintentar conexión'),
                      ),
                  ],
                  const SizedBox(height: 12),
                  if (constraints.maxWidth >= 680)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 330,
                                ),
                                child: instruments,
                              ),
                              const SizedBox(height: 8),
                              distanceView(label, distance != null, meters),
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: profile(
                            (constraints.maxHeight - 123).clamp(104.0, 152.0),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    instruments,
                    const SizedBox(height: 12),
                    distanceView(label, distance != null, meters),
                    const SizedBox(height: 14),
                    profile((constraints.maxHeight * .24).clamp(112.0, 172.0)),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget distanceView(
    Widget Function(String) label,
    bool available,
    double meters,
  ) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Flexible(child: label('DISTANCIA RECORRIDA')),
      Text(
        available ? '${dashboardDecimal(meters / 1000, 2)} km' : '— km',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}
