import 'dart:async';
import 'dart:convert';

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
      final copied = <String>[];
      double? selected, accepted;
      Map<String, Object?>? success, stop;
      final history = <Map<String, Object?>>[];
      Map<String, Object?> report() => {
        'sessionId': 'sync',
        'trainingServiceActive': !stopped,
        'selectedDevice': SavedTrainer.known.device,
        'connectionState': 'identity_verified',
        'reportSequence': ++sequence,
        'running': sequence > 1 && !stopped,
        'status': stopped ? 'user_finish' : 'running',
        'recordState': stopped ? 'final' : 'partial',
        if (stopped) 'csvFile': 'training_sync.csv',
        'manualControl': {
          'enabled': enabled,
          'state': enabled ? 'active' : 'available',
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
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        if (call.method == 'start') {
          await rx(report());
          return null;
        }
        if (call.method == 'exportCsv' || call.method == 'exportJson') {
          expect((call.arguments as Map)['sessionId'], 'sync');
          expect(stopped, isTrue);
          return call.method == 'exportCsv'
              ? 'event,session_id\nfinished:user_finish,sync\n'
              : report();
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
          history.add({'event': 'stop_requested', 'reason': 'user_finish'});
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
        (c.snapshot['manualControl'] as Map)['lastManualApiSuccess'],
        isNull,
      );
      expect(find.text('LLANO 0 %'), findsNothing);
      for (final step in [
        ('Aumentar pendiente', 0.5),
        ('Aumentar pendiente', 1.0),
        ('Disminuir pendiente', 0.5),
        ('Disminuir pendiente', 0.0),
      ]) {
        final old = Map<String, Object?>.from(c.snapshot);
        await tester.tap(find.byTooltip(step.$1));
        await tester.pumpAndSettle();
        expect(
          (c.snapshot['manualControl']
              as Map)['lastManualApiSuccess']['requestedPercent'],
          step.$2,
        );
        await rx(old);
        await tester.pump();
        expect(
          (c.snapshot['manualControl']
              as Map)['lastManualApiSuccess']['requestedPercent'],
          step.$2,
        );
        await rx({
          ...report(),
          'telemetry': {'signal': 'receiving', 'powerW': 150},
        });
        await tester.pump();
        expect(
          (c.snapshot['manualControl']
              as Map)['lastManualApiSuccess']['requestedPercent'],
          step.$2,
        );
      }
      await tester.tap(find.text('DETENER ENTRENAMIENTO'));
      await tester.pumpAndSettle();
      expect(
        (c.snapshot['manualControl']
            as Map)['lastStopCommand']['requestedPercent'],
        0.0,
      );
      expect(
        history
            .where(
              (e) => e['event'] == 'api_returned' && e['stopRequest'] != true,
            )
            .map((e) => e['requestedPercent']),
        [0.5, 1.0, 0.5, 0.0],
      );
      await tester.tap(find.byTooltip('Exportar entrenamiento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Exportar entrenamiento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar JSON'));
      await tester.pumpAndSettle();
      final finalReport = jsonDecode(copied.last) as Map;
      expect(copied.first, contains('finished:user_finish,sync'));
      expect(finalReport['sessionId'], 'sync');
      expect(finalReport['recordState'], 'final');
      expect(finalReport['manualControlEvents'].last['stopRequest'], true);
      expect(
        (finalReport['clientManualChanges'] as List)
            .where((entry) => entry['event'] == 'slope_selected')
            .map((entry) => entry['percent']),
        [0.5, 1.0, 0.5, 0.0],
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(c.channel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel('openbkool/training/events'),
        null,
      );
    },
  );
}
