import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/manual_ride.dart';
import 'package:openbkool/app_home.dart';
import 'package:openbkool/trainer_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const device = <String, Object?>{
    'deviceNumber': 30064,
    'deviceType': 112,
    'transmissionType': 5,
    'protocol': 'BKOOL_V1_PUBLIC',
  };
  Map<String, Object?> report({bool allowed = false, bool active = false}) => {
    'sessionId': 'manual-sim',
    'running': true,
    'connectionState': 'identity_verified',
    'manualSessionPolicy': {'physicalEnabled': allowed},
    'manualControl': {
      'mode': 'manual_session',
      'authorizedRange': {'id': 'original', 'minPercent': -5, 'maxPercent': 15},
      'enabled': active,
      'eligible': true,
      'state': active ? 'active' : 'available',
      'elapsedControlMs': 7200000,
      'maxDurationMs': null,
      'remainingMs': null,
    },
    'telemetry': {
      'elapsedMs': 7200000,
      'speedKmh': 20.5,
      'powerW': 120,
      'cadenceRpm': 80,
    },
  };
  Future<void> show(WidgetTester tester, AntTrainerSearchController c) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ManualRidePage(controller: c, device: device),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> clean(WidgetTester tester, AntTrainerSearchController c) async {
    c.snapshot = {...c.snapshot, 'running': false};
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    messenger.setMockMethodCallHandler(c.channel, null);
  }

  test(
    'range contains exactly 41 half points, zero, negatives and extremes',
    () {
      expect(manualRideSlopes.length, 41);
      expect(manualRideSlopes.first, -5);
      expect(manualRideSlopes.last, 15);
      expect(manualRideSlopes.where((p) => p == 0).length, 1);
      for (var i = 1; i < 41; i++) {
        expect(manualRideSlopes[i] - manualRideSlopes[i - 1], 0.5);
      }
    },
  );
  testWidgets('home opens manual preparation without connecting or arming', (
    tester,
  ) async {
    final c = AntTrainerSearchController(
      channelName: 'openbkool/manual-ride-sim',
    );
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(c.channel, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
      TrainerPreferences.channel,
      (call) async => null,
    );
    final session = TrainerSession(training: c);
    await tester.pumpWidget(
      MaterialApp(
        home: OpenBkoolShell(
          session: session,
          advancedBuilder: (_, close) =>
              const Scaffold(body: Text('Diagnósticos')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Control manual 1.4'), 250);
    await tester.tap(find.text('Control manual 1.4'));
    await tester.pumpAndSettle();
    expect(find.byType(ManualRidePage), findsOneWidget);
    expect(calls, isEmpty);
    expect(find.textContaining('Selección: 41 valores.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    messenger.setMockMethodCallHandler(c.channel, null);
    messenger.setMockMethodCallHandler(TrainerPreferences.channel, null);
  });
  testWidgets(
    'physical mode blocked even with valid identity; preview never sends',
    (tester) async {
      final c = AntTrainerSearchController(
        channelName: 'openbkool/manual-ride-sim',
      );
      c.snapshot = report();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return c.snapshot;
      });
      await show(tester, c);
      final dropdown = tester.widget<DropdownButton<double>>(
        find.byKey(const ValueKey('manualRideSlope')),
      );
      expect(dropdown.items!.length, 41);
      dropdown.onChanged!(-5);
      await tester.pump();
      expect(find.text('Pendiente seleccionada: -5,0 %'), findsOneWidget);
      tester
          .widget<DropdownButton<double>>(
            find.byKey(const ValueKey('manualRideSlope')),
          )
          .onChanged!(15);
      await tester.pump();
      expect(find.text('Pendiente seleccionada: +15,0 %'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Autorizar sesión manual'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'LLANO 0 %'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Sin autorización nativa'), findsOneWidget);
      expect(calls, isEmpty);
      await clean(tester, c);
    },
  );
  testWidgets(
    'simulated enabled session requires consent and arming never sends selected goal',
    (tester) async {
      final c = AntTrainerSearchController(
        channelName: 'openbkool/manual-ride-sim',
      );
      c.snapshot = report(allowed: true);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return report(allowed: true, active: true);
      });
      await show(tester, c);
      await tester.tap(find.text('Autorizar sesión manual'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Autorizar sesión manual'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Autorizar sesión'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'enableManualTest');
      expect((calls.single.arguments as Map)['confirmed'], true);
      expect((calls.single.arguments as Map)['controlMode'], 'manual_session');
      expect((calls.single.arguments as Map)['rangeProfile'], 'original');
      expect((calls.single.arguments as Map)['experimentalConfirmed'], true);
      expect(find.text('Tiempo: 2:00:00'), findsOneWidget);
      await clean(tester, c);
    },
  );
  testWidgets(
    'simulated range orders update API display; failed send preserves accepted goal',
    (tester) async {
      final c = AntTrainerSearchController(
        channelName: 'openbkool/manual-ride-sim',
      );
      c.snapshot = report(allowed: true, active: true);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        final p = (call.arguments as Map)['percent'];
        return {
          ...c.snapshot,
          'manualControl': {
            ...(c.snapshot['manualControl'] as Map),
            if (p == 15) 'lastApiError': {'error': 'simulated failure'},
            if (p != 15)
              'lastManualApiSuccess': {
                'requestedPercent': p,
                'stopRequest': false,
              },
          },
        };
      });
      await show(tester, c);
      tester
          .widget<DropdownButton<double>>(
            find.byKey(const ValueKey('manualRideSlope')),
          )
          .onChanged!(-5);
      await tester.pumpAndSettle();
      expect(find.text('Pendiente ordenada: -5,0 %'), findsOneWidget);
      tester
          .widget<DropdownButton<double>>(
            find.byKey(const ValueKey('manualRideSlope')),
          )
          .onChanged!(15);
      await tester.pumpAndSettle();
      expect(find.text('Pendiente seleccionada: +15,0 %'), findsOneWidget);
      expect(find.text('Pendiente ordenada: -5,0 %'), findsOneWidget);
      expect(find.textContaining('simulated failure'), findsOneWidget);
      expect(calls.map((c) => (c.arguments as Map)['percent']), [-5, 15]);
      await clean(tester, c);
    },
  );
  testWidgets(
    'LLANO and stop are distinct and background never resumes control',
    (tester) async {
      final c = AntTrainerSearchController(
        channelName: 'openbkool/manual-ride-sim',
      );
      c.snapshot = report(allowed: true, active: true);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return {
          ...c.snapshot,
          if (call.method == 'stopManualTest' || call.method == 'stop')
            'running': false,
        };
      });
      await show(tester, c);
      await tester.tap(find.text('LLANO 0 %'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'setManualSlope');
      expect((calls.single.arguments as Map)['percent'], 0);
      await tester.tap(find.text('DETENER CONTROL'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'stopManualTest');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      await clean(tester, c);
    },
  );
  testWidgets(
    'active background stops once and forced screen removal cancels session',
    (tester) async {
      final c = AntTrainerSearchController(
        channelName: 'openbkool/manual-ride-sim',
      );
      c.snapshot = report(allowed: true, active: true);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return {...c.snapshot, 'running': false};
      });
      await show(tester, c);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(calls.single.method, 'stop');
      expect((calls.single.arguments as Map)['reason'], 'app_background');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls.length, 1);
      c.snapshot = report(allowed: true, active: true);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect((calls.last.arguments as Map)['reason'], 'screen_closed');
      await clean(tester, c);
    },
  );
  testWidgets(
    'low load requires consent, survives 30 seconds and cannot escalate profile',
    (tester) async {
      final c = AntTrainerSearchController(
        channelName: 'openbkool/low-load-sim',
      );
      Map<String, Object?> lowReport(bool active) => {
        ...report(active: active),
        'lowLoadPolicy': {'physicalEnabled': true},
        'manualControl': {
          ...(report(active: active)['manualControl'] as Map),
          'mode': 'manual_low_load',
        },
      };
      c.snapshot = lowReport(false);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return {
          ...lowReport(true),
          if (call.method == 'stopManualTest') 'running': false,
          'manualControl': {
            ...(lowReport(true)['manualControl'] as Map),
            if (call.method == 'setManualSlope')
              'lastManualApiSuccess': {
                'requestedPercent': (call.arguments as Map)['percent'],
                'stopRequest': false,
              },
          },
        };
      });
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ManualRidePage(controller: c, device: device, lowLoad: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(
        tester
            .widget<DropdownButton<double>>(
              find.byKey(const ValueKey('manualRideSlope')),
            )
            .items!
            .length,
        41,
      );
      await tester.tap(find.text('Iniciar sesión supervisada'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Autorizar sesión supervisada'),
      );
      await tester.pumpAndSettle();
      expect(calls.single.method, 'enableManualTest');
      expect((calls.single.arguments as Map)['controlMode'], 'manual_low_load');
      expect((calls.single.arguments as Map)['experimentalConfirmed'], true);
      expect(find.text('Tiempo: 2:00:00'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const ValueKey('manualRangeProfile')),
            )
            .onChanged,
        isNull,
      );
      tester
          .widget<DropdownButton<double>>(
            find.byKey(const ValueKey('manualRideSlope')),
          )
          .onChanged!(0.5);
      await tester.pumpAndSettle();
      expect(find.text('Pendiente ordenada: +0,5 %'), findsOneWidget);
      await tester.tap(find.text('LLANO 0 %'));
      await tester.pumpAndSettle();
      expect((calls.last.arguments as Map)['percent'], 0);
      await tester.tap(find.text('DETENER CONTROL'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'stopManualTest');
      expect(calls.length, 4);
      await clean(tester, c);
    },
  );
  testWidgets(
    'profile authorization keeps 41 previews and rejects UI escalation without RPC',
    (tester) async {
      final c = AntTrainerSearchController(
        channelName: 'openbkool/range-profiles-sim',
      );
      c.snapshot = report(allowed: true);
      var active = false;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        if (call.method == 'enableManualTest') active = true;
        return {
          ...report(allowed: true, active: active),
          if (call.method == 'stopManualTest') 'running': false,
          'manualControl': {
            ...(report(allowed: true, active: active)['manualControl'] as Map),
            'authorizedRange': {
              'id': 'reported',
              'minPercent': 0,
              'maxPercent': 3,
            },
            if (call.method == 'setManualSlope') ...{
              'lastRequestedPercent': (call.arguments as Map)['percent'],
              'lastManualApiSuccess': {
                'requestedPercent': (call.arguments as Map)['percent'],
              },
            },
          },
        };
      });
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ManualRidePage(
            controller: c,
            device: device,
            initialProfile: 'reported',
          ),
        ),
      );
      await tester.pumpAndSettle();
      void select(double p) => tester
          .widget<DropdownButton<double>>(
            find.byKey(const ValueKey('manualRideSlope')),
          )
          .onChanged!(p);
      expect(
        tester
            .widget<DropdownButton<double>>(
              find.byKey(const ValueKey('manualRideSlope')),
            )
            .items!
            .length,
        41,
      );
      select(15);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Autorizar sesión manual'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Autorizar sesión'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'enableManualTest');
      expect((calls.single.arguments as Map)['rangeProfile'], 'reported');
      expect((calls.single.arguments as Map)['experimentalConfirmed'], true);
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const ValueKey('manualRangeProfile')),
            )
            .onChanged,
        isNull,
      );
      for (final p in [-5.0, 3.5, 15.0]) {
        select(p);
        await tester.pumpAndSettle();
      }
      expect(calls.length, 1);
      expect(find.textContaining('Solo previsualización:'), findsOneWidget);
      select(3);
      await tester.pumpAndSettle();
      expect(find.text('Pendiente ordenada: +3,0 %'), findsOneWidget);
      expect(find.text('Pendiente solicitada: +3,0 %'), findsOneWidget);
      select(-5);
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      expect(find.text('Pendiente ordenada: +3,0 %'), findsOneWidget);
      await tester.tap(find.text('LLANO 0 %'));
      await tester.pumpAndSettle();
      expect((calls.last.arguments as Map)['percent'], 0);
      await tester.tap(find.text('DETENER CONTROL'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'stopManualTest');
      await clean(tester, c);
    },
  );
  testWidgets('screen fits S7 and S20 without enabling blocked buttons', (
    tester,
  ) async {
    final c = AntTrainerSearchController(
      channelName: 'openbkool/manual-ride-sim',
    );
    c.snapshot = report();
    await show(tester, c);
    for (final size in [const Size(360, 640), const Size(412, 915)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('DETENER CONTROL'), findsOneWidget);
    }
    await clean(tester, c);
  });
}
