import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/trainer_session.dart';
import 'package:openbkool/main.dart';
import 'package:openbkool/training.dart';
import 'package:openbkool/workout_dashboard.dart';

class DashboardController extends AntTrainerSearchController {
  DashboardController() : super(channelName: 'openbkool/training');
  void replace(Map<String, Object?> report) {
    snapshot = report;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'profile marks the last valid point on the right and joins uncertain segments',
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(
                width: 300,
                child: ElevationChart(
                  height: 128,
                  distanceMeters: 150,
                  points: [
                    [0, 0, 0],
                    [25, 0, 0],
                    [50, 0, 1],
                    [100, 0, 1],
                    [90, 9, 2],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final render =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage();
        final data = (await image.toByteData())!;
        int green(int x) => data.getUint8((58 * image.width + x) * 4 + 1);
        expect(green(284), greaterThan(180));
        expect(green(100), greaterThan(green(103)));
        image.dispose();
      });
    },
  );

  for (final screen in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets(
      'dashboard fits ${screen.width} × ${screen.height} and keeps the native profile',
      (tester) async {
        await tester.binding.setSurfaceSize(screen);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = DashboardController();
        final session = TrainerSession(training: controller);
        final boundary = GlobalKey();
        final profile = [
          [0, 0, 0],
          [400, 0, 0],
          [1300, 31, 0],
          [2200, 16, 0],
          [3550, 37, 0],
          [4100, 23, 0],
          [5000, 67, 0],
          [5800, 54, 1],
          [6750, 72, 1],
          [7450, 48, 1],
          [8420, 56, 1],
        ];
        final telemetry = {
          'signal': 'receiving',
          'speedKmh': 31.4,
          'powerW': 214,
          'cadenceRpm': 88,
          'distanceM': 8420,
          'elapsedMs': 1496000,
        };
        final report = <String, Object?>{
          'sessionId': 'preview',
          'trainingElapsedMs': 1496000,
          'running': true,
          'status': 'running',
          'trainingServiceActive': true,
          'connectionState': 'identity_verified',
          'selectedDevice': SavedTrainer.known.device,
          'manualControl': {
            'eligible': true,
            'enabled': true,
            'state': 'active',
            'lastRequestedPercent': 3.5,
          },
          'virtualElevation': profile,
          'telemetry': telemetry,
        };
        final preview = Platform.environment['OPENBKOOL_PREVIEW_DIR'];
        if (preview != null) {
          await tester.runAsync(() async {
            final fonts = Platform.environment['OPENBKOOL_PREVIEW_FONTS']!;
            for (final entry in {
              'Roboto': 'Roboto-Regular.ttf',
              'MaterialIcons': 'MaterialIcons-Regular.otf',
            }.entries) {
              final data = await File('$fonts/${entry.value}').readAsBytes();
              final loader = FontLoader(entry.key)
                ..addFont(Future.value(ByteData.sublistView(data)));
              await loader.load();
            }
          });
        }
        controller.snapshot = report;
        Widget page(Key key) => RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: TrainingPage(key: key, session: session),
          ),
        );
        await tester.pumpWidget(page(const ValueKey(1)));
        await tester.pumpAndSettle();
        expect(find.byType(WorkoutDial), findsNWidgets(3));
        expect(
          tester.getSize(find.byType(ElevationChart)).height,
          lessThan(175),
        );
        expect(
          tester.getSize(find.byType(FilledButton)).height,
          greaterThanOrEqualTo(48),
        );

        expect(find.text('31,4'), findsOneWidget);
        expect(find.text('214'), findsOneWidget);
        expect(find.text('88'), findsOneWidget);
        expect(find.text('00:24:56'), findsOneWidget);
        expect(find.text('8,42 km'), findsOneWidget);
        expect(find.text('LLANO 0 %'), findsNothing);
        expect(
          find.text('DETENER ENTRENAMIENTO').hitTestable(),
          findsOneWidget,
        );
        expect(
          tester.widget<ElevationChart>(find.byType(ElevationChart)).points,
          profile,
        );
        expect(tester.takeException(), isNull);
        Future<void> capture(String name) async {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 2);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$preview/$name.png')
                .writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }

        if (preview != null) {
          await capture('dashboard-${screen.width.toInt()}');
        }
        controller.replace({
          ...report,
          'telemetry': {...telemetry, 'powerW': null},
        });
        await tester.pumpAndSettle();
        expect(find.text('214'), findsNothing);
        expect(find.text('—'), findsOneWidget);
        await tester.pumpWidget(page(const ValueKey(2)));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ElevationChart>(find.byType(ElevationChart)).points,
          profile,
        );
        controller.replace({
          ...report,
          'sessionId': 'new',
          'virtualElevation': [
            [0, 0, 0],
          ],
        });
        await tester.pumpAndSettle();
        expect(
          tester.widget<ElevationChart>(find.byType(ElevationChart)).points,
          [
            [0, 0, 0],
          ],
        );
        expect(tester.takeException(), isNull);
        if (preview != null && screen.width < screen.height) {
          controller.replace({
            ...report,
            'sessionId': 'warming',
            'trainingElapsedMs': null,
            'manualControl': {'eligible': false, 'enabled': false},
          });
          await tester.pumpAndSettle();
          await capture('calentamiento-360');
          controller.replace({'status': 'not_started', 'running': false});
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
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: OpenBkoolApp(session: session),
            ),
          );
          await tester.pumpAndSettle();
          await capture('inicio-360');
        }
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }
}
