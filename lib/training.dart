import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'trainer_session.dart';
import 'workout_dashboard.dart';

final trainingSlopes = List<double>.unmodifiable(
  List.generate(41, (index) => TrainerSession.minSlope + index * 0.5),
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

  Future<void> authorize(String id) async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Autorizar control de pendiente'),
        content: const Text(
          'Autorizo el rango de −5 % a +15 % para este rodillo en futuros entrenamientos. Las pendientes '
          'negativas y superiores a +8 % son experimentales. La respuesta física '
          'no está verificada para los 41 valores. '
          'La API y una solicitud de 0 % no garantizan la resistencia del rodillo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar autorización'),
          ),
        ],
      ),
    );
    if (consent == true &&
        mounted &&
        !cancelled &&
        widget.session.training.snapshot['sessionId'] == id &&
        readyForControl(widget.session.training.snapshot)) {
      await widget.session.setControlConsent(true);
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

  bool starting = false;
  bool pendingEntry = true;
  bool cancelled = false;
  String? promptedSession;
  String? activationAttempt;
  bool checking = false;
  bool prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final session = widget.session;
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
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(scheduleWarmup);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) scheduleWarmup();
  }

  bool readyForControl(Map<String, Object?> report) =>
      report['sessionId'] is String &&
      report['trainingServiceActive'] == true &&
      connectionFor(report, widget.session.selected) ==
          TrainerConnection.connected &&
      // Kotlin already checks channel, exact identity, 67/22 and freshness.
      (report['manualControl'] as Map?)?['eligible'] == true &&
      !widget.session.training.manualStopping &&
      !widget.session.training.controlTransportUncertain;

  void scheduleWarmup() {
    if (checking) return;
    checking = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checking = false;
      if (mounted) unawaited(checkWarmup());
    });
  }

  Future<void> askConsent(String id) async {
    setState(() {
      promptedSession = id;
      prompting = true;
    });
    try {
      await authorize(id);
    } finally {
      if (mounted) {
        setState(() => prompting = false);
        scheduleWarmup();
      }
    }
  }

  Future<void> checkWarmup() async {
    final session = widget.session;
    final c = session.training;
    final report = c.snapshot;
    if (cancelled ||
        prompting ||
        session.loading ||
        session.saving ||
        c.commandBusy ||
        !readyForControl(report)) {
      return;
    }
    final id = report['sessionId'] as String;
    if ((report['manualControl'] as Map)['enabled'] == true) return;
    if (session.hasControlConsent) {
      if (activationAttempt == id) return;
      setState(() => activationAttempt = id);
      await c.authorizeControl(id);
    } else if (promptedSession != id &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed)) {
      await askConsent(id);
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
      promptedSession = null;
    });
    try {
      await session.connect();
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Future<void> stop({String reason = 'user_finish'}) async {
    setState(() {
      cancelled = true;
    });
    await widget.session.training.stop(reason: reason);
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
        selected = (manual['lastRequestedPercent'] as num?)?.toDouble() ?? 0;
        if (!trainingSlopes.contains(selected)) selected = 0;
      }
      final available = id != null && readyForControl(report) && !cancelled;
      final error = starting && !c.running ? null : connectionError(report);
      final active =
          available && manual['enabled'] == true && manual['state'] == 'active';
      final activationFailed =
          available && !active && activationAttempt == id && !c.commandBusy;
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
      final elapsed = telemetry['elapsedMs'] as num? ?? 0;
      final connection = widget.session.connection;
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.outlined(
            tooltip: 'Disminuir pendiente',
            onPressed: usable && selected > trainingSlopes.first
                ? () => request(selected - 0.5, rapid: true)
                : null,
            icon: const Text('−', style: TextStyle(fontSize: 26)),
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
          SizedBox(
            width: 106,
            child: Center(
              child: DropdownButton<double>(
                key: const ValueKey('trainingSlope'),
                isExpanded: true,
                menuWidth: 152,
                selectedItemBuilder: (context) => [
                  for (final value in trainingSlopes)
                    Align(
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(slopeLabel(value)),
                      ),
                    ),
                ],
                value: selected,
                underline: const SizedBox.shrink(),
                dropdownColor: dashboardPanel,
                style: const TextStyle(
                  fontSize: 19,
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
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
            ),
          ),
          IconButton.outlined(
            tooltip: 'Aumentar pendiente',
            onPressed: usable && selected < trainingSlopes.last
                ? () => request(selected + 0.5, rapid: true)
                : null,
            icon: const Text('+', style: TextStyle(fontSize: 26)),
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
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
        child: PopScope(
          canPop: !starting && !c.running && !c.commandBusy,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop || c.manualStopping) return;
            await stop(reason: 'screen_closed');
            if (context.mounted && !c.running && !c.commandBusy) {
              Navigator.pop(context);
            }
          },
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
                      const PopupMenuItem(
                        value: true,
                        child: Text('Copiar CSV'),
                      ),
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
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: const Color(0xffff7169),
                  foregroundColor: const Color(0xff2c1012),
                  textStyle: const TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
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
                    Row(
                      children: [
                        Icon(
                          Icons.sensors_rounded,
                          color: connection == TrainerConnection.connected
                              ? dashboardAccent
                              : dashboardMuted,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'ANT · ${warmingUp ? 'CALENTAMIENTO' : connectionLabel(connection)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: dashboardMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label('TIEMPO'),
                            Text(
                              workoutTime(elapsed),
                              style: const TextStyle(
                                fontSize: 32,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [label('PENDIENTE'), controls],
                        ),
                      ],
                    ),
                    if (warmingUp &&
                        !activationFailed &&
                        !c.controlTransportUncertain)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          available
                              ? (widget.session.hasControlConsent
                                    ? 'Activando control…'
                                    : 'Permiso de control pendiente')
                              : connection == TrainerConnection.connected
                              ? 'Esperando identificación ANT…'
                              : 'Buscando rodillo…',
                          style: const TextStyle(color: dashboardMuted),
                        ),
                      ),
                    if (available &&
                        !active &&
                        !prompting &&
                        !widget.session.hasControlConsent &&
                        promptedSession == id)
                      TextButton(
                        onPressed: () => askConsent(id),
                        child: const Text('Revisar permiso de control'),
                      ),
                    if (activationFailed ||
                        (c.running && c.controlTransportUncertain))
                      const Text('No se pudo activar el control.'),
                    if (available && widget.session.consentError != null)
                      Text(widget.session.consentError!),
                    if (error != null && (!cancelled || c.running)) ...[
                      Text(
                        error,
                        style: const TextStyle(color: dashboardMuted),
                      ),
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
                                    maxWidth: 345,
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
                              (constraints.maxHeight - 150).clamp(108.0, 240.0),
                            ),
                          ),
                        ],
                      )
                    else ...[
                      instruments,
                      const SizedBox(height: 12),
                      distanceView(label, distance != null, meters),
                      const SizedBox(height: 14),
                      profile(
                        (constraints.maxHeight - 310).clamp(146.0, 340.0),
                      ),
                    ],
                  ],
                ),
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
