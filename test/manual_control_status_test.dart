import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/manual_control_status.dart';

void main() {
  ManualActivationStatus status(
    Map<String, Object?> r, {
    bool busy = false,
    bool stopping = false,
  }) => ManualActivationStatus.fromReport(
    r,
    commandBusy: busy,
    stopping: stopping,
  );
  final ready = <String, Object?>{
    'running': true,
    'status': 'running',
    'sessionId': 'new-session',
    'manualControl': {'enabled': false, 'eligible': true},
  };
  test(
    'real S20 snapshot blocks despite verified identity and fresh telemetry',
    () {
      final r = Map<String, Object?>.from(
        jsonDecode(
          File('test/fixtures/manual_control_blocked_s20.json')
              .readAsStringSync(),
        ) as Map,
      );
      final s = status(r);
      expect(s.canChange, false);
      expect(s.code, 'dedicated_channel_required');
      expect(s.message, contains('canal específico'));
      expect((r['devices'] as List).first['modelNumber'], isNull);
    },
  );
  test('native safety decision is required; confirmation and timer are not prerequisites for opening dialog', () {
    expect(status(ready).canChange, true);
    expect(
      status({
        ...ready,
        'manualControl': {
          'enabled': false,
          'eligible': false,
          'unavailableReason': 'manufacturer_model_not_verified',
        },
      }).code,
      'manufacturer_model_not_verified',
    );
    expect(status({...ready, 'manualControl': null}).canChange, false);
    expect(
      status({
        ...ready,
        'manualControl': {
          'eligible': false,
          'unavailableReason': 'telemetry_not_fresh',
        },
      }).canChange,
      false,
    );
  });
  test('every Flutter blocker has a specific reason', () {
    expect(status(ready, busy: true).code, 'command_in_progress');
    expect(status(ready, stopping: true).code, 'session_stopping');
    expect(status({...ready, 'status': 'starting'}).code, 'starting');
    expect(status({...ready, 'running': false}).code, 'no_training_session');
    expect(status({...ready, 'sessionId': null}).code, 'session_not_ready');
    expect(
      status({
        ...ready,
        'manualControl': {'eligible': false, 'stopped': true},
      }).code,
      'session_stopped',
    );
    expect(
      status({
        ...ready,
        'manualControl': {'eligible': false, 'faulted': true},
      }).code,
      'api_fault_requires_reconnect',
    );
    expect(
      status({
        ...ready,
        'manualControl': {
          'eligible': false,
          'unavailableReason': 'test_timeout',
        },
      }).code,
      'test_timeout',
    );
  });
  test(
    'elapsed timer disables activation until native controlled stop completes',
    () {
      expect(
        status({
          ...ready,
          'manualControl': {
            'enabled': true,
            'eligible': false,
            'remainingMs': 0,
            'unavailableReason': 'test_timeout',
          },
        }).code,
        'test_timeout',
      );
      expect(
        status({
          ...ready,
          'manualControl': {
            'enabled': true,
            'eligible': true,
            'remainingMs': 0,
          },
        }).canChange,
        false,
      );
      expect(
        status({
          ...ready,
          'manualControl': {
            'enabled': false,
            'eligible': true,
            'remainingMs': null,
          },
        }).canChange,
        true,
      );
    },
  );
  test('enabled flag cannot hide a latched link loss', () {
    final blocked = status({
      ...ready,
      'manualControl': {
        'enabled': true,
        'eligible': false,
        'remainingMs': 12000,
        'state': 'error',
        'unavailableReason': 'link_lost:signal_not_fresh',
      },
    });
    expect(blocked.canChange, false);
    expect(blocked.code, 'link_lost:signal_not_fresh');
    expect(blocked.message, contains('No se reactivará'));
  });
}
