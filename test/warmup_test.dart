import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/trainer_session.dart';
import 'package:openbkool/training.dart';

import 'app_home_test.dart' show FakeTraining;

class ActivationProbe extends FakeTraining {
  final activations = <String>[];

  @override
  Future<void> activateControl(String sessionId) async {
    activations.add(sessionId);
  }
}

void main() {
  for (final immediate in [true, false]) {
    testWidgets(
      'warm-up with ${immediate ? 'immediate' : 'delayed'} eligibility',
      (tester) async {
        final training = ActivationProbe();
        final session = TrainerSession(training: training)..loading = false;
        await tester.pumpWidget(
          MaterialApp(home: TrainingPage(session: session)),
        );
        await tester.pumpAndSettle();

        bool canSelect() =>
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == 'Aumentar pendiente',
                  ),
                )
                .onPressed !=
            null;
        expect(training.starts, hasLength(1));
        expect(find.text('CALENTAMIENTO'), findsOneWidget);
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
          expect(find.text('CALENTAMIENTO'), findsOneWidget);
          expect(find.text('127'), findsOneWidget);
          expect(find.text('00:00:08'), findsOneWidget);
          expect(find.text('0,14 km'), findsOneWidget);
          expect(find.text('Autorizar control de pendiente'), findsNothing);
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
        expect(training.activations, ['warm']);
        expect(find.byType(AlertDialog), findsNothing);
        expect(canSelect(), isFalse);
        expect(find.text('CALENTAMIENTO'), findsOneWidget);
        training.emit({
          ...report,
          'trainingElapsedMs': 0,
          'warmupElapsedMs': 8750,
          'manualControl': {
            'eligible': true,
            'enabled': true,
            'state': 'active',
          },
        });
        await tester.pumpAndSettle();
        expect(find.text('¡COMIENZA EL ENTRENAMIENTO!'), findsOneWidget);
        expect(find.text('00:00:00'), findsOneWidget);
        expect(find.text('TIEMPO DE ENTRENAMIENTO'), findsOneWidget);
        expect(canSelect(), isTrue);
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('¡COMIENZA EL ENTRENAMIENTO!'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }

  testWidgets(
    'identity, foreground service and terminal link loss gate activation',
    (tester) async {
      final training = ActivationProbe();
      final session = TrainerSession(training: training)..loading = false;
      await tester.pumpWidget(
        MaterialApp(home: TrainingPage(session: session)),
      );
      await tester.pumpAndSettle();
      final report = {
        'sessionId': 'next-session',
        'running': true,
        'trainingServiceActive': true,
        'selectedDevice': SavedTrainer.known.device,
        'connectionState': 'identity_verified',
        'manualControl': {
          'eligible': true,
          'enabled': false,
          'state': 'available',
        },
        'telemetry': {'signal': 'receiving'},
      };
      bool canSelect() =>
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Aumentar pendiente',
                ),
              )
              .onPressed !=
          null;
      training.emit({
        ...report,
        'manualControl': {
          'eligible': false,
          'enabled': false,
          'unavailableReason': 'manufacturer_model_not_verified',
        },
      });
      await tester.pumpAndSettle();
      expect(training.activations, isEmpty);
      training.emit({...report, 'connectionState': 'waiting_for_identity'});
      await tester.pumpAndSettle();
      expect(training.activations, isEmpty);
      training.emit({...report, 'trainingServiceActive': false});
      await tester.pumpAndSettle();
      expect(training.activations, isEmpty);
      training.emit(report);
      await tester.pumpAndSettle();
      expect(training.activations, ['next-session']);
      expect(canSelect(), isFalse);
      expect(find.text('CALENTAMIENTO'), findsOneWidget);
      expect(find.text('Guardar autorización'), findsNothing);
      final active = {
        ...report,
        'manualControl': {'eligible': true, 'enabled': true, 'state': 'active'},
      };
      training.emit(active);
      await tester.pumpAndSettle();
      expect(canSelect(), isTrue);
      expect(find.text('CALENTAMIENTO'), findsNothing);
      training.emit({
        ...active,
        'telemetry': {'signal': 'signal_lost'},
      });
      await tester.pumpAndSettle();
      expect(canSelect(), isFalse);
      expect(training.activations, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      await training.stop();
      session.dispose();
    },
  );

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
    expect(find.text('CALENTAMIENTO'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
