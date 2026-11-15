/// UI intent only. Never persisted, encoded or interpreted as an ANT acknowledgement.
class SlopeUiIntent {
  const SlopeUiIntent({
    required this.sessionId,
    required this.percent,
    required this.eventCount,
    this.pending = true,
  });
  final String? sessionId;
  final double percent;
  final int eventCount;
  final bool pending;
  SlopeUiIntent completed() => SlopeUiIntent(
    sessionId: sessionId,
    percent: percent,
    eventCount: eventCount,
    pending: false,
  );
}

class SlopePresentation {
  const SlopePresentation({
    this.requested,
    this.apiPercent,
    this.apiEvent,
    this.apiIsStop = false,
    required this.finished,
    required this.expired,
    required this.stopping,
    required this.pending,
    required this.unrecordedIntent,
    required this.rejected,
    this.stopResult,
    this.apiError,
  });
  final num? requested, apiPercent;
  final String? apiEvent, stopResult, apiError;
  final bool apiIsStop,
      finished,
      expired,
      stopping,
      pending,
      unrecordedIntent,
      rejected;
  static String percent(num? value) =>
      value == null ? '—' : value.toStringAsFixed(1).replaceAll('.', ',');
  factory SlopePresentation.fromReport(
    Map<String, Object?> report, {
    SlopeUiIntent? intent,
  }) {
    final manual = report['manualControl'] as Map? ?? const {};
    final events = report['manualControlEvents'] as List? ?? const [];
    final activeIntent =
        intent != null &&
            intent.sessionId != null &&
            intent.sessionId == report['sessionId']
        ? intent
        : null;
    num? requested, apiPercent;
    String? apiEvent, stopReason, apiError;
    bool apiStop = false, newerRequest = false, newerApi = false;
    for (var i = 0; i < events.length; i++) {
      final e = events[i] as Map;
      final value = e['requestedPercent'];
      final valid = value is num && value.isFinite;
      // Automatic stop zero is an API operation, not a new manual selection.
      if (valid &&
          (e['event'] == 'request' ||
              (e['event'] == 'api_attempt' && e['stopRequest'] != true))) {
        requested = value;
        if (activeIntent != null && i >= activeIntent.eventCount) {
          newerRequest = true;
        }
      }
      if (e['event'] == 'api_returned' || e['event'] == 'api_error') {
        if (e['event'] == 'api_returned' && e['stopRequest'] != true) {
          apiEvent = 'api_returned';
          apiPercent = valid ? value : null;
          apiStop = e['stopRequest'] == true;
        } else if (e['event'] == 'api_error') {
          apiError =
              'Error al enviar la orden a ANT: ${e['error'] ?? 'consulta el diagnóstico'}';
        }
        if (activeIntent != null && i >= activeIntent.eventCount) {
          newerApi = true;
        }
      }
      if (e['event'] == 'stop_requested') stopReason = e['reason'] as String?;
    }
    // Native snapshot is independent of RX pages and event history retention.
    if (manual['lastRequestedPercent'] is num) {
      requested = manual['lastRequestedPercent'] as num;
    }
    final lastSuccess = manual['lastApiSuccess'] as Map?;
    final success =
        manual['lastManualApiSuccess'] as Map? ??
        (lastSuccess?['stopRequest'] != true ? lastSuccess : null);
    if (success != null) {
      apiEvent = 'api_returned';
      apiPercent = success['requestedPercent'] as num?;
      apiStop = success['stopRequest'] == true;
    }
    final error = manual['lastApiError'] as Map?;
    if (error != null) {
      apiError = 'Error al enviar la orden a ANT: ${error['error']}';
    }
    if (report['clientError'] != null) apiError = '${report['clientError']}';
    if (activeIntent != null && !newerRequest) requested = activeIntent.percent;
    final stopped = manual['stopped'] == true;
    // A missing request history is unknown, not an implied manual request of zero.
    if (requested == null &&
        !stopped &&
        manual['lastSubmittedPercent'] is num) {
      requested = manual['lastSubmittedPercent'] as num;
    }
    final remaining = manual['remainingMs'];
    final expired =
        report['status'] == 'test_timeout' ||
        stopReason == 'test_timeout' ||
        manual['unavailableReason'] == 'test_timeout' ||
        (manual['enabled'] == true && remaining is num && remaining <= 0);
    final stopping =
        report['status'] == 'stopping_zero_unconfirmed' ||
        (stopped && report['running'] == true);
    return SlopePresentation(
      requested: requested,
      apiError: apiError,
      apiPercent: apiPercent,
      apiEvent: apiEvent,
      apiIsStop: apiStop,
      finished: stopped && !stopping,
      expired: expired,
      stopping: stopping,
      pending:
          activeIntent?.pending == true && !newerApi && !stopped && !expired,
      unrecordedIntent:
          activeIntent != null &&
          !activeIntent.pending &&
          !newerRequest &&
          !stopped,
      rejected: (manual['lastResult'] as Map?)?['event'] == 'rejected',
      stopResult: manual['stopResult'] as String?,
    );
  }
  String? get trialStatus => expired
      ? 'Prueba caducada (30 s)'
      : stopping
      ? 'Deteniendo prueba'
      : finished
      ? 'Prueba finalizada'
      : null;
  String get apiStatus => switch (apiEvent) {
    'api_returned' =>
      '${apiIsStop ? 'Orden de parada enviada' : 'Orden enviada'} a la API ANT: ${percent(apiPercent)} %',
    'api_error' =>
      '${apiIsStop ? 'Error al enviar la parada' : 'Error al enviar la orden'} a ANT${apiPercent == null ? '' : ': ${percent(apiPercent)} %'}',
    _ => 'Sin orden enviada a ANT',
  };
  String? get stopStatus {
    if (stopResult == 'zero_api_returned_unconfirmed') {
      return 'Parada: solicitud de 0 % entregada a la API; aplicación física sin confirmar.';
    }
    if (stopResult == 'zero_api_error') {
      return 'Parada: error al solicitar 0 %. Resistencia física desconocida.';
    }
    if (stopResult?.startsWith('zero_not_requested:') == true) {
      return 'Parada: no se solicitó 0 %. Consulta el diagnóstico; resistencia física desconocida.';
    }
    return null;
  }
}
