import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/experimental_slopes.dart';
import 'package:openbkool/ant_trainer_search.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<String, Object?> ready() => {
    'sessionId': 'experimental',
    'running': true,
    'connectionState': 'identity_verified',
    'manualControl': {
      'enabled': false,
      'eligible': true,
      'state': 'available',
      'remainingMs': null,
    },
  };
  Future<void> show(WidgetTester tester, AntTrainerSearchController c) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: ExperimentalSlopesPage(controller: c)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(
    WidgetTester tester,
    AntTrainerSearchController c,
  ) async {
    c.snapshot = {...c.snapshot, 'running': false};
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    messenger.setMockMethodCallHandler(c.channel, null);
  }

  testWidgets('four percent stays blocked after accepted three percent', (
    tester,
  ) async {
    final c = AntTrainerSearchController(channelName: 'openbkool/training');
    c.snapshot = ready();
    c.snapshot['manualControl'] = {
      ...(c.snapshot['manualControl'] as Map),
      'lastManualApiSuccess': {'requestedPercent': 3.0},
      'threePercentAttempted': true,
    };
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(c.channel, (call) async {
      calls.add(call);
      return null;
    });
    await show(tester, c);
    for (final index in [5]) {
      await tester.tap(find.byKey(const ValueKey('experimentalLevel')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(
              '${experimentalPercent(experimentalSlopeLevels[index].percent)} · bloqueado',
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(experimentalSlopeLevels[index].hex),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Habilitar prueba de este nivel',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '+'))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('experimentalBlocker')), findsOneWidget);
    }
    expect(calls, isEmpty);
    await dispose(tester, c);
  });
  testWidgets(
    'isolated two requires additional recovery consent and arms without sending',
    (tester) async {
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      c.snapshot = ready();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return {
          ...c.snapshot,
          'manualControl': {
            'enabled': true,
            'eligible': true,
            'state': 'active',
            'mode': 'isolated_two_percent',
            'remainingMs': 30000,
            'twoPercentAttempted': call.method == 'setManualSlope',
            'lastManualApiSuccess': {
              'requestedPercent': call.method == 'setManualSlope'
                  ? (call.arguments as Map)['percent']
                  : 1.0,
            },
          },
        };
      });
      await show(tester, c);
      await tester.tap(find.byKey(const ValueKey('experimentalLevel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+2,0 % · experimental').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Habilitar prueba de este nivel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activar prueba'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('Autorizar un único +2 %'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(360, 640));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Habilitar prueba de este nivel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activar prueba'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar recuperación y autorizar +2 %'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'enableManualTest');
      expect(
        (calls.single.arguments as Map)['controlMode'],
        'isolated_two_percent',
      );
      expect((calls.single.arguments as Map)['experimentalConfirmed'], true);
      await tester.tap(find.widgetWithText(OutlinedButton, '+'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'setManualSlope');
      expect((calls.last.arguments as Map)['percent'], 2.0);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '+'))
            .onPressed,
        isNull,
      );
      expect(find.text('LLANO 0 %'), findsOneWidget);
      expect(find.text('Detener control'), findsOneWidget);
      await dispose(tester, c);
    },
  );
  testWidgets(
    'isolated three requires additional recovery consent and arms without sending',
    (tester) async {
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      c.snapshot = ready();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return {
          ...c.snapshot,
          'manualControl': {
            'enabled': true,
            'eligible': true,
            'state': 'active',
            'mode': 'isolated_three_percent',
            'remainingMs': 30000,
            'threePercentAttempted': call.method == 'setManualSlope',
            'lastManualApiSuccess': {
              'requestedPercent': call.method == 'setManualSlope'
                  ? (call.arguments as Map)['percent']
                  : 1.0,
            },
          },
        };
      });
      await show(tester, c);
      await tester.tap(find.byKey(const ValueKey('experimentalLevel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+3,0 % · experimental').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Habilitar prueba de este nivel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activar prueba'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('Autorizar un único +3 %'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(360, 640));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Habilitar prueba de este nivel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activar prueba'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar recuperación y autorizar +3 %'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'enableManualTest');
      expect(
        (calls.single.arguments as Map)['controlMode'],
        'isolated_three_percent',
      );
      expect((calls.single.arguments as Map)['experimentalConfirmed'], true);
      await tester.tap(find.widgetWithText(OutlinedButton, '+'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'setManualSlope');
      expect((calls.last.arguments as Map)['percent'], 3.0);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '+'))
            .onPressed,
        isNull,
      );
      expect(find.text('LLANO 0 %'), findsOneWidget);
      expect(find.text('Detener control'), findsOneWidget);
      await dispose(tester, c);
    },
  );
  testWidgets(
    'validated level needs explicit confirmation and arming sends no slope',
    (tester) async {
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      c.snapshot = ready();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        expect(call.method, 'enableManualTest');
        expect((call.arguments as Map)['confirmed'], true);
        expect((call.arguments as Map)['controlMode'], 'trial_30s');
        return {
          ...c.snapshot,
          'manualControl': {
            'enabled': true,
            'eligible': true,
            'state': 'active',
            'remainingMs': 30000,
          },
        };
      });
      await show(tester, c);
      await tester.tap(find.text('Habilitar prueba de este nivel'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Activar prueba'));
      await tester.pumpAndSettle();
      expect(calls.length, 1);
      expect(find.text('Tiempo restante: 30 s'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '+'))
            .onPressed,
        isNotNull,
      );
      await dispose(tester, c);
    },
  );
  testWidgets(
    'API error keeps last ordered slope and stop remains accessible',
    (tester) async {
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      c.snapshot = {
        ...ready(),
        'manualControl': {
          'enabled': true,
          'eligible': true,
          'state': 'active',
          'remainingMs': 20000,
          'lastManualApiSuccess': {
            'requestedPercent': 1.0,
            'stopRequest': false,
          },
        },
      };
      final calls = <String>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call.method);
        if (call.method == 'stopManualTest') {
          return {
            ...c.snapshot,
            'running': false,
            'manualControl': {
              'enabled': false,
              'stopped': true,
              'state': 'error',
              'stopResult': 'zero_not_requested:api_fault_no_retry',
              'lastManualApiSuccess': {
                'requestedPercent': 1.0,
                'stopRequest': false,
              },
            },
          };
        }
        return {
          ...c.snapshot,
          'manualControl': {
            'enabled': false,
            'faulted': true,
            'eligible': false,
            'state': 'error',
            'remainingMs': 19000,
            'lastManualApiSuccess': {
              'requestedPercent': 1.0,
              'stopRequest': false,
            },
            'lastApiError': {'error': 'IPC failed'},
          },
        };
      });
      await show(tester, c);
      await tester.tap(find.widgetWithText(OutlinedButton, '−'));
      await tester.pumpAndSettle();
      expect(find.text('Última pendiente ordenada: +1,0 %'), findsOneWidget);
      expect(find.textContaining('IPC failed'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '+'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Detener control'));
      await tester.pumpAndSettle();
      expect(calls, ['setManualSlope', 'stopManualTest']);
      expect(find.textContaining('no se solicitó 0 %'), findsOneWidget);
      await dispose(tester, c);
    },
  );
  testWidgets('experimental controls fit S7 and S20 and remain unarmed', (
    tester,
  ) async {
    final c = AntTrainerSearchController(channelName: 'openbkool/training');
    c.snapshot = {'running': false};
    await show(tester, c);
    for (final size in [const Size(360, 640), const Size(412, 915)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await dispose(tester, c);
  });
}
