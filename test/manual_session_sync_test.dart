import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/trainer_session.dart';
import 'package:openbkool/training.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real controller RPC and RX events preserve accepted sequence through stop',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      var sequence = 0;
      var enabled = false;
      var stopped = false;
      double? selected, accepted;
      Map<String, Object?>? success, stop;
      final history = <Map<String, Object?>>[];
      Map<String, Object?> report() => {
        'sessionId': 'sync',
        'reportSequence': ++sequence,
        'running': sequence > 1 && !stopped,
        'status': stopped ? 'manual_stop' : 'running',
        'manualControl': {
          'enabled': enabled,
          'eligible': true,
          'everEnabled': enabled || stopped,
          'stopped': stopped,
          'lastRequestedPercent': selected,
          'lastSubmittedPercent': accepted,
          'lastManualApiSuccess': success,
          'lastStopCommand': stop,
          'stopResult': stopped ? 'zero_api_returned_unconfirmed' : null,
        },
        'manualControlEvents': List.of(history),
        'telemetry': {'signal': 'receiving', 'powerW': 100},
      };
      Future<void> rx(Map<String, Object?> snapshot) async {
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          'openbkool/training/events',
          const StandardMethodCodec().encodeSuccessEnvelope(snapshot),
          (_) => done.complete(),
        );
        await done.future;
      }

      messenger.setMockMethodCallHandler(
        const MethodChannel('openbkool/training/events'),
        (call) async {
          if (call.method == 'listen') scheduleMicrotask(() => rx(report()));
          return null;
        },
      );
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        if (call.method == 'start') {
          await rx(report());
          return null;
        }
        if (call.method == 'authorizeControl') {
          expect((call.arguments as Map)['confirmed'], true);
          enabled = true;
          history.add({'event': 'enabled'});
        } else if (call.method == 'setManualSlope') {
          selected = (call.arguments as Map)['percent'] as double;
          accepted = selected;
          history.add({'event': 'request', 'requestedPercent': selected});
          success = {
            'event': 'api_returned',
            'requestedPercent': accepted,
            'stopRequest': false,
          };
          history.add(success!);
        } else if (call.method == 'stop') {
          stopped = true;
          enabled = false;
          stop = {
            'event': 'api_returned',
            'requestedPercent': 0.0,
            'stopRequest': true,
          };
          history.add({'event': 'stop_requested', 'reason': 'manual_stop'});
          history.add(stop!);
        }
        return report();
      });
      final start = c.start(
        'training_connected',
        device: const {
          'protocol': 'BKOOL_V1_PUBLIC',
          'deviceNumber': 30064,
          'deviceType': 112,
          'transmissionType': 5,
        },
      );
      await tester.runAsync(() => start);
      await c.authorizeControl('sync');
      final session = TrainerSession(training: c);
      await tester.pumpWidget(
        MaterialApp(home: TrainingPage(session: session)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Última pendiente aceptada por la API · —'),
        findsOneWidget,
      );
      for (final step in [
        ('+', '+0,5'),
        ('+', '+1,0'),
        ('−', '+0,5'),
        ('LLANO 0 %', '0,0'),
      ]) {
        final old = Map<String, Object?>.from(c.snapshot);
        await tester.tap(find.widgetWithText(OutlinedButton, step.$1));
        await tester.pumpAndSettle();
        expect(
          find.text('Última pendiente aceptada por la API · ${step.$2} %'),
          findsOneWidget,
        );
        await rx(
          old,
        ); // Delayed pre-command telemetry snapshot must not roll back slope.
        await tester.pump();
        expect(
          find.text('Última pendiente aceptada por la API · ${step.$2} %'),
          findsOneWidget,
        );
        await rx({
          ...report(),
          'telemetry': {'signal': 'receiving', 'powerW': 150},
        });
        await tester.pump();
        expect(
          find.text('Última pendiente aceptada por la API · ${step.$2} %'),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('DETENER ENTRENAMIENTO'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '0 % solicitado al detener. Resistencia física sin confirmar.',
        ),
        findsOneWidget,
      );
      expect(
        history
            .where(
              (e) => e['event'] == 'api_returned' && e['stopRequest'] != true,
            )
            .map((e) => e['requestedPercent']),
        [0.5, 1.0, 0.5, 0.0],
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(c.channel, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel('openbkool/training/events'),
        null,
      );
    },
  );
}
