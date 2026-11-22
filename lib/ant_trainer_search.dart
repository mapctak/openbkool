import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _DeferredSlope {
  _DeferredSlope(
    this.percent,
    this.sessionId,
    this.generation,
    this.rapidAdjustment,
  );
  final double percent;
  final bool rapidAdjustment;
  final stopwatch = Stopwatch()..start();
  final String? sessionId;
  final int generation;
  final requestedAtUtc = DateTime.now().toUtc().toIso8601String();
  final done = Completer<void>();
}

class AntTrainerSearchController extends ChangeNotifier {
  AntTrainerSearchController({String channelName = 'openbkool/ant_search'})
    : channel = MethodChannel(channelName),
      events = EventChannel('$channelName/events');
  final MethodChannel channel;
  final EventChannel events;
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _ready;
  bool _disposed = false;
  bool commandBusy = false;
  int _manualCommands = 0;
  int _manualGeneration = 0;
  bool manualStopping = false;
  bool _slopePumping = false;
  _DeferredSlope? _nextSlope, _activeSlope;
  final _clientSlopeEvents = <Map<String, Object?>>[];
  int _droppedClientSlopeEvents = 0;
  bool get acceptingManualChanges => !commandBusy || _slopePumping;
  num? get pendingManualPercent {
    if (manualStopping || controlTransportUncertain || !running) return null;
    final m = snapshot['manualControl'] as Map? ?? const {};
    if (m['stopped'] == true ||
        m['faulted'] == true ||
        m['eligible'] == false) {
      return null;
    }
    return _nextSlope?.percent ??
        _activeSlope?.percent ??
        (m['pendingManualChange'] as Map?)?['percent'] as num?;
  }

  void _clientEvent(String event, double? percent) {
    _clientSlopeEvents.add({
      'event': event,
      'percent': percent,
      'timestampUtc': DateTime.now().toUtc().toIso8601String(),
      'sessionId': snapshot['sessionId'],
    });
    if (_clientSlopeEvents.length > 256) {
      _clientSlopeEvents.removeAt(0);
      _droppedClientSlopeEvents++;
    }
  }

  void _cancelDeferredSlope(String reason) {
    final pending = _nextSlope;
    _nextSlope = null;
    if (pending != null) {
      _clientEvent(reason, pending.percent);
      pending.done.complete();
    }
  }

  Future<void> _queueSlope(
    double percent,
    String? sessionId,
    bool rapidAdjustment,
  ) {
    if (_disposed ||
        manualStopping ||
        controlTransportUncertain ||
        !acceptingManualChanges) {
      return Future.value();
    }
    final wanted = _DeferredSlope(
      percent,
      sessionId ?? snapshot['sessionId'] as String?,
      _manualGeneration,
      rapidAdjustment,
    );
    final previous = _nextSlope;
    if (previous != null) {
      _clientEvent('superseded_before_native', previous.percent);
      previous.done.complete();
    }
    _nextSlope = wanted;
    _clientEvent('selected_for_native', percent);
    if (!_slopePumping) unawaited(_pumpSlopes());
    _notify();
    return wanted.done.future;
  }

  Future<void> _pumpSlopes() async {
    _slopePumping = true;
    try {
      while (_nextSlope != null) {
        final wanted = _nextSlope!;
        _nextSlope = null;
        if (_disposed ||
            wanted.generation != _manualGeneration ||
            wanted.sessionId != snapshot['sessionId'] ||
            manualStopping ||
            controlTransportUncertain ||
            !running) {
          wanted.done.complete();
          _cancelDeferredSlope('cancelled_before_native');
          break;
        }
        _activeSlope = wanted;
        await _performManualAction(
          'setManualSlope',
          percent: wanted.percent,
          expectedSessionId: wanted.sessionId,
          requestedAtUtc: wanted.requestedAtUtc,
          uiQueueMs: wanted.stopwatch.elapsedMilliseconds,
          rapidAdjustment: wanted.rapidAdjustment,
        );
        _activeSlope = null;
        wanted.done.complete();
        final m = snapshot['manualControl'] as Map? ?? const {};
        if (m['stopped'] == true ||
            m['faulted'] == true ||
            m['eligible'] == false) {
          _cancelDeferredSlope('native_link_or_control_invalid');
        }
      }
    } finally {
      _activeSlope = null;
      _slopePumping = false;
      _notify();
    }
  }

