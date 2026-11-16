import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/transmission_diagnostics.dart';

void main() {
  testWidgets(
    'stop API error and TX are distinct from ordered grade and physical effect',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TransmissionDiagnostics(
                report: {
                  'transmissionDiagnostics': {
                    'lastManualOrder': {
                      'requestedPercent': 1.0,
                      'event': 'api_returned',
                    },
                    'lastStopCommand': {
                      'requestedPercent': 0.0,
                      'event': 'api_error',
                    },
                    'stopResult': 'zero_api_error',
                    'channelUsable': false,
                    'channelClosedEventAtMs': 100,
                    'txEventCount': 3,
                  },
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Diagnóstico de transmisión ANT'));
      await tester.pumpAndSettle();
      expect(
        find.text('Última pendiente ordenada (API): 1,0 %'),
        findsOneWidget,
      );
      expect(find.textContaining('api_error · zero_api_error'), findsOneWidget);
      expect(
        find.textContaining(
          'Canal utilizable: no · CHANNEL_CLOSED observado: sí',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('No identifican qué pendiente'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Resistencia física desconocida'),
        findsOneWidget,
      );
    },
  );
}
