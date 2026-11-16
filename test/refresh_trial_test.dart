import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/manual_ride.dart';

class TrialController extends AntTrainerSearchController {
  TrialController() : super(channelName: 'openbkool/refresh-ui-sim');
  void emit(Map<String, Object?> value) {
    snapshot = value;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const device = <String, Object?>{
    'protocol': 'BKOOL_V1_PUBLIC',
    'deviceNumber': 30064,
    'deviceType': 112,
    'transmissionType': 5,
  };
  Map<String, Object?> report({
    bool active = false,
    num? remaining,
    bool eligible = true,
  }) => {
    'sessionId': 'refresh-ui',
    'running': true,
    'selectedDevice': device,
    'connectionState': 'identity_verified',
    'manualSessionPolicy': {'physicalEnabled': false},
    'refreshTrialPolicy': {
      'physicalEnabled': true,
      'maxPercent': 0.5,
      'maxDurationMs': 30000,
    },
    'manualControl': {
      'mode': 'refresh_trial_30s',
      'enabled': active,
      'eligible': eligible,
      'state': active ? 'active' : 'available',
      'remainingMs': remaining,
      'maxDurationMs': 30000,
    },
    'telemetry': {
      'elapsedMs': 2000,
      'signal': 'receiving',
      'speedKmh': 12,
      'powerW': 20,
      'cadenceRpm': 40,
    },
  };
  Future<void> show(WidgetTester tester, TrialController c) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ManualRidePage(controller: c, device: device, refreshTrial: true),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> clean(WidgetTester tester, TrialController c) async {
    c.snapshot = {...c.snapshot, 'running': false};
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    messenger.setMockMethodCallHandler(c.channel, null);
  }

  testWidgets(
    'trial requires consent, has only zero and half, and arming sends no slope',
    (tester) async {
      final c = TrialController();
      c.snapshot = report();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        final r = report(active: true, remaining: 30000);
        if (call.method == 'setManualSlope') {
          (r['manualControl'] as Map)['lastManualApiSuccess'] = {
            'requestedPercent': 0.5,
            'periodicRefresh': false,
          };
        }
        return r;
      });
      await show(tester, c);
      final dropdown = tester.widget<DropdownButton<double>>(
        find.byKey(const ValueKey('manualRideSlope')),
      );
      expect(dropdown.items!.map((i) => i.value), [0, 0.5]);
      await tester.tap(find.text('Preparar ensayo de 30 s'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Preparar ensayo de 30 s'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Autorizar ensayo'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'enableManualTest');
      final args = calls.single.arguments as Map;
      expect(args['controlMode'], 'refresh_trial_30s');
      expect(args['confirmed'], true);
      expect(args['experimentalConfirmed'], true);
      expect(find.text('Tiempo restante: 30 s'), findsOneWidget);
      await tester.tap(find.text('Solicitar +0,5 %'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'setManualSlope');
      expect((calls.last.arguments as Map)['percent'], 0.5);
      expect(find.text('Pendiente ordenada: +0,5 %'), findsOneWidget);
      expect(
        (c.snapshot['manualSessionPolicy'] as Map)['physicalEnabled'],
        false,
      );
      await clean(tester, c);
    },
  );
  testWidgets(
    'native refresh snapshots do not create Flutter sends and stop bypasses pending RPC',
    (tester) async {
      final c = TrialController();
      c.snapshot = report(active: true, remaining: 25000);
      final calls = <MethodCall>[];
      final pending = Completer<Map<String, Object?>>();
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        if (call.method == 'setManualSlope') return pending.future;
        return {
          ...report(),
          'running': false,
          'manualControl': {
            'mode': 'refresh_trial_30s',
            'enabled': false,
            'state': 'stopped',
            'stopped': true,
            'lastManualApiSuccess': {'requestedPercent': 0.5},
            'stopResult': 'zero_api_returned_unconfirmed',
          },
        };
      });
      await show(tester, c);
      for (final remaining in [25000, 20000, 15000]) {
        final r = report(active: true, remaining: remaining);
        (r['manualControl'] as Map)['lastManualApiSuccess'] = {
          'requestedPercent': 0.5,
          'periodicRefresh': true,
        };
        c.emit(r);
        await tester.pumpAndSettle();
      }
      expect(calls, isEmpty);
      expect(find.text('Pendiente ordenada: +0,5 %'), findsOneWidget);
      await tester.tap(find.text('LLANO 0 %'));
      await tester.pump();
      await tester.tap(find.text('DETENER CONTROL'));
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), ['setManualSlope', 'stopManualTest']);
      pending.complete(report(active: true, remaining: 10000));
      await tester.pumpAndSettle();
      expect((c.snapshot['manualControl'] as Map)['state'], 'stopped');
      expect(find.textContaining('solicitud de 0 % entregada'), findsOneWidget);
      await clean(tester, c);
    },
  );
  testWidgets(
    'expired or lost link blocks slope buttons but leaves stop available',
    (tester) async {
      final c = TrialController();
      c.snapshot = report(active: true, remaining: 0);
      await show(tester, c);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Solicitar +0,5 %'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'DETENER CONTROL'),
            )
            .onPressed,
        isNotNull,
      );
      c.emit(report(active: true, remaining: 10000, eligible: false));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'LLANO 0 %'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'DETENER CONTROL'),
            )
            .onPressed,
        isNotNull,
      );
      await clean(tester, c);
    },
  );
  testWidgets('trial background stops once and return does not arm or replay', (
    tester,
  ) async {
    final c = TrialController();
    c.snapshot = report(active: true, remaining: 20000);
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(c.channel, (call) async {
      calls.add(call);
      return {...report(), 'running': false};
    });
    await show(tester, c);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.single.method, 'stop');
    expect((calls.single.arguments as Map)['reason'], 'app_background');
    await clean(tester, c);
  });
  testWidgets(
    'zero failure stays explicit without replacing last accepted half percent',
    (tester) async {
      final c = TrialController();
      c.snapshot = {
        ...report(),
        'running': false,
        'manualControl': {
          'mode': 'refresh_trial_30s',
          'state': 'error',
          'enabled': false,
          'stopped': true,
          'lastManualApiSuccess': {'requestedPercent': 0.5},
          'stopResult': 'zero_api_error',
          'lastApiError': {'error': 'simulated zero failure'},
        },
      };
      await show(tester, c);
      expect(find.text('Pendiente ordenada: +0,5 %'), findsOneWidget);
      expect(find.textContaining('error al solicitar 0 %'), findsOneWidget);
      expect(find.textContaining('simulated zero failure'), findsOneWidget);
      await clean(tester, c);
    },
  );
  testWidgets('trial fits S7 and S20 with stop permanently visible', (
    tester,
  ) async {
    final c = TrialController();
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