  Map<String, Object?> snapshot = {'status': 'not_started', 'running': false};
  bool get _nativeTrainingLifecycle => channel.name == 'openbkool/training';
  bool get running => snapshot['running'] == true;
  bool get controlTransportUncertain =>
      snapshot['controlTransportUncertain'] == true;

  void _notify() {
    snapshot = {
      ...snapshot,
      'clientPendingManualPercent': pendingManualPercent,
      'clientManualChanges': List.of(_clientSlopeEvents),
      'droppedClientManualChanges': _droppedClientSlopeEvents,
    };
    if (!_disposed) notifyListeners();
  }

  void _update(dynamic value) {
    final incoming = Map<String, Object?>.from(value as Map);
    final sequence = incoming['reportSequence'];
    final currentSequence = snapshot['reportSequence'];
    // EventChannel and MethodChannel can deliver snapshots in different order.
    // Never let an older RX snapshot roll back an accepted manual command.
    if (incoming['sessionId'] != null &&
        incoming['sessionId'] == snapshot['sessionId'] &&
        sequence is num &&
        currentSequence is num &&
        sequence < currentSequence) {
      return;
    }
    final sameSession =
        incoming['sessionId'] != null &&
        incoming['sessionId'] == snapshot['sessionId'];
    if (!sameSession ||
        incoming['running'] == false ||
        (incoming['manualControl'] as Map?)?['stopped'] == true) {
      _cancelDeferredSlope('session_changed_or_closed');
    }
    snapshot = {
      ...incoming,
      if (sameSession && controlTransportUncertain)
        'controlTransportUncertain': true,
    };
    if (_ready != null && !_ready!.isCompleted) _ready!.complete();
    _notify();
  }

  Future<void> _listen() {
    if (_subscription == null) {
      _ready = Completer<void>();
      _subscription = events.receiveBroadcastStream().listen(
        _update,
        onError: (Object error) {
          if (!_ready!.isCompleted) _ready!.completeError(error);
          snapshot = {
            ...snapshot,
            'clientError': error.toString(),
            'controlTransportUncertain': true,
          };
          _notify();
          if (running && !_nativeTrainingLifecycle) unawaited(stop());
        },
      );
    }
    return _ready!.future.timeout(const Duration(seconds: 4));
  }

