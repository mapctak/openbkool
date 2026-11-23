import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/app_home.dart';
import 'package:openbkool/main.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/trainer_session.dart';

import 'widget_test.dart' show TestBlePlatform;

class FakeTraining extends AntTrainerSearchController {
  FakeTraining() : super(channelName: 'openbkool/training');
  final starts = <Map<String, Object?>>[];
  int stops = 0;
  Map<String, Object?>? workoutStopReport;
  @override
  Future<void> start(String mode, {Map<String, Object?>? device}) async {
    starts.add({'mode': mode, 'device': device});
    emit({
      'running': mode != 'training_connection_check',
      'status': 'starting',
      'selectedDevice': device,
      'mode': mode,
      if (mode == 'training_connection_check') ...{
        'trainingServiceActive': true,
        'connectionOnly': true,
        'antConnectionState': 'connecting',
      },
    });
  }

  void emit(Map<String, Object?> report) {
    snapshot = report;
    notifyListeners();
  }

  @override
  Future<void> stop({String reason = 'user_finish', String? expectedId}) async {
    stops++;
    if (workoutStopReport case final report?) {
      emit(report);
      return;
    }
    emit({
      ...snapshot,
      'running': false,
      'status': reason,
      'trainingServiceActive': false,
      'antConnectionState': 'disconnected',
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(
    () => messenger.setMockMethodCallHandler(
      TrainerPreferences.channel,
      (call) async => null,
    ),
  );
  tearDown(
    () => messenger.setMockMethodCallHandler(TrainerPreferences.channel, null),
  );
  testWidgets(
    'a new Flutter activity reattaches to the service workout without starting or authorizing',
    (tester) async {
      const events = MethodChannel('openbkool/training/events');
      const commands = MethodChannel('openbkool/training');
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(commands, (call) async {
        calls.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(events, (call) async {
        if (call.method == 'listen') {
          await messenger.handlePlatformMessage(
            events.name,
            const StandardMethodCodec().encodeSuccessEnvelope({
              'sessionId': 'owned-by-service',
              'running': true,
              'trainingServiceActive': true,
              'selectedDevice': SavedTrainer.known.device,
              'connectionState': 'identity_verified',
              'telemetry': {'signal': 'receiving'},
              'manualControl': {
                'enabled': true,
                'eligible': true,
                'state': 'active',
              },
            }),
            (_) {},
          );
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(events, null);
        messenger.setMockMethodCallHandler(commands, null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: OpenBkoolShell(advancedBuilder: (_, _) => const SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('TIEMPO DE ENTRENAMIENTO'), findsOneWidget);
      expect(find.text('Autorizar rango completo'), findsNothing);
      expect(find.text('DETENER ENTRENAMIENTO'), findsOneWidget);
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'home offers only free training and connects using the remembered identity',
    (tester) async {
      messenger.setMockMethodCallHandler(
        TrainerPreferences.channel,
        (call) async => const SavedTrainer(123, 112, 6, model: 22).toJson(),
      );
      final training = FakeTraining();
      final session = TrainerSession(training: training);
      await tester.pumpWidget(
        MaterialApp(
          home: OpenBkoolShell(
            session: session,
            advancedBuilder: (_, close) =>
                Scaffold(appBar: AppBar(title: const Text('Diagnostic probe'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CONECTANDO…'), findsOneWidget);
      expect(training.starts.single, {
        'mode': 'training_connection_check',
        'device': const SavedTrainer(123, 112, 6).device,
      });
      training.emit({
        ...training.snapshot,
        'trainingServiceActive': false,
        'antConnectionState': 'error',
        'status': 'radio_search_timeout',
      });
      await tester.pumpAndSettle();
      expect(find.text('DESCONECTADO'), findsOneWidget);
      expect(find.text('ANT · 123/112/6'), findsNothing);
      expect(find.text('ENTRENAMIENTO LIBRE'), findsOneWidget);
      expect(find.text('Control manual 1.4'), findsNothing);
      await tester.tap(find.text('ENTRENAMIENTO LIBRE'));
      await tester.pumpAndSettle();
      expect(training.starts.last, {
        'mode': 'training_connected',
        'device': const SavedTrainer(123, 112, 6).device,
      });
      expect(find.text('CALENTAMIENTO'), findsOneWidget);
      training.emit({
        'running': true,
        'status': 'running',
        'sessionId': 'live',
        'selectedDevice': session.selected.device,
        'connectionState': 'identity_verified',
        'telemetry': {'signal': 'receiving'},
      });
      await tester.pumpAndSettle();
      expect(find.text('CALENTAMIENTO'), findsOneWidget);
      training.emit({
        'running': false,
        'status': 'start_error',
        'clientError': 'radio unavailable',
      });
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No se pudo conectar. Revisa el rodillo, ANT y los permisos.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Reintentar conexión'));
      await tester.pumpAndSettle();
      expect(training.starts, hasLength(3));
      expect(training.starts.last, training.starts[1]);
      await tester.tap(find.text('DETENER ENTRENAMIENTO'));
      await tester.pumpAndSettle();
      expect(training.stops, 1);
      expect(find.text('CALENTAMIENTO'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'home connects automatically and reuses the link for successive workouts',
    (tester) async {
      final training = FakeTraining();
      final session = TrainerSession(training: training);
      await tester.pumpWidget(
        MaterialApp(
          home: OpenBkoolShell(
            session: session,
            advancedBuilder: (_, _) => const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bkool Smart Pro v1'), findsOneWidget);
      expect(find.text('Comprobar conexión'), findsNothing);
      expect(find.text('CALENTAMIENTO'), findsNothing);
      expect(find.text('CONECTANDO…'), findsOneWidget);
      expect(training.starts.single, {
        'mode': 'training_connection_check',
        'device': SavedTrainer.known.device,
      });
      training.emit({
        'mode': 'training_connection_check',
        'running': false,
        'status': 'running',
        'selectedDevice': SavedTrainer.known.device,
        'trainingServiceActive': true,
        'antConnectionState': 'read_only',
        'connectionOnly': true,
        'resourcesReleased': false,
      });
      await tester.pumpAndSettle();
      expect(find.text('CONECTADO'), findsOneWidget);
      expect(find.text('Desconectar'), findsNothing);
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('CONECTADO'), findsOneWidget);
      expect(training.starts, hasLength(1));
      expect(training.stops, 0);
      await tester.tap(find.text('ENTRENAMIENTO LIBRE'));
      await tester.pumpAndSettle();
      expect(training.starts.last['mode'], 'training_connected');
      expect(find.text('CALENTAMIENTO'), findsOneWidget);
      final readOnly = <String, Object?>{
        'selectedDevice': SavedTrainer.known.device,
        'connectionId': 'channel',
        'connectionActionId': 'channel',
        'connectionOnly': true,
        'antConnectionState': 'read_only',
        'trainingServiceActive': true,
        'running': false,
      };
      Map<String, Object?> workout(String id) => {
        ...readOnly,
        'sessionId': id,
        'connectionOnly': false,
        'connectionActionId': id,
        'antConnectionState': 'training',
        'running': true,
        'manualControl': {'eligible': true, 'enabled': true, 'state': 'active'},
      };
      training.emit(workout('first'));
      await tester.pumpAndSettle();
      expect(find.text('¡COMIENZA EL ENTRENAMIENTO!'), findsOneWidget);
      training.workoutStopReport = {
        ...readOnly,
        'sessionId': 'first',
        'recordState': 'final',
        'status': 'user_finish',
        'csvFile': 'first.csv',
      };
      await tester.tap(find.text('DETENER ENTRENAMIENTO'));
      await tester.pumpAndSettle();
      expect(training.running, false);
      await tester.tap(find.byTooltip('Exportar entrenamiento'));
      await tester.pumpAndSettle();
      expect(find.text('Copiar CSV'), findsOneWidget);
      expect(find.text('Copiar JSON'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('CONECTADO'), findsOneWidget);
      await tester.tap(find.text('ENTRENAMIENTO LIBRE'));
      await tester.pumpAndSettle();
      training.emit(workout('second'));
      await tester.pumpAndSettle();
      expect(training.snapshot['sessionId'], 'second');
      expect(training.snapshot['connectionId'], 'channel');
      expect(training.snapshot['csvFile'], isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'home retries a released link only while visible and foregrounded',
    (tester) async {
      final training = FakeTraining();
      final session = TrainerSession(training: training);
      await tester.pumpWidget(OpenBkoolApp(session: session));
      await tester.pumpAndSettle();

      final connected = {
        ...training.snapshot,
        'antConnectionState': 'read_only',
      };
      training.emit(connected);
      await tester.pumpAndSettle();
      expect(find.text('CONECTADO'), findsOneWidget);
      expect(training.snapshot['sessionId'], isNull);
      expect(training.snapshot['virtualElevation'], isNull);
      expect(training.snapshot['trainingElapsedMs'], isNull);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(training.starts, hasLength(1));

      training.emit({...connected, 'antConnectionState': 'error'});
      await tester.pumpAndSettle();
      expect(find.text('DESCONECTADO'), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      expect(training.starts, hasLength(1));

      training.emit({
        ...training.snapshot,
        'status': 'disconnected',
        'trainingServiceActive': false,
      });
      await tester.pump(const Duration(seconds: 14));
      expect(training.starts, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(training.starts, hasLength(2));
      expect(find.text('CONECTANDO…'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      training.emit({
        ...training.snapshot,
        'status': 'radio_search_timeout',
        'antConnectionState': 'error',
        'trainingServiceActive': false,
      });
      await tester.pump(const Duration(seconds: 16));
      expect(training.starts, hasLength(2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(training.starts, hasLength(3));
      expect(
        training.starts.every(
          (call) => call['mode'] == 'training_connection_check',
        ),
        isTrue,
      );
      expect(training.stops, 0);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'settings exposes intact advanced tools and preserves BLE page across visits',
    (tester) async {
      const trainingEvents = MethodChannel('openbkool/training/events');
      const trainingCommands = MethodChannel('openbkool/training');
      messenger.setMockMethodCallHandler(trainingCommands, (call) async {
        if (call.method == 'start') {
          throw PlatformException(code: 'training_service_blocked');
        }
        return {'running': false, 'status': 'disconnect_trainer'};
      });
      messenger.setMockMethodCallHandler(trainingEvents, (call) async {
        if (call.method == 'listen') {
          await messenger.handlePlatformMessage(
            trainingEvents.name,
            const StandardMethodCodec().encodeSuccessEnvelope({
              'running': false,
              'status': 'not_started',
            }),
            (_) {},
          );
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(trainingEvents, null),
      );
      final radio = TestBlePlatform();
      FlutterBluePlusPlatform.instance = radio;
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const OpenBkoolApp());
      await tester.pumpAndSettle();
      expect(find.text('Rutas GPX'), findsNothing);
      expect(find.text('Sesiones de spinning'), findsNothing);
      expect(find.text('Buscar dispositivos BLE'), findsNothing);
      expect(radio.settings, isEmpty);
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagnósticos avanzados'));
      await tester.pumpAndSettle();
      expect(find.text('Buscar dispositivos BLE'), findsOneWidget);
      expect(find.text('Buscar rodillos ANT'), findsOneWidget);
      expect(find.text('Diagnóstico ANT+'), findsOneWidget);
      expect(find.text('Exportar diagnóstico JSON'), findsOneWidget);
      final state = tester.state(find.byType(BleDiagnosticPage));
      await tester.tap(find.byTooltip('Volver al inicio'));
      await tester.pumpAndSettle();
      expect(find.text('ENTRENAMIENTO LIBRE'), findsOneWidget);
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagnósticos avanzados'));
      await tester.pumpAndSettle();
      expect(
        identical(tester.state(find.byType(BleDiagnosticPage)), state),
        true,
      );
      expect(radio.writeAttempts, 0);
      expect(radio.notificationAttempts, 0);
      expect(radio.settings, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'manual selection of multiple trainers persists without connecting',
    (tester) async {
      Map<dynamic, dynamic>? stored;
      messenger.setMockMethodCallHandler(TrainerPreferences.channel, (
        call,
      ) async {
        if (call.method == 'loadTrainer') return stored;
        stored = Map<dynamic, dynamic>.from(call.arguments as Map);
        return null;
      });
      final training = FakeTraining();
      final session = TrainerSession(training: training);
      await session.restore();
      session.search.snapshot = {
        'devices': [
          const SavedTrainer(123, 112, 6, model: 22).toJson(),
          const SavedTrainer(456, 112, 7, model: 24).toJson(),
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TrainerSelectionPage(session: session),
                  ),
                ),
                child: const Text('Choose'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(find.text('123/112/6'), findsOneWidget);
      expect(find.text('456/112/7'), findsOneWidget);
      await tester.tap(find.text('123/112/6'));
      await tester.pumpAndSettle();
      expect(session.selected.id, '123/112/6');
      expect(stored!['deviceNumber'], 123);
      expect(training.starts, isEmpty);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'free training on S7 width has readable metrics and no automatic control',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final training = FakeTraining();
      final session = TrainerSession(training: training);
      training.snapshot = {
        'running': true,
        'status': 'running',
        'sessionId': 'live',
        'selectedDevice': SavedTrainer.known.device,
        'connectionState': 'identity_verified',
        'telemetry': {
          'signal': 'receiving',
          'powerW': 200,
          'cadenceRpm': 80,
          'speedKmh': 25.0,
          'distanceM': 1234,
          'elapsedMs': 61000,
        },
        'manualControl': {'enabled': false, 'eligible': true},
        'manualControlEvents': [
          {'event': 'request', 'requestedPercent': 0.5},
          {'event': 'api_returned', 'requestedPercent': 0.5},
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: OpenBkoolShell(
            session: session,
            advancedBuilder: (_, close) => const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('ENTRENAMIENTO LIBRE'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ENTRENAMIENTO LIBRE'));
      await tester.pumpAndSettle();
      expect(find.text('ENTRENAMIENTO LIBRE'), findsOneWidget);
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('200'), 150, scrollable: list);
      expect(find.text('200'), findsOneWidget);
      expect(find.text('00:01:01'), findsOneWidget);
      expect(find.text('1,23 km'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
      expect(training.starts, isEmpty);
      expect(tester.takeException(), isNull);
      await training.stop();
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets('leaving free training explicitly stops the session once', (
    tester,
  ) async {
    final training = FakeTraining();
    final session = TrainerSession(training: training);
    training.snapshot = {
      'running': true,
      'status': 'running',
      'sessionId': 'live',
      'selectedDevice': SavedTrainer.known.device,
      'connectionState': 'identity_verified',
      'telemetry': {'signal': 'receiving'},
    };
    await tester.pumpWidget(OpenBkoolApp(session: session));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ENTRENAMIENTO LIBRE'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ENTRENAMIENTO LIBRE'));
    await tester.pumpAndSettle();
    expect(training.stops, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(training.stops, 1);
    expect(training.running, false);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
