import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/training.dart';

class DisplayController extends AntTrainerSearchController {
  DisplayController() : super(channelName: 'openbkool/training');
  void emit(Map<String, Object?> report) {
    snapshot = report;
    notifyListeners();
  }
}

Map<String, Object?> active(double percent) => {
  'sessionId': 'display-session',
  'running': true,
  'status': 'running',
  'connectionState': 'identity_verified',
  'selectedDevice': {
    'protocol': 'BKOOL_V1_PUBLIC',
    'deviceNumber': 30064,
    'deviceType': 112,
    'transmissionType': 5,
  },
  'telemetry': {
    'signal': 'receiving',
    'powerW': 200,
    'speedKmh': 25.0,
    'cadenceRpm': 80,
    'distanceM': 100,
    'elapsedMs': 20000,
  },
  'manualControl': {
    'enabled': true,
    'eligible': true,
    'everEnabled': true,
    'remainingMs': 2000,
    'lastSubmittedPercent': percent,
  },
  'manualControlEvents': [
    {'event': 'request', 'requestedPercent': percent},
    {
      'event': 'api_returned',
      'requestedPercent': percent,
      'stopRequest': false,
    },
  ],
};
Map<String, Object?> stopping(
  Map<String, Object?> old, {
  required bool timeout,
  bool closed = true,
}) => {
  ...old,
  'running': !closed,
  'status': closed
      ? (timeout ? 'test_timeout' : 'manual_stop')
      : 'stopping_zero_unconfirmed',
  'manualControl': {
    'enabled': false,
    'eligible': false,
    'everEnabled': true,
    'stopped': true,
    'remainingMs': 0,
    'lastSubmittedPercent': 0.0,
    'stopResult': 'zero_api_returned_unconfirmed',
  },
  'manualControlEvents': [
    ...old['manualControlEvents'] as List,
    {
      'event': 'stop_requested',
      'reason': timeout ? 'test_timeout' : 'manual_stop',
    },
    {'event': 'api_attempt', 'requestedPercent': 0.0, 'stopRequest': true},
    {'event': 'api_returned', 'requestedPercent': 0.0, 'stopRequest': true},
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<void> open(WidgetTester tester, DisplayController c) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: TrainingPage(controller: c, simple: true)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester, DisplayController c) async {
    c.snapshot = {...c.snapshot, 'running': false};
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    messenger.setMockMethodCallHandler(c.channel, null);
  }

  testWidgets(
    'native link guard disables slope actions but leaves controlled stop available',
    (tester) async {
      final c = DisplayController();
      final report = active(0.5);
      c.emit({
        ...report,
        'manualControl': {
          ...report['manualControl'] as Map,
          'eligible': false,
          'blockingReasons': ['radio_unavailable'],
        },
      });
      await open(tester, c);
      for (final label in ['+', '−', 'LLANO 0 %']) {
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, label),
              )
              .onPressed,
          isNull,
        );
      }
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Detener control'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'native control-only update refreshes main slope without RX and preserves API success',
    (tester) async {
      final c = DisplayController();
      c.emit(active(0));
      await open(tester, c);
      for (final percent in [0.0, 0.5, 1.0]) {
        c.emit({
          ...c.snapshot,
          'manualControlEvents': [],
          'manualControl': {
            'enabled': true,
            'everEnabled': true,
            'remainingMs': 1000,
            'lastRequestedPercent': percent,
            'lastApiSuccess': {
              'requestedPercent': percent,
              'stopRequest': false,
            },
          },
        });
        await tester.pump();
        final label = percent == 0
            ? '0,0'
            : '+${percent.toStringAsFixed(1).replaceAll('.', ',')}';
        expect(find.text('Pendiente ordenada: $label %'), findsOneWidget);
      }
      c.emit({
        ...c.snapshot,
        'manualControl': {
          'lastRequestedPercent': 0.5,
          'lastApiSuccess': {'requestedPercent': 1.0, 'stopRequest': false},
          'lastApiError': {'error': 'radio lost'},
        },
      });
      await tester.pump();
      expect(find.text('Pendiente ordenada: +1,0 %'), findsOneWidget);
      expect(find.text('Seleccionada: +0,5 %'), findsOneWidget);
      expect(
        find.textContaining('Orden enviada a la API ANT: 1,0'),
        findsOneWidget,
      );
      expect(find.textContaining('radio lost'), findsOneWidget);
    },
  );
  testWidgets(
    'one main indicator updates immediately for 0.5, 1 and 0 before simulated API reply',
    (tester) async {
      final c = DisplayController();
      c.snapshot = active(0);
      Completer<Map<String, Object?>>? pending;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call);
        expect(call.method, 'setManualSlope');
        return pending!.future;
      });
      await open(tester, c);
      expect(find.text('Pendiente ordenada: 0,0 %'), findsOneWidget);
      expect(find.byKey(const ValueKey('slopeSummary')), findsOneWidget);
      expect(find.text('LLANO 0 %'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('requestedSlope'))).dy,
        lessThan(tester.getTopLeft(find.text('LLANO 0 %')).dy),
      );
      for (final step in [
        ('+', 0.5, '+0,5'),
        ('+', 1.0, '+1,0'),
        ('−', 0.5, '+0,5'),
        ('LLANO 0 %', 0.0, '0,0'),
      ]) {
        final previous = c.snapshot;
        pending = Completer<Map<String, Object?>>();
        await tester.tap(find.widgetWithText(OutlinedButton, step.$1));
        await tester.pump();
        expect(find.text('Seleccionada: ${step.$3} %'), findsOneWidget);
        expect(
          find.text('Solicitud pendiente de respuesta del controlador.'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('slopeSummary')), findsOneWidget);
        expect((calls.last.arguments as Map)['percent'], step.$2);
        final updated = {
          ...active(step.$2),
          'manualControlEvents': [
            ...previous['manualControlEvents'] as List,
            {'event': 'request', 'requestedPercent': step.$2},
            {
              'event': 'api_returned',
              'requestedPercent': step.$2,
              'stopRequest': false,
            },
          ],
        };
        pending.complete(updated);
        await tester.pumpAndSettle();
        expect(find.text('Pendiente ordenada: ${step.$3} %'), findsOneWidget);
        expect(
          find.text(
            'Orden enviada a la API ANT: ${step.$3.replaceAll('+', '')} %',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Solicitud pendiente de respuesta del controlador.'),
          findsNothing,
        );
      }
      expect(calls.length, 4);
      expect(
        find.text('Aplicación física no confirmada por el protocolo.'),
        findsOneWidget,
      );
      await close(tester, c);
    },
  );
  testWidgets(
    'controlled stop displays actual zero API result without overwriting last manual request',
    (tester) async {
      final c = DisplayController();
      c.snapshot = active(1);
      final calls = <String>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call.method);
        return stopping(c.snapshot, timeout: false);
      });
      await open(tester, c);
      await tester.tap(find.text('Detener control'));
      await tester.pumpAndSettle();
      expect(calls, ['stopManualTest']);
      expect(find.text('Prueba finalizada'), findsOneWidget);
      expect(find.text('Última pendiente ordenada: +1,0 %'), findsOneWidget);
      expect(
        find.text(
          'Control finalizado · Se solicitó 0 % · Resistencia actual desconocida',
        ),
        findsOneWidget,
      );
      expect(
        find.text('No se asume que el rodillo haya vuelto físicamente a 0 %.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'LLANO 0 %'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Diagnóstico detallado del entrenamiento'),
        findsOneWidget,
      );
      await close(tester, c);
    },
  );
  testWidgets(
    '30 second expiry disables controls and preserves native timeout and zero uncertainty',
    (tester) async {
      final c = DisplayController();
      c.snapshot = active(0.5);
      final calls = <String>[];
      messenger.setMockMethodCallHandler(c.channel, (call) async {
        calls.add(call.method);
        return null;
      });
      await open(tester, c);
      final expired = {
        ...c.snapshot,
        'manualControl': {
          ...c.snapshot['manualControl'] as Map,
          'remainingMs': 0,
          'eligible': false,
          'unavailableReason': 'test_timeout',
        },
      };
      c.emit(expired);
      await tester.pumpAndSettle();
      expect(find.text('Prueba caducada (30 s)'), findsOneWidget);
      for (final label in ['−', 'LLANO 0 %', '+']) {
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, label),
              )
              .onPressed,
          isNull,
        );
      }
      c.emit(stopping(expired, timeout: true, closed: false));
      await tester.pumpAndSettle();
      expect(find.text('Última pendiente ordenada: +0,5 %'), findsOneWidget);
      expect(
        find.text(
          'Parada: solicitud de 0 % entregada a la API; aplicación física sin confirmar.',
        ),
        findsOneWidget,
      );
      c.emit(stopping(expired, timeout: true));
      await tester.pumpAndSettle();
      expect(find.text('Prueba caducada (30 s)'), findsOneWidget);
      expect(
        find.text(
          'Control finalizado · Se solicitó 0 % · Resistencia actual desconocida',
        ),
        findsOneWidget,
      );
      expect(calls, isEmpty);
      expect(
        find.text('No se asume que el rodillo haya vuelto físicamente a 0 %.'),
        findsOneWidget,
      );
      await close(tester, c);
    },
  );
}