  Future<void> attachToTraining() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _listen();
    }
  }

  Future<void> start(String mode, {Map<String, Object?>? device}) async {
    if (running || commandBusy) return;
    commandBusy = true;
    _notify();
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        throw UnsupportedError(
          'La búsqueda ANT solo está disponible en Android',
        );
      }
      await _listen();
      if (_disposed || running) return;
      final training = mode == 'training_connected';
      _manualGeneration++;
      _cancelDeferredSlope("new_session");
      _clientSlopeEvents.clear();
      _droppedClientSlopeEvents = 0;
      snapshot = {
        ...snapshot,
        if (training) ...{
          'sessionId': null,
          'reportSequence': null,
          'identificationTiming': null,
          'transmissionDiagnostics': null,
          'radioCaptureCorrelation': null,
          'controlTransportUncertain': false,
          'manualControl': <String, Object?>{
            'enabled': false,
            'eligible': false,
            'unavailableReason': 'starting',
          },
          'manualControlEvents': <Object?>[],
          'channelIdentity': null,
          'startedAt': null,
          'updatedAt': null,
          'events': <Object?>[],
          'messages': <Object?>[],
          'operationEvents': <Object?>[],
          'csvError': null,
          'telemetry': null,
          'devices': <Object?>[],
          'connectionState': 'waiting_for_identity',
          'channelMode': 'dedicated_bidirectional_manual_opt_in',
          'selectedDevice': device,
          'csvFile': null,
        },
        'status': 'starting',
        'running': true,
        'clientError': null,
        'resourcesReleased': null,
      };
      _notify();
      await channel.invokeMethod<void>('start', {
        'mode': mode,
        'device': ?device,
      });
    } catch (error) {
      snapshot = {
        ...snapshot,
        'status': 'start_error',
        'running': false,
        'clientError': error.toString(),
        if (error is PlatformException && error.details is Map)
          ...Map<String, Object?>.from(error.details as Map),
      };
    } finally {
      commandBusy = false;
      _notify();
    }
  }

  Future<void> stop({String reason = 'user_finish'}) async {
    if (manualStopping) return;
    manualStopping = true;
    _manualGeneration++;
    _cancelDeferredSlope(reason);
    commandBusy = true;
    _notify();
    try {
      final report = await channel
          .invokeMapMethod<String, dynamic>('stop', {'reason': reason})
          .timeout(const Duration(seconds: 20));
      if (report != null) _update(report);
    } catch (error) {
      // No afirmar liberación si no se ha recibido confirmación nativa.
      snapshot = {
        ...snapshot,
        'clientError': 'No se pudo confirmar el cierre: $error',
        'controlTransportUncertain': true,
        'resourcesReleased': null,
      };
    } finally {
      manualStopping = false;
      commandBusy = manualStopping || _manualCommands > 0;
      _notify();
    }
  }

  Future<void> authorizeControl(String sessionId) => _performManualAction(
    'authorizeControl',
    confirmed: true,
    expectedSessionId: sessionId,
  );

  Future<void> requestSlope(
    double percent, {
    required String? sessionId,
    bool rapidAdjustment = false,
  }) => _queueSlope(percent, sessionId, rapidAdjustment);

  Future<void> _performManualAction(
    String method, {
    double? percent,
    String? requestedAtUtc,
    int? uiQueueMs,
    bool rapidAdjustment = false,
    bool confirmed = false,
    String? expectedSessionId,
  }) async {
    if (controlTransportUncertain || commandBusy || manualStopping) return;
    final generation = _manualGeneration;
    _manualCommands++;
    commandBusy = true;
    _notify();
    try {
      final report = await channel
          .invokeMapMethod<String, dynamic>(method, {
            'sessionId': expectedSessionId ?? snapshot['sessionId'],
            'confirmed': confirmed,
            'percent': ?percent,
            'requestedAtUtc': ?requestedAtUtc,
            'uiQueueMs': ?uiQueueMs,
            if (rapidAdjustment) 'rapidAdjustment': true,
          })
          .timeout(const Duration(seconds: 20));
      if (report != null && generation == _manualGeneration) _update(report);
    } catch (error) {
      if (generation == _manualGeneration) {
        snapshot = {
          ...snapshot,
          'clientError': 'Control manual: $error',
          'controlTransportUncertain': true,
        };
      }
    } finally {
      _manualCommands--;
      commandBusy = manualStopping || _manualCommands > 0;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (running && !_nativeTrainingLifecycle) {
      unawaited(stop(reason: 'controller_disposed'));
    }
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

class AntTrainerSearchPage extends StatefulWidget {
  const AntTrainerSearchPage({
    super.key,
    required this.controller,
    required this.onExport,
  });
  final AntTrainerSearchController controller;
  final Future<void> Function() onExport;
  @override
  State<AntTrainerSearchPage> createState() => _AntTrainerSearchPageState();
}

class _AntTrainerSearchPageState extends State<AntTrainerSearchPage> {
  String mode = 'sequential';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final report = c.snapshot;
      final devices = report['devices'] as List? ?? const [];
      final messages = report['messages'] as List? ?? const [];
      final events = report['events'] as List? ?? const [];
      final operations = report['operationEvents'] as List? ?? const [];
      final failure = report['v1Failure'] as Map?;
      final failureDetails = failure?['error'] as Map?;
      return PopScope(
        canPop: !c.running && !c.commandBusy,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          await c.stop();
          if (context.mounted && !c.running) Navigator.of(context).pop();
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Buscar rodillos ANT')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Búsqueda secuencial: FE-C (30 s), información de cada equipo (hasta 20 s por ID), '
                'y Bkool V1 público (40 s). Solo recepción y suscripciones informativas. '
                'Sin pendiente, resistencia, ERG ni firmware. Bkool V2 no está habilitado.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Protocolos'),
                items: const [
                  DropdownMenuItem(
                    value: 'sequential',
                    child: Text('Secuencial: FE-C → Bkool V1'),
                  ),
                  DropdownMenuItem(value: 'fec', child: Text('Solo ANT+ FE-C')),
                  DropdownMenuItem(
                    value: 'bkool_v1',
                    child: Text('Solo Bkool V1 público'),
                  ),
                ],
                onChanged: c.running || c.commandBusy
                    ? null
                    : (value) => setState(() => mode = value!),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: c.running || c.commandBusy
                    ? null
                    : () => c.start(mode),
                icon: const Icon(Icons.search),
                label: const Text('Iniciar búsqueda ANT'),
              ),
              OutlinedButton.icon(
                onPressed: c.running || c.commandBusy ? c.stop : null,
                icon: const Icon(Icons.stop),
                label: Text(
                  c.commandBusy ? 'Procesando…' : 'Detener búsqueda ANT',
                ),
              ),
              if (c.running || c.commandBusy) const LinearProgressIndicator(),
              Text(
                'Estado: ${report['status']} · fase: ${report['stage'] ?? 'sin iniciar'}',
              ),
              Text(
                'Recursos liberados: ${switch (report['resourcesReleased']) {
                  true => 'sí',
                  false => 'no / en uso',
                  _ => 'sin confirmar',
                }}',
              ),
              if (failure != null)
                ListTile(
                  title: const Text('Operación V1 fallida'),
                  subtitle: SelectableText(
                    '${failure['operation'] ?? 'no identificada'}\n'
                    '${failureDetails?['type']} · ${failureDetails?['failureReason'] ?? ''}\n'
                    '${failureDetails?['message']}',
                  ),
                ),
              if (operations.isNotEmpty)
                ExpansionTile(
                  title: Text('Operaciones ANT: ${operations.length}'),
                  children: [
                    for (final op in operations)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: SelectableText(
                          '${op['timestamp']} #${op['operationId']} ${op['operation']} [${op['state']}]\n'
                          'Argumentos: ${op['arguments']} · ${op['durationMs'] ?? '-'} ms\n'
                          '${op['reason'] ?? op['result'] ?? op['error'] ?? ''}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              if (report['clientError'] != null)
                SelectableText('ERROR: ${report['clientError']}'),
              if (report['status'] == 'cleanup_failed')
                const Text(
                  'Falló el cierre. No se iniciarán otras operaciones ANT hasta reiniciar la aplicación.',
                ),
              OutlinedButton.icon(
                onPressed: widget.onExport,
                icon: const Icon(Icons.copy),
                label: const Text('Exportar diagnóstico JSON'),
              ),
              Text('Dispositivos ANT encontrados: ${devices.length}'),
              for (final d in devices)
                Card(
                  child: ListTile(
                    title: Text(
                      '${d['bkoolConfirmed'] == true ? 'BKOOL ' : ''}${d['bkoolModel'] ?? d['displayName'] ?? 'Dispositivo ANT'}',
                    ),
                    subtitle: Text(
                      [
                        'ID ${d['deviceNumber']} · tipo ${d['deviceType']} · ${d['protocol']}',
                        'Transmisión: ${d['transmissionType'] ?? 'no expuesta por SDK'}',
                        if (d['bkoolV1TypeCandidate'] == true)
                          'Tipo 112 compatible con candidato Bkool V1',
                        if (d['manufacturerId'] != null)
                          'Fabricante ${d['manufacturerId']} · modelo ${d['modelNumber']}',
                        if (d['bkoolModel'] != null &&
                            d['bkoolConfirmed'] != true)
                          'Modelo compatible; fabricante Bkool sin confirmar',
                        if (d['hardwareRevision'] != null)
                          'Hardware ${d['hardwareRevision']}',
                        if (d['mainSoftwareRevision'] != null)
                          'Software ${d['mainSoftwareRevision']} · serial ${d['serialNumber']}',
                        'Última detección: ${d['lastSeen']}',
                      ].join('\n'),
                    ),
                  ),
                ),
              const Text('Mensajes ANT en hexadecimal (recepción pública V1)'),
              const Text(
                'FE-C expone eventos interpretados del SDK, no bytes ANT crudos. No se generan tramas ficticias.',
              ),
              Text(
                'Mensajes conservados: ${messages.length} · descartados del búfer: ${report['droppedMessages'] ?? 0}',
              ),
              for (final m in messages.reversed.take(100))
                SelectableText(
                  '${m['timestamp']} ${m['messageType']} ID=${m['messageId']} '
                  'dispositivo=${m['deviceNumber'] ?? '?'}\n${m['messageHex'] ?? m['contentHex']}\n'
                  '${m['payloadHex'] == null ? '' : 'Página: ${m['payloadHex']}'}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              const Text('Eventos de búsqueda'),
              for (final e in events.reversed)
                SelectableText(
                  '${e['timestamp']} [${e['stage']}/${e['event']}] ${e['message']}',
                ),
            ],
          ),
        ),
      );
    },
  );
}
