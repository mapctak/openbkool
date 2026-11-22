import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/trainer_session.dart';
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
  for (final screen in [const Size(412, 820), const Size(820, 412)]) {
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
          [5800, 54, 0],
          [6750, 72, 0],
          [7450, 48, 0],
          [8420, 56, 0],
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
          'running': true,
          'status': 'running',
          'trainingServiceActive': true,
          'connectionState': 'identity_verified',
          'selectedDevice': SavedTrainer.known.device,
          'manualControl': {
            'eligible': true,
            'enabled': true,
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
        if (preview != null) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 2);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$preview/dashboard-${screen.width.toInt()}.png')
                .writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
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
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }
}
