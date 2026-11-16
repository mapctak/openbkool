import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/training.dart';
import 'package:openbkool/workout_summary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  testWidgets(
    'physical app defaults to trial and continuous option cannot be selected',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(home: TrainingPage(controller: c, simple: true)),
      );
      await tester.pumpAndSettle();
      final selector = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('controlMode')),
      );
      expect(selector.initialValue, 'trial_30s');
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const ValueKey('controlMode')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(
        dropdown.items!
            .singleWhere((i) => i.value == 'continuous_experimental')
            .enabled,
        false,
      );
      selector.onChanged!('continuous_experimental');
      await tester.pump();
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.descendant(
                of: find.byKey(const ValueKey('controlMode')),
                matching: find.byType(DropdownButton<String>),
              ),
            )
            .value,
        'trial_30s',
      );
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      messenger.setMockMethodCallHandler(c.channel, null);
    },
  );
  testWidgets(
    'simulated authorized continuous state has elapsed time and commands beyond 30s',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      c.snapshot = {
        'sessionId': 'sim-only',
        'running': true,
        'manualControl': {
          'mode': 'continuous_experimental',
          'continuousControlEnabled': true,
          'enabled': true,
          'eligible': true,
          'everEnabled': true,
          'state': 'active',
          'elapsedControlMs': 45000,
          'remainingMs': null,
          'maxDurationMs': null,
        },
      };
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return {
          ...c.snapshot,
          'manualControl': {
            ...c.snapshot['manualControl'] as Map,
            'elapsedControlMs': 61000,
            'lastSubmittedPercent': 0.5,
            'lastRequestedPercent': 0.5,
            'lastManualApiSuccess': {
              'requestedPercent': 0.5,
              'stopRequest': false,
            },
          },
        };
      });
      await tester.pumpWidget(
        MaterialApp(home: TrainingPage(controller: c, simple: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tiempo de control: 45 s'), findsOneWidget);
      expect(find.textContaining('Prueba caducada'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'LLANO 0 %'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, '+'));
      await tester.pumpAndSettle();
      expect(find.text('Pendiente ordenada: +0,5 %'), findsOneWidget);
      expect(find.text('Tiempo de control: 61 s'), findsOneWidget);
      expect(calls.single.method, 'setManualSlope');
      c.snapshot = {...c.snapshot, 'running': false};
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      messenger.setMockMethodCallHandler(c.channel, null);
    },
  );
  testWidgets(
    'failed stop is visible without claiming flat or losing accepted order',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ManualOrderSummary(
              report: {
                'running': false,
                'manualControl': {
                  'state': 'error',
                  'stopped': true,
                  'stopResult': 'zero_api_error',
                  'lastManualApiSuccess': {
                    'requestedPercent': 1.0,
                    'stopRequest': false,
                  },
                  'lastApiError': {'error': 'zero failed'},
                },
              },
            ),
          ),
        ),
      );
      expect(find.text('Control: Error'), findsOneWidget);
      expect(find.text('Última pendiente ordenada: +1,0 %'), findsOneWidget);
      expect(
        find.text(
          'Control bloqueado por error · Resistencia física actual desconocida.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Control finalizado · Se solicitó 0 %'),
        findsNothing,
      );
    },
  );
  test('uncertain RPC blocks commands until a new connection, but stop remains possible', () async {
    final c = AntTrainerSearchController(channelName: 'openbkool/training');
    c.snapshot = {'sessionId': 'uncertain', 'running': true};
    final calls = <String>[];
    messenger.setMockMethodCallHandler(c.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'setManualSlope') {
        throw PlatformException(code: 'ipc_timeout', message: 'No response');
      }
      return {
        'sessionId': 'uncertain',
        'running': false,
        'manualControl': {'enabled': false},
      };
    });
    await c.manualAction('setManualSlope', percent: 1.0);
    expect(c.controlTransportUncertain, true);
    await c.manualAction('setManualSlope', percent: 0.5);
    await c.manualAction('enableManualTest', confirmed: true);
    expect(calls, ['setManualSlope']);
    await c.manualAction('stopManualTest');
    expect(calls, ['setManualSlope', 'stopManualTest']);
    expect(c.controlTransportUncertain, true);
    c.dispose();
    messenger.setMockMethodCallHandler(c.channel, null);
    final fresh = AntTrainerSearchController(channelName: 'openbkool/training');
    expect(fresh.controlTransportUncertain, false);
    fresh.dispose();
  });
}
