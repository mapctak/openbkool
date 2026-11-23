import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/trainer_session.dart';
import 'package:openbkool/ant_trainer_search.dart';

class PendingConnection extends AntTrainerSearchController {
  final completion = Completer<void>();
  @override
  Future<void> start(String mode, {Map<String, Object?>? device}) =>
      completion.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(TrainerPreferences.channel, null),
  );
  test('selection survives new state instance without restoring connection or control permission', () async {
    Map<dynamic, dynamic>? stored;
    messenger.setMockMethodCallHandler(TrainerPreferences.channel, (
      call,
    ) async {
      if (call.method == 'loadTrainer') return stored;
      stored = Map<dynamic, dynamic>.from(call.arguments as Map);
      return null;
    });
    final first = TrainerSession();
    await first.restore();
    expect(first.selected.id, '30064/112/5');
    expect(first.connection, TrainerConnection.disconnected);
    await first.select(
      const SavedTrainer(123, 112, 6, model: 22, manufacturer: 67),
    );
    first.dispose();
    final second = TrainerSession();
    await second.restore();
    expect(second.selected.id, '123/112/6');
    expect(second.connection, TrainerConnection.disconnected);
    expect(second.training.snapshot['manualControl'], isNull);
    expect(stored!.containsKey('sessionId'), false);
    expect(stored!.containsKey('connected'), false);
    second.dispose();
  });
  test(
    'failed write preserves previous selection and surfaces error',
    () async {
      messenger.setMockMethodCallHandler(TrainerPreferences.channel, (
        call,
      ) async {
        if (call.method == 'loadTrainer') return null;
        throw PlatformException(code: 'disk_error');
      });
      final s = TrainerSession();
      await s.restore();
      await expectLater(
        s.select(const SavedTrainer(123, 112, 6)),
        throwsA(isA<PlatformException>()),
      );
      expect(s.selected.id, '30064/112/5');
      expect(s.preferenceError, isNotNull);
      expect(s.saving, false);
      s.dispose();
    },
  );
  test('late restore cannot overwrite newer user selection', () async {
    final loaded = Completer<Map<String, Object?>>();
    messenger.setMockMethodCallHandler(
      TrainerPreferences.channel,
      (call) async => call.method == 'loadTrainer' ? loaded.future : null,
    );
    final s = TrainerSession();
    final restoring = s.restore();
    await s.select(const SavedTrainer(123, 112, 6));
    loaded.complete(SavedTrainer.known.toJson());
    await restoring;
    expect(s.selected.id, '123/112/6');
    s.dispose();
  });
  test('remembered, connecting, verified, signal loss, wrong identity and close are distinct', () {
    final d = SavedTrainer.known;
    final connected = <String, Object?>{
      'sessionId': 'live',
      'running': true,
      'status': 'running',
      'selectedDevice': d.device,
      'connectionState': 'identity_verified',
      'telemetry': {'signal': 'receiving'},
    };
    expect(connectionFor({}, d), TrainerConnection.disconnected);
    expect(
      connectionFor({...connected, 'sessionId': null}, d),
      TrainerConnection.connecting,
    );
    expect(
      connectionFor({
        ...connected,
        'connectionState': 'waiting_for_identity',
      }, d),
      TrainerConnection.connecting,
    );
    expect(connectionFor(connected, d), TrainerConnection.connected);
    expect(
      connectionFor(connected, const SavedTrainer(123, 112, 6)),
      TrainerConnection.connecting,
    );
    expect(
      connectionFor({
        ...connected,
        'telemetry': {'signal': 'signal_lost'},
      }, d),
      TrainerConnection.error,
    );
    expect(
      connectionFor({
        ...connected,
        'running': false,
        'status': 'manual_stop',
      }, d),
      TrainerConnection.disconnected,
    );
    expect(
      connectionFor({
        ...connected,
        'running': false,
        'status': 'start_error',
      }, d),
      TrainerConnection.error,
    );
    expect(
      connectionFor({...connected, 'status': 'stopping_zero_unconfirmed'}, d),
      TrainerConnection.disconnecting,
    );
  });
  test('invalid persisted protocol and wildcard are rejected', () {
    expect(
      () => SavedTrainer.fromMap({
        ...SavedTrainer.known.device,
        'deviceNumber': 0,
      }),
      throwsFormatException,
    );
    expect(
      () => SavedTrainer.fromMap({
        ...SavedTrainer.known.device,
        'protocol': 'FEC',
      }),
      throwsFormatException,
    );
  });
  test('pending connect is connecting but never connected before native identity and telemetry', () async {
    messenger.setMockMethodCallHandler(
      TrainerPreferences.channel,
      (call) async => null,
    );
    final controller = PendingConnection();
    final s = TrainerSession(training: controller);
    await s.restore();
    final pending = s.connect();
    expect(s.connection, TrainerConnection.connecting);
    expect(s.locked, true);
    controller.completion.complete();
    await pending;
    expect(s.connection, TrainerConnection.disconnected);
    s.dispose();
  });
}
