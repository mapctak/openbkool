import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/slope_presentation.dart';

void main() {
  test(
    'intent from old session is ignored and an unselected request is unknown',
    () {
      final state = SlopePresentation.fromReport(
        {'sessionId': 'new', 'manualControl': {}},
        intent: const SlopeUiIntent(
          sessionId: 'old',
          percent: 1,
          eventCount: 0,
        ),
      );
      expect(state.requested, isNull);
      expect(state.pending, false);
      expect(state.apiStatus, 'Sin orden enviada a ANT');
    },
  );
  test(
    'client failure retains requested intent but never claims API acceptance',
    () {
      final state = SlopePresentation.fromReport(
        {
          'sessionId': 'same',
          'clientError': 'RPC timeout',
          'manualControl': {},
        },
        intent: const SlopeUiIntent(
          sessionId: 'same',
          percent: 0.5,
          eventCount: 0,
          pending: false,
        ),
      );
      expect(state.requested, 0.5);
      expect(state.unrecordedIntent, true);
      expect(state.apiEvent, isNull);
    },
  );
  test('stop without history never fabricates a manual zero from lastSubmittedPercent', () {
    final state = SlopePresentation.fromReport({
      'running': false,
      'manualControl': {
        'stopped': true,
        'lastSubmittedPercent': 0,
        'stopResult': 'zero_api_error',
      },
    });
    expect(state.requested, isNull);
    expect(state.finished, true);
    expect(state.stopStatus, contains('error'));
    expect(state.apiStatus, 'Sin orden enviada a ANT');
  });
  test('native state survives event history loss and keeps successful API value after error', () {
    final state = SlopePresentation.fromReport({
      'manualControl': {
        'lastRequestedPercent': 1.0,
        'lastSubmittedPercent': 0.5,
        'lastApiSuccess': {'requestedPercent': 0.5, 'stopRequest': false},
        'lastApiError': {
          'requestedPercent': 1.0,
          'error': {'message': 'radio lost'},
        },
      },
      'manualControlEvents': [],
    });
    expect(state.requested, 1.0);
    expect(state.apiPercent, 0.5);
    expect(state.apiStatus, contains('0,5'));
    expect(state.apiError, contains('radio lost'));
  });
}
