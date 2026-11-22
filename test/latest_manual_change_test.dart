import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/manual_ride.dart';

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
    'telemetry': {'powerW': 80, 'elapsedMs': 188458},
  };
  Future<void> show(WidgetTester tester, LatestUiController c) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ManualRidePage(
          controller: c,
          device: const {
            'protocol': 'BKOOL_V1_PUBLIC',
            'deviceNumber': 30064,
            'deviceType': 112,
            'transmissionType': 5,
          },
        ),
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

  void select(WidgetTester tester, double p) => tester
      .widget<DropdownButton<double>>(
        find.byKey(const ValueKey('manualRideSlope')),
      )
      .onChanged!(p);

  testWidgets(
    'rapid edits during native RPC retain only latest LLANO and show native pending until accepted',
    (tester) async {
      final c = LatestUiController()..snapshot = report();
      final calls = <MethodCall>[];
      final first = Completer<Map<String, Object?>>();
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        if (calls.length == 1) return first.future;
        return report(pending: 0);
      });
      await show(tester, c);
      select(tester, 2);
      await tester.pump();
      select(tester, 1);
      await tester.pump();
      await tester.tap(find.text('LLANO 0 %'));
      await tester.pump();
      expect(calls.length, 1);
      expect(c.pendingManualPercent, 0);
      expect(find.text('Pendiente ordenada: +3,0 %'), findsOneWidget);
      expect(find.textContaining('LLANO pendiente:'), findsOneWidget);
      first.complete(report(pending: 2));
      await tester.pumpAndSettle();
      expect(calls.map((e) => (e.arguments as Map)['percent']), [2, 0]);
      expect(find.text('Pendiente ordenada: +3,0 %'), findsOneWidget);
      expect(c.pendingManualPercent, 0);
      c.emit(report(accepted: 0));
      await tester.pumpAndSettle();
      expect(find.text('Pendiente ordenada: 0,0 %'), findsOneWidget);
      expect(find.text('Cambio pendiente: ninguno'), findsOneWidget);
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
      final c = LatestUiController()..snapshot = report();
      final calls = <MethodCall>[];
      final first = Completer<Map<String, Object?>>();
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return call.method == 'setManualSlope'
            ? first.future
            : report(stopped: true);
      });
      await show(tester, c);
      select(tester, 2);
      await tester.pump();
      select(tester, 0);
      await tester.pump();
      await tester.tap(find.text('DETENER CONTROL'));
      await tester.pumpAndSettle();
      first.complete(report(pending: 2));
      await tester.pumpAndSettle();
      expect(calls.map((e) => e.method), ['setManualSlope', 'stopManualTest']);
      expect(c.running, false);
      expect(c.pendingManualPercent, isNull);
      await clean(tester, c);
    },
  );

  testWidgets(
    'background and link loss discard deferred selection without automatic recovery',
    (tester) async {
      for (final background in [false, true]) {
        final c = LatestUiController()..snapshot = report();
        final calls = <MethodCall>[];
        final first = Completer<Map<String, Object?>>();
        messenger.setMockMethodCallHandler(c.channel, (call) async {
          calls.add(call);
          return call.method == 'setManualSlope'
              ? first.future
              : report(stopped: true);
        });
        await show(tester, c);
        select(tester, 2);
        await tester.pump();
        select(tester, 0);
        await tester.pump();
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
        }
        first.complete(background ? report() : report(eligible: false));
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

  testWidgets(
    'failed LLANO preserves accepted grade and visible warning; profile limits prominent',
    (tester) async {
      final c = LatestUiController()..snapshot = report();
      messenger.setMockMethodCallHandler(
        c.channel,
        (_) async => report(error: true),
      );
      await show(tester, c);
      await tester.tap(find.text('LLANO 0 %'));
      await tester.pumpAndSettle();
      expect(find.text('Pendiente ordenada: +3,0 %'), findsOneWidget);
      expect(find.textContaining('AVISO: LLANO no entregado'), findsOneWidget);
      expect(find.textContaining('Positivo termina en +3 %.'), findsOneWidget);
      await clean(tester, c);
    },
  );
}
