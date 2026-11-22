import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ant_trainer_search.dart';
import 'package:openbkool/trainer_session.dart';
import 'package:openbkool/spinning.dart';
import 'package:openbkool/spinning_engine.dart';
import 'package:openbkool/spinning_program.dart';
import 'package:openbkool/app_home.dart';

class SpinPreferences extends TrainerPreferences {
  @override
  Future<SavedTrainer?> load() async => SavedTrainer.known;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final short = SpinningProgram('test', 'Sesión simulada', [
    SpinningInterval(SpinningPhase.warmup, const Duration(seconds: 10), 0),
    SpinningInterval(SpinningPhase.work, const Duration(seconds: 10), 0.5),
    SpinningInterval(SpinningPhase.recovery, const Duration(seconds: 10), 1),
  ]);
  TrainerSession session() {
    final training = AntTrainerSearchController(
      channelName: 'openbkool/training',
    );
    training.snapshot = {
      'sessionId': 'guided',
      'running': true,
      'connectionState': 'identity_verified',
      'selectedDevice': SavedTrainer.known.device,
      'telemetry': {
        'signal': 'receiving',
        'powerW': 165,
        'speedKmh': 28.4,
        'cadenceRpm': 84,
      },
      'manualControl': {
        'enabled': false,
        'lastManualApiSuccess': {'requestedPercent': 0.0, 'stopRequest': false},
      },
    };
    return TrainerSession(training: training, preferences: SpinPreferences());
  }

  testWidgets(
    'guided target changes, pause, resume and finish never submit ANT slopes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = session();
      var now = Duration.zero;
      final e = SpinningEngine(short, now: () => now);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(s.training.channel, (call) async {
        calls.add(call);
        return {...s.training.snapshot, 'running': false};
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SpinningSessionPage(program: short, session: s, engine: e),
        ),
      );
      expect(find.text('165 W'), findsOneWidget);
      expect(find.text('84 RPM'), findsOneWidget);
      expect(
        find.text('Última pendiente ordenada al rodillo (API): 0,0 %'),
        findsOneWidget,
      );
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pump();
      now = const Duration(seconds: 11);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('spinningTarget'))).data,
        '+0,5 %',
      );
      expect(
        find.text('Última pendiente ordenada al rodillo (API): 0,0 %'),
        findsOneWidget,
      );
      await tester.tap(find.text('Pausar'));
      await tester.pump();
      now = const Duration(minutes: 2);
      await tester.pump(const Duration(seconds: 3));
      expect(e.elapsed, const Duration(seconds: 11));
      await tester.tap(find.text('Reanudar'));
      await tester.pump();
      now += const Duration(seconds: 10);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('spinningTarget'))).data,
        '+1,0 %',
      );
      expect(calls, isEmpty);
      await tester.tap(find.text('Finalizar'));
      await tester.pumpAndSettle();
      expect(e.state, SpinningState.finished);
      expect(find.text('Sesión finalizada'), findsOneWidget);
      expect(calls.map((c) => c.method), ['stop']);
      expect(
        calls.any(
          (c) => c.method == 'setManualSlope' || c.method == 'enableManualTest',
        ),
        false,
      );
      await tester.pumpWidget(const SizedBox());
      s.dispose();
      messenger.setMockMethodCallHandler(s.training.channel, null);
    },
  );
  testWidgets('guide completion never submits a slope or stops the radio', (
    tester,
  ) async {
    final s = session();
    var now = Duration.zero;
    final e = SpinningEngine(short, now: () => now);
    e.start();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(s.training.channel, (call) async {
      calls.add(call);
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SpinningSessionPage(program: short, session: s, engine: e),
      ),
    );
    now = const Duration(minutes: 1);
    await tester.pump(const Duration(milliseconds: 250));
    expect(e.state, SpinningState.completed);
    expect(find.text('Programa completado'), findsOneWidget);
    expect(calls, isEmpty);
    s.training.snapshot = {...s.training.snapshot, 'running': false};
    await tester.pumpWidget(const SizedBox());
    s.dispose();
    messenger.setMockMethodCallHandler(s.training.channel, null);
  });
  testWidgets('background pauses guide and leaves ANT lifecycle to Android', (
    tester,
  ) async {
    final s = session();
    var now = Duration.zero;
    final e = SpinningEngine(short, now: () => now);
    e.start();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(s.training.channel, (call) async {
      calls.add(call);
      return {...s.training.snapshot, 'running': false};
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SpinningSessionPage(program: short, session: s, engine: e),
      ),
    );
    now = const Duration(seconds: 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    now = const Duration(hours: 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(e.state, SpinningState.paused);
    expect(e.elapsed, const Duration(seconds: 4));
    expect(calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
    messenger.setMockMethodCallHandler(s.training.channel, null);
  });
  testWidgets('home exposes four programs and session fits S7 and S20', (
    tester,
  ) async {
    final s = session();
    s.training.snapshot = {...s.training.snapshot, 'running': false};
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OpenBkoolShell(
          session: s,
          advancedBuilder: (_, _) => const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sesiones de spinning'), 200);
    await tester.tap(find.text('Sesiones de spinning'));
    await tester.pumpAndSettle();
    expect(find.text('Spinning suave'), findsOneWidget);
    expect(find.text('Spinning de resistencia'), findsOneWidget);
    await tester.tap(find.text('Spinning suave'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsOneWidget);
    for (final size in [const Size(360, 640), const Size(412, 915)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
