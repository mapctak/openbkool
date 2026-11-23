import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/trainer_session.dart';
import 'package:openbkool/training.dart';

void main() {
  testWidgets(
    'the same activated session survives pause and resume, then exports after native stop',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      final session = TrainerSession(training: c)..loading = false;
      const stream = MethodChannel('openbkool/training/events');
      final calls = <MethodCall>[];
      final copied = <String>[];
      final initial = <String, Object?>{
        'running': true,
        'trainingServiceActive': true,
        'backgroundPolicy': 'foreground_service',
        'sessionId': 'session',
        'selectedDevice': SavedTrainer.known.device,
        'connectionState': 'identity_verified',
        'telemetry': {'signal': 'receiving', 'speedKmh': 12, 'partial': true},
        'manualControl': {'eligible': true, 'enabled': false},
      };
      Future<void> publish(Map<String, Object?> report) async {
        await messenger.handlePlatformMessage(
          stream.name,
          const StandardMethodCodec().encodeSuccessEnvelope(report),
          (_) {},
        );
      }

      var nativeReport = initial;
      messenger.setMockMethodCallHandler(stream, (call) async => null);
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        if (call.method == 'exportCsv') {
          return 'event,session_id\nfinished:user_finish,session\n';
        }
        if (call.method == 'exportJson') {
          final finalized = (call.arguments as Map)['final'] == true;
          return {
            ...nativeReport,
            'recordState': finalized ? 'final' : 'partial',
          };
        }
        return {
          ...initial,
          'manualControl': {
            'enabled': true,
            'eligible': true,
            'state': 'active',
          },
        };
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      final listen = c.attachToTraining();
      await tester.pump();
      await publish(initial);
      await listen;
      await tester.pumpWidget(
        MaterialApp(home: TrainingPage(session: session)),
      );
      bool canIncrease() =>
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Aumentar pendiente',
                ),
              )
              .onPressed !=
          null;
      expect(trainingSlopes, List.generate(41, (i) => -5 + 0.5 * i));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(calls.single.method, 'activateControl');
      expect(calls.single.arguments, {'sessionId': 'session'});
      expect(canIncrease(), isTrue);
      await tester.tap(find.byTooltip('Exportar entrenamiento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar JSON parcial'));
      await tester.pumpAndSettle();
      expect(jsonDecode(copied.single)['recordState'], 'partial');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(calls, hasLength(2));
      await publish({
        ...initial,
        'manualControl': {'enabled': true, 'eligible': true, 'state': 'active'},
        'events': [
          {
            'event': 'android_lifecycle',
            'details': {'decision': 'continue_training'},
          },
        ],
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(c.running, isTrue);
      expect(c.snapshot['sessionId'], 'session');
      expect(calls, hasLength(2));
      expect(canIncrease(), isTrue);
      nativeReport = {
        ...initial,
        'running': false,
        'trainingServiceActive': false,
        'status': 'user_finish',
        'csvFile': 'training.csv',
        'manualControlEvents': [
          {'event': 'stop_requested', 'reason': 'user_finish'},
        ],
        'events': [
          {
            'event': 'android_lifecycle',
            'details': {'decision': 'user_finish'},
          },
        ],
        'manualControl': {
          'state': 'stopped',
          'stopped': true,
          'stopReason': 'user_finish',
        },
      };
      await publish(nativeReport);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(canIncrease(), isFalse);
      expect(c.snapshot['status'], 'user_finish');
      expect(find.text('TIEMPO DE ENTRENAMIENTO'), findsOneWidget);
      await tester.tap(find.byTooltip('Exportar entrenamiento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Exportar entrenamiento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar JSON'));
      await tester.pumpAndSettle();
      expect(copied[1], contains('finished:user_finish,session'));
      expect(jsonDecode(copied.last)['sessionId'], 'session');
      expect(jsonDecode(copied.last)['recordState'], 'final');
      expect(
        jsonDecode(copied.last)['manualControlEvents'].single['event'],
        'stop_requested',
      );
      expect(calls[1].arguments, {'sessionId': 'session', 'final': false});
      expect(calls[2].arguments, {'sessionId': 'session'});
      expect(calls[3].arguments, {'sessionId': 'session', 'final': true});
      expect(
        jsonDecode(copied.last)['events'].single['details']['decision'],
        'user_finish',
      );
      expect(calls.map((call) => call.method), [
        'activateControl',
        'exportJson',
        'exportCsv',
        'exportJson',
      ]);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      for (final channel in [stream, c.channel, SystemChannels.platform]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
