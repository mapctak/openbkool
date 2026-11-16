import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/identification_progress.dart';

void main() {
  testWidgets(
    'page50 wait increases and all milestones stay separate without enabling anything',
    (tester) async {
      Map<String, Object?> report(int wait, {bool complete = false}) => {
        'identificationTiming': {
          'waiting': !complete,
          'waitingReason': complete ? null : 'manufacturer_model_not_verified',
          'waitingForConditionMs': wait,
          'waitingSinceChannelOpenMs': wait + 200,
          'milestonesMs': {
            'channelOpen': 200,
            'firstTelemetry': 300,
            'firstPage51': 400,
            if (complete) 'identificationComplete': 25400,
            if (complete) 'controlAvailable': 25600,
          },
        },
      };
      Future<void> show(Map<String, Object?> data) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: IdentificationProgress(report: data)),
        ),
      );
      await show(report(1000));
      expect(
        find.textContaining('Esperando esta condición: 1,0 s'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Identificación 0x50: pendiente'),
        findsOneWidget,
      );
      expect(
        find.textContaining('La página 0x51 no sustituye'),
        findsOneWidget,
      );
      await show(report(25000));
      expect(
        find.textContaining('Esperando esta condición: 25,0 s'),
        findsOneWidget,
      );
      await show(report(25000, complete: true));
      expect(find.byKey(const ValueKey('identificationBlocker')), findsNothing);
      expect(
        find.text('Identificación 0x50: 25,4 s · Control disponible: 25,6 s'),
        findsOneWidget,
      );
      expect(find.byType(Checkbox), findsNothing);
    },
  );
  testWidgets('old diagnostics do not fabricate zero timings', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: IdentificationProgress(report: {})),
    );
    expect(find.textContaining('Tiempos desde'), findsNothing);
  });
}
