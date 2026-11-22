import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/trainer_session.dart';
import 'package:openbkool/training.dart';

void main() {
  testWidgets(
    'the full selector requires consent, reports background stop and exports',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      final session = TrainerSession(training: c);
      const stream = MethodChannel('openbkool/training/events');
      final calls = <MethodCall>[];
      final copied = <String>[];
      final initial = <String, Object?>{
        'running': true,
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
          return 'event,session_id\nfinished:app_background,session\n';
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
          'manualControl': {'enabled': true, 'eligible': true},
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
      final selector = find.byKey(const ValueKey('trainingSlope'));
      var dropdown = tester.widget<DropdownButton<double>>(selector);
      expect(
        dropdown.items!.map((item) => item.value),
        List.generate(41, (i) => -5 + 0.5 * i),
      );
      expect(dropdown.onChanged, isNull);
      await tester.tap(find.text('Autorizar rango completo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Autorizar rango completo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Autorizar sesión'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'authorizeControl');
      expect(calls.single.arguments, {
        'sessionId': 'session',
        'confirmed': true,
      });
      dropdown = tester.widget<DropdownButton<double>>(selector);
      expect(dropdown.onChanged, isNotNull);
      await tester.tap(find.text('Copiar JSON parcial'));
      await tester.pumpAndSettle();
      expect(jsonDecode(copied.single)['recordState'], 'partial');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(calls, hasLength(2)); // Android owns the background decision.
      nativeReport = {
        ...initial,
        'running': false,
        'status': 'app_background',
        'csvFile': 'training.csv',
        'manualControlEvents': [
          {'event': 'stop_requested', 'reason': 'app_background'},
        ],
        'events': [
          {
            'event': 'android_lifecycle',
            'details': {'decision': 'app_background'},
          },
        ],
        'manualControl': {
          'state': 'stopped',
          'stopped': true,
          'stopReason': 'app_background',
        },
      };
      await publish(nativeReport);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<double>>(selector).onChanged, isNull);
      expect(
        find.text('Motivo de parada · app en segundo plano'),
        findsOneWidget,
      );
      expect(find.textContaining('Bloquear la pantalla'), findsOneWidget);
      await tester.tap(find.text('Copiar CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar JSON'));
      await tester.pumpAndSettle();
      expect(copied[1], contains('finished:app_background,session'));
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
        'app_background',
      );
      expect(calls.map((call) => call.method), [
        'authorizeControl',
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
