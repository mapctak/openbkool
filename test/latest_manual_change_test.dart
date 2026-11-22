import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/trainer_session.dart';
import 'package:openbkool/training.dart';

class LatestUiController extends AntTrainerSearchController {
  LatestUiController() : super(channelName: 'openbkool/latest-ui-sim');
  void emit(Map<String, Object?> r) {
    snapshot = {...snapshot, ...r};
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<String, Object?> report({
    num accepted = 3,
    num? pending,
    bool stopped = false,
    bool error = false,
    bool eligible = true,
  }) => {
    'sessionId': 'latest',
    'trainingServiceActive': true,
    'selectedDevice': SavedTrainer.known.device,
    'connectionState': 'identity_verified',
    'running': !stopped,
    'manualSessionPolicy': {'physicalEnabled': true},
    'manualControl': {
      'mode': 'manual_session',
      'authorizedRange': {'id': 'original'},
      'enabled': !stopped,
      'eligible': eligible,
      'stopped': stopped,
      'state': stopped ? 'stopped' : 'active',
      'lastManualApiSuccess': {
        'requestedPercent': accepted,
        'stopRequest': false,
      },
      'pendingManualChange': pending == null ? null : {'percent': pending},
      if (error) 'lastApiError': {'error': 'simulated zero failed'},
      'lastRequestedPercent': pending ?? accepted,
    },
    'telemetry': {'signal': 'receiving', 'powerW': 80, 'elapsedMs': 188458},
  };
  Future<void> show(WidgetTester tester, LatestUiController c) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: TrainingPage(session: TrainerSession(training: c)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> clean(WidgetTester tester, LatestUiController c) async {
    c.snapshot = {...c.snapshot, 'running': false};
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    messenger.setMockMethodCallHandler(c.channel, null);
  }

  Future<void> lower(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Disminuir pendiente'));
    await tester.pump();
  }

  testWidgets('step buttons mark adjustments including return to zero', (
    tester,
  ) async {
    final c = LatestUiController()..snapshot = report(accepted: 0);
    final calls = <Map>[];
    messenger.setMockMethodCallHandler(c.channel, (call) async {
      calls.add(call.arguments as Map);
      return report();
    });
    await show(tester, c);
    await tester.tap(find.byTooltip('Aumentar pendiente'));
    await tester.pumpAndSettle();
    await lower(tester);
    await tester.pumpAndSettle();
    expect(calls.map((call) => call['percent']), [0.5, 0.0]);
    expect(calls.map((call) => call['rapidAdjustment']), [true, true]);
    expect(calls.every((call) => call['uiQueueMs'] is int), isTrue);
    await clean(tester, c);
  });

  testWidgets(
    'rapid edits during native RPC retain only latest LLANO and show native pending until accepted',
    (tester) async {
      final c = LatestUiController()..snapshot = report(accepted: 1.5);
      final calls = <MethodCall>[];
      final first = Completer<Map<String, Object?>>();
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        if (calls.length == 1) return first.future;
        return report(accepted: 1.5, pending: 0);
      });
      await show(tester, c);
      await lower(tester);
      await lower(tester);
      await lower(tester);
      expect(calls.length, 1);
      expect(c.pendingManualPercent, 0);
      expect(
        (c.snapshot['manualControl']
            as Map)['lastManualApiSuccess']['requestedPercent'],
        1.5,
      );
      expect(find.text('LLANO 0 %'), findsNothing);
      first.complete(report(accepted: 1.5, pending: 1));
      await tester.pumpAndSettle();
      expect(calls.map((e) => (e.arguments as Map)['percent']), [1.0, 0]);
      expect(
        (c.snapshot['manualControl']
            as Map)['lastManualApiSuccess']['requestedPercent'],
        1.5,
      );
      expect(c.pendingManualPercent, 0);
      c.emit(report(accepted: 0));
      await tester.pumpAndSettle();
      expect(
        (c.snapshot['manualControl']
            as Map)['lastManualApiSuccess']['requestedPercent'],
        0,
      );
      expect(find.textContaining('Cambio pendiente ·'), findsNothing);
      expect(
        (c.snapshot['clientManualChanges'] as List).any(
          (e) => (e as Map)['event'] == 'superseded_before_native',
        ),
        true,
      );
      await clean(tester, c);
    },
  );

  testWidgets(
    'stop discards client deferred input and late RPC cannot restore it',
    (tester) async {
      final c = LatestUiController()..snapshot = report(accepted: 1);
      final calls = <MethodCall>[];
      final first = Completer<Map<String, Object?>>();
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return call.method == 'setManualSlope'
            ? first.future
            : report(stopped: true);
      });
      await show(tester, c);
      await lower(tester);
      await lower(tester);
      await tester.tap(find.text('DETENER ENTRENAMIENTO'));
      await tester.pumpAndSettle();
      first.complete(report(pending: 2));
      await tester.pumpAndSettle();
      expect(calls.map((e) => e.method), ['setManualSlope', 'stop']);
      expect(c.running, false);
      expect(c.pendingManualPercent, isNull);
      await clean(tester, c);
    },
  );

  testWidgets(
    'native background stop and link loss discard deferred selection',
    (tester) async {
      for (final background in [false, true]) {
        final c = LatestUiController()..snapshot = report(accepted: 1);
        final calls = <MethodCall>[];
        final first = Completer<Map<String, Object?>>();
        messenger.setMockMethodCallHandler(c.channel, (call) async {
          calls.add(call);
          return call.method == 'setManualSlope'
              ? first.future
              : report(stopped: true);
        });
        await show(tester, c);
        await lower(tester);
        await lower(tester);
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
        }
        first.complete(
          background ? report(stopped: true) : report(eligible: false),
        );
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(calls.where((e) => e.method == 'setManualSlope').length, 1);
        expect(c.pendingManualPercent, isNull);
        await clean(tester, c);
      }
    },
  );
}
