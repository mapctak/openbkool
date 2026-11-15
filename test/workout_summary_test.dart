import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/workout_summary.dart';

void main() {
  testWidgets(
    'rejected request is distinct from the last command returned by ANT API',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ManualOrderSummary(
              report: {
                'manualControl': {
                  'lastSubmittedPercent': 0.5,
                  'lastResult': {'event': 'rejected', 'reason': 'rate_limited'},
                },
                'manualControlEvents': [
                  {'event': 'request', 'requestedPercent': 0.5},
                  {'event': 'api_returned', 'requestedPercent': 0.5},
                  {'event': 'request', 'requestedPercent': 1.0},
                ],
              },
            ),
          ),
        ),
      );
      expect(find.text('Pendiente ordenada: +0,5 %'), findsOneWidget);
      expect(find.text('Seleccionada: +1,0 %'), findsOneWidget);
      expect(find.text('Orden enviada a la API ANT: 0,5 %'), findsOneWidget);
      expect(
        find.text('Última solicitud rechazada; no se ha enviado esa orden.'),
        findsOneWidget,
      );
      expect(
        find.text('Aplicación física no confirmada por el protocolo.'),
        findsOneWidget,
      );
    },
  );
}
