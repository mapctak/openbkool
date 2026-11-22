import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/trainer_session.dart';
import 'package:openbkool/training.dart';

import 'app_home_test.dart' show FakeTraining;

void main() {
  for (final immediate in [true, false]) {
    testWidgets(
      'warm-up with ${immediate ? 'immediate' : 'delayed'} eligibility',
      (tester) async {
        final training = FakeTraining();
        final session = TrainerSession(training: training)..loading = false;
        await tester.pumpWidget(
          MaterialApp(home: TrainingPage(session: session)),
        );
        await tester.pumpAndSettle();

        const selector = ValueKey('trainingSlope');
        bool canSelect() =>
            tester
                .widget<DropdownButton<double>>(find.byKey(selector))
                .onChanged !=
            null;
        expect(training.starts, hasLength(1));
        expect(find.textContaining('Buscando rodillo'), findsOneWidget);
        expect(canSelect(), isFalse);
        final report = {
          'sessionId': 'warm',
          'running': true,
          'trainingServiceActive': true,
          'selectedDevice': SavedTrainer.known.device,
          'connectionState': 'identity_verified',
          'manualControl': {'eligible': false, 'enabled': false},
          'telemetry': {
            'signal': 'receiving',
            'speedKmh': 21,
            'powerW': 127,
            'cadenceRpm': 81,
            'distanceM': 140,
            'elapsedMs': 8750,
          },
          'virtualElevation': [
            [0, 0, 0],
            [140, 0, 0],
          ],
        };

        if (!immediate) {
          training.emit(report);
          await tester.pump();
          expect(
            find.textContaining('Esperando identificación ANT'),
            findsOneWidget,
          );
          expect(find.text('127'), findsOneWidget);
          expect(find.text('00:00:08'), findsOneWidget);
          expect(find.text('0,14 km'), findsOneWidget);
          expect(find.text('Autorizar rango completo'), findsNothing);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          expect(training.stops, 0);
        }
        training.emit({
          ...report,
          'manualControl': {'eligible': true, 'enabled': false},
        });
        if (!immediate) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await tester.pumpAndSettle();
        expect(training.starts, hasLength(1));
        expect(training.snapshot['sessionId'], 'warm');
        expect(find.text('¡CALENTAMIENTO COMPLETADO!'), findsOneWidget);
        expect(find.text('Autorizar rango completo'), findsOneWidget);
        expect(canSelect(), isFalse);
        await tester.pump(const Duration(seconds: 2));
        expect(find.textContaining('CALENTAMIENTO'), findsNothing);
        expect(canSelect(), isFalse);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }

  testWidgets('stop while subscribing cancels the pending native start', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final controller = AntTrainerSearchController(
      channelName: 'openbkool/training',
    );
    final session = TrainerSession(training: controller)..loading = false;
    const events = MethodChannel('openbkool/training/events');
    final calls = <String>[];
    final idle = {'running': false, 'status': 'not_started'};
    messenger.setMockMethodCallHandler(events, (call) async => null);
    messenger.setMockMethodCallHandler(controller.channel, (call) async {
      calls.add(call.method);
      return idle;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(events, null);
      messenger.setMockMethodCallHandler(controller.channel, null);
    });

    await tester.pumpWidget(MaterialApp(home: TrainingPage(session: session)));
    await tester.pump();
    await tester.tap(find.text('DETENER ENTRENAMIENTO'));
    await tester.pump();
    final delivered = Completer<void>();
    unawaited(
      messenger.handlePlatformMessage(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope(idle),
        (_) => delivered.complete(),
      ),
    );
    await delivered.future;
    await tester.pumpAndSettle();
    expect(calls, ['stop']);
    expect(find.textContaining('CALENTAMIENTO'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
