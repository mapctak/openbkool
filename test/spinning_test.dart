import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/main.dart';
import 'package:openbkool/spinning.dart';
import 'package:openbkool/trainer_session.dart';

import 'app_home_test.dart' show FakeTraining;

List<Map<Object?, Object?>> get catalog => [
  {
    'id': 'spinning-v1-10-1',
    'name': 'Muy suave · 10 min',
    'durationMs': 600000,
    'level': 1,
    'maxGrade': 2.0,
    'intervals': [
      for (final (start, end, grade) in [
        (0, 45, 0.5),
        (45, 90, 1.0),
        (90, 180, 1.0),
        (180, 315, 0.5),
        (315, 405, 2.0),
        (405, 540, 0.5),
        (540, 570, 0.5),
        (570, 600, 0.0),
      ])
        {'startMs': start * 1000, 'endMs': end * 1000, 'grade': grade},
    ],
  },
];

class SpinningTraining extends FakeTraining {
  String? stoppedId;
  @override
  Future<List<Map<Object?, Object?>>> spinningCatalog() async => catalog;

  @override
  Future<void> stop({String reason = 'user_finish', String? expectedId}) {
    stoppedId = expectedId;
    return super.stop(reason: reason, expectedId: expectedId);
  }
}

void main() {
  testWidgets(
    'selecting a program is passive, and starting it claims the only workout',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        TrainerPreferences.channel,
        (_) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          TrainerPreferences.channel,
          null,
        ),
      );
      final controller = SpinningTraining();
      final session = TrainerSession(training: controller);
      await tester.pumpWidget(OpenBkoolApp(session: session));
      await tester.pumpAndSettle();
      expect(find.text('SPINNING'), findsOneWidget);
      expect(find.text('ENTRENAMIENTO LIBRE'), findsOneWidget);
      await tester.tap(find.text('SPINNING'));
      await tester.pumpAndSettle();
      expect(controller.starts.single['mode'], 'training_connection_check');
      expect(find.text('Muy suave · 10 min'), findsOneWidget);
      await tester.tap(find.text('INICIAR SPINNING'));
      await tester.pumpAndSettle();
      expect(controller.starts.last['mode'], 'spinning:spinning-v1-10-1');
      final report = <String, Object?>{
        'sessionId': 'spin-one',
        'running': true,
        'workoutMode': 'spinning',
        'trainingServiceActive': true,
        'antConnectionState': 'present',
        'selectedDevice': SavedTrainer.known.device,
        'trainingElapsedMs': 46000,
        'manualControl': {'enabled': true, 'eligible': true, 'state': 'active'},
        'spinning': {
          ...catalog.first,
          'currentGrade': 1.0,
          'remainingMs': 554000,
          'intervalRemainingMs': 44000,
        },
      };
      controller.emit(report);
      await tester.pumpAndSettle();
      for (final tooltip in ['Aumentar pendiente', 'Disminuir pendiente']) {
        final button = find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        );
        expect(tester.widget<IconButton>(button).onPressed, isNull);
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('ENTRENAMIENTO EN CURSO'), findsOneWidget);
      expect(find.text('Muy suave · 10 min'), findsOneWidget);
      expect(find.text('ENTRENAMIENTO LIBRE'), findsNothing);
      expect(find.text('SPINNING'), findsNothing);
      await session.stopWorkout(expectedId: 'previous-workout');
      expect(controller.stops, 0);
      await session.connect();
      await session.connect(programId: 'spinning-v1-15-2');
      expect(controller.starts, hasLength(2));
      await tester.tap(find.text('VOLVER AL ENTRENAMIENTO'));
      await tester.pumpAndSettle();
      expect(find.text('CALENTAMIENTO'), findsNothing);
      expect(find.text('00:00:46'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('DETENER'));
      await tester.pumpAndSettle();
      expect(controller.stoppedId, 'spin-one');
      expect(controller.stops, 1);
      expect(find.text('ENTRENAMIENTO EN CURSO'), findsNothing);
      expect(find.text('ENTRENAMIENTO LIBRE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('selector shows deterministic temporal preview', (tester) async {
    tester.view.physicalSize = const Size(420, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final path = Platform.environment['OPENBKOOL_SPINNING_PREVIEW'];
    if (path != null) {
      await tester.runAsync(() async {
        final font = await File(
          '/usr/share/fonts/truetype/lato/Lato-Regular.ttf',
        ).readAsBytes();
        await (FontLoader(
          'Preview',
        )..addFont(Future.value(ByteData.sublistView(font)))).load();
        final icons = Platform.environment['OPENBKOOL_MATERIAL_ICONS'];
        if (icons != null) {
          final bytes = await File(icons).readAsBytes();
          await (FontLoader(
            'MaterialIcons',
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
      });
    }
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF008F70),
          fontFamily: path == null ? null : 'Preview',
        ),
        home: RepaintBoundary(
          key: boundary,
          child: SpinningSelector(catalog: Future.value(catalog)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('INICIAR SPINNING'), findsOneWidget);
    expect(find.textContaining('Vuelta a la calma'), findsOneWidget);
    if (path != null) {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(path).writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
