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
  Map<String, Object?> active() => {
    'sessionId': 'lifecycle',
    'running': true,
    'manualControl': {
      'state': 'active',
      'enabled': true,
      'eligible': true,
      'everEnabled': true,
      'remainingMs': 20000,
      'lastManualApiSuccess': {'requestedPercent': 1.0},
    },
  };
  testWidgets(
    'background stops once, resume sends nothing and leaves control stopped',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      c.snapshot = active();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return {
          'sessionId': 'lifecycle',
          'running': false,
          'manualControl': {'state': 'stopped', 'stopped': true},
        };
      });
      await tester.pumpWidget(
        MaterialApp(home: TrainingPage(controller: c, simple: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Control: Activo'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), ['stop']);
      expect((calls.single.arguments as Map)['reason'], 'app_background');
      expect(find.text('Control: Detenido'), findsOneWidget);
      expect(c.running, false);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      messenger.setMockMethodCallHandler(c.channel, null);
    },
  );
  testWidgets(
    'closing training routes an explicit screen_closed stop before popping',
    (tester) async {
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      c.snapshot = active();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return {
          'running': false,
          'manualControl': {'state': 'stopped'},
        };
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TrainingPage(controller: c, simple: true),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), ['stop']);
      expect((calls.single.arguments as Map)['reason'], 'screen_closed');
      expect(find.text('Open'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      messenger.setMockMethodCallHandler(c.channel, null);
    },
  );
  testWidgets('all six native control states have explicit labels', (
    tester,
  ) async {
    for (final entry in {
      'inactive': 'Inactivo',
      'available': 'Disponible',
      'active': 'Activo',
      'stopping': 'Deteniendo',
      'stopped': 'Detenido',
      'error': 'Error',
    }.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualOrderSummary(
              report: {
                'manualControl': {'state': entry.key},
              },
            ),
          ),
        ),
      );
      expect(find.text('Control: ${entry.value}'), findsOneWidget);
    }
  });
}
