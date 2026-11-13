import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/training.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shows native telemetry, stops and exports CSV', (tester) async {
    final c = AntTrainerSearchController(channelName: 'openbkool/training');
    c.snapshot = {
      'running': true,
      'status': 'running',
      'telemetry': {
        'signal': 'receiving',
        'speedKmh': 12.4632,
        'powerW': 29,
        'cadenceRpm': 23,
        'distanceM': 4,
      },
    };
    final calls = <String>[];
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(c.channel, (call) async {
          calls.add(call.method);
          if (call.method == 'stop') {
            return {
              ...c.snapshot,
              'running': false,
              'status': 'stopped',
              'resourcesReleased': true,
              'csvFile': 'test.csv',
            };
          }
          if (call.method == 'exportCsv') {
            return 'timestamp_utc,power_w\r\n2026-11-13,29\r\n';
          }
          throw StateError('Unexpected method ${call.method}');
        });
    await tester.pumpWidget(MaterialApp(home: TrainingPage(controller: c)));
    expect(find.text('12.5 km/h'), findsOneWidget);
    expect(find.text('29 W'), findsOneWidget);
    expect(find.text('23 RPM'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Finalizar entrenamiento'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finalizar entrenamiento'));
    await tester.pumpAndSettle();
    expect(c.running, false);
    expect(c.snapshot['resourcesReleased'], true);
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Exportar CSV al portapapeles'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exportar CSV al portapapeles'));
    await tester.pumpAndSettle();
    expect(calls, ['stop', 'exportCsv']);
    expect(copied, contains('2026-11-13,29'));
    expect(find.text('CSV copiado al portapapeles'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(c.channel, null);
  });
  testWidgets('lost signal displays missing metrics and partial distance', (
    tester,
  ) async {
    final c = AntTrainerSearchController(channelName: 'openbkool/training');
    c.snapshot = {
      'running': true,
      'telemetry': {
        'signal': 'signal_lost',
        'distanceM': 10,
        'distancePartial': true,
      },
    };
    await tester.pumpWidget(MaterialApp(home: TrainingPage(controller: c)));
    expect(find.text('— km/h'), findsOneWidget);
    expect(find.text('— W'), findsOneWidget);
    expect(find.textContaining('Distancia parcial:'), findsOneWidget);
    c.snapshot = {'running': false};
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'manual control disabled and dedicated mode is explicit with selected identity',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      final search = AntTrainerSearchController();
      search.snapshot = {
        'devices': [
          {
            'protocol': 'BKOOL_V1_PUBLIC',
            'deviceNumber': 123,
            'deviceType': 112,
            'transmissionType': 6,
          },
        ],
      };
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const eventChannel = MethodChannel('openbkool/training/events');
      messenger.setMockMethodCallHandler(eventChannel, (call) async {
        if (call.method == 'listen') {
          scheduleMicrotask(() {
            messenger.handlePlatformMessage(
              'openbkool/training/events',
              const StandardMethodCodec().encodeSuccessEnvelope({
                'status': 'not_started',
                'running': false,
              }),
              (_) {},
            );
          });
        }
        return null;
      });
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: TrainingPage(controller: c, searchController: search),
        ),
      );
      expect(calls, isEmpty);
      await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<String>),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('123:112:6').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('3. Conectar y entrenar (sin comandos)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('3. Conectar y entrenar (sin comandos)'));
      await tester.pumpAndSettle();
      expect(calls.length, 1);
      expect(calls.single.method, 'start');
      expect(calls.single.arguments, {
        'mode': 'training_connected',
        'device': {
          'protocol': 'BKOOL_V1_PUBLIC',
          'deviceNumber': 123,
          'deviceType': 112,
          'transmissionType': 6,
        },
      });
      await tester.scrollUntilVisible(
        find.byType(CheckboxListTile),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, '+'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '+'))
            .onPressed,
        isNull,
      );
      c.snapshot = {'running': false};
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      search.dispose();
      await tester.pump();
      messenger.setMockMethodCallHandler(c.channel, null);
      messenger.setMockMethodCallHandler(eventChannel, null);
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets(
    'real control needs confirmation; increments and stop use session token; JSON is exportable',
    (tester) async {
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      c.snapshot = {
        'sessionId': 'test-session',
        'running': true,
        'manualControl': {'eligible': true, 'enabled': false},
      };
      final calls = <MethodCall>[];
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        expect((call.arguments as Map)['sessionId'], 'test-session');
        if (call.method == 'enableManualTest') {
          expect((call.arguments as Map)['confirmed'], true);
          return {
            ...c.snapshot,
            'manualControl': {
              'eligible': true,
              'enabled': true,
              'everEnabled': true,
              'remainingMs': 30000,
            },
          };
        }
        if (call.method == 'setManualSlope') {
          return {
            ...c.snapshot,
            'manualControl': {
              'eligible': true,
              'enabled': true,
              'everEnabled': true,
              'remainingMs': 29000,
              'lastSubmittedPercent': (call.arguments as Map)['percent'],
            },
            'manualControlEvents': [
              {'event': 'api_returned', 'physicalApplication': 'unconfirmed'},
            ],
          };
        }
        if (call.method == 'stopManualTest') {
          return {
            ...c.snapshot,
            'running': false,
            'resourcesReleased': true,
            'manualControl': {
              'enabled': false,
              'everEnabled': true,
              'stopped': true,
              'stopResult': 'zero_api_returned_unconfirmed',
            },
          };
        }
        throw StateError('Unexpected method');
      });
      await tester.pumpWidget(MaterialApp(home: TrainingPage(controller: c)));
      expect(calls, isEmpty);
      await tester.scrollUntilVisible(
        find.byType(CheckboxListTile),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Habilitar prueba'));
      await tester.pumpAndSettle();
      expect(calls.map((e) => e.method), ['enableManualTest']);
      await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, '+'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '+'));
      await tester.pumpAndSettle();
      expect((calls.last.arguments as Map)['percent'], 0.5);
      await tester.tap(find.widgetWithText(OutlinedButton, '+'));
      await tester.pumpAndSettle();
      expect((calls.last.arguments as Map)['percent'], 1.0);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '+'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Detener prueba'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'stopManualTest');
      expect(c.snapshot['resourcesReleased'], true);
      await tester.scrollUntilVisible(
        find.text('Exportar diagnóstico JSON'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exportar diagnóstico JSON'));
      await tester.pumpAndSettle();
      expect(copied, contains('zero_api_returned_unconfirmed'));
      expect(copied, contains('manualControlEvents'));
      expect(calls.any((e) => e.method == 'start'), false);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      messenger.setMockMethodCallHandler(c.channel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    },
  );
  testWidgets(
    'stop bypasses a pending command and late response cannot revive stopped session',
    (tester) async {
      final c = AntTrainerSearchController(channelName: 'openbkool/training');
      c.snapshot = {'sessionId': 'pending-session', 'running': true};
      final pending = Completer<Map<String, Object?>>();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call.method);
        if (call.method == 'setManualSlope') return pending.future;
        return {
          'sessionId': 'pending-session',
          'running': false,
          'resourcesReleased': true,
        };
      });
      final request = c.manualAction('setManualSlope', percent: 0.5);
      await tester.pump();
      expect(c.commandBusy, true);
      final stopping = c.manualAction('stopManualTest');
      await tester.pump();
      await stopping;
      expect(calls, ['setManualSlope', 'stopManualTest']);
      expect(c.running, false);
      pending.complete({'sessionId': 'pending-session', 'running': true});
      await tester.pump();
      await request;
      expect(c.running, false);
      expect(c.commandBusy, false);
      c.dispose();
      messenger.setMockMethodCallHandler(c.channel, null);
    },
  );
}
