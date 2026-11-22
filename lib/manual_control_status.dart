/// Presentation of the native safety decision. It never grants native eligibility.
class ManualActivationStatus {
  const ManualActivationStatus(this.code, this.canChange);
  final String code;
  final bool canChange;

  factory ManualActivationStatus.fromReport(
    Map<String, Object?> report, {
    required bool commandBusy,
    required bool stopping,
  }) {
    final manual = report['manualControl'] as Map? ?? const {};
    if (stopping) {
      return const ManualActivationStatus('session_stopping', false);
    }
    if (commandBusy) {
      return const ManualActivationStatus('command_in_progress', false);
    }
    if (report['controlTransportUncertain'] == true) {
      return const ManualActivationStatus('control_transport_uncertain', false);
    }
    if (report['status'] == 'starting') {
      return const ManualActivationStatus('starting', false);
    }
    if (report['running'] != true) {
      return const ManualActivationStatus('no_training_session', false);
    }
    if (report['sessionId'] is! String ||
        (report['sessionId'] as String).isEmpty) {
      return const ManualActivationStatus('session_not_ready', false);
    }
    if (manual['faulted'] == true) {
      return const ManualActivationStatus(
        'api_fault_requires_reconnect',
        false,
      );
    }
    if (manual['stopped'] == true) {
      return const ManualActivationStatus('session_stopped', false);
    }
    final remaining = manual['remainingMs'];
    if (manual['unavailableReason'] == 'test_timeout' ||
        (manual['enabled'] == true && remaining is num && remaining <= 0)) {
      return const ManualActivationStatus('test_timeout', false);
    }
    if (manual['enabled'] == true && manual['eligible'] != false) {
      return const ManualActivationStatus('test_enabled', true);
    }
    if (manual['eligible'] != true) {
      var reason =
          manual['unavailableReason'] as String? ?? 'native_state_missing';
      // Older native snapshots conflated channel type and identity verification.
      if (reason == 'dedicated_identity_required' &&
          report['channelMode'] == 'background_receive_only') {
        reason = 'dedicated_channel_required';
      }
      return ManualActivationStatus(reason, false);
    }
    return const ManualActivationStatus('ready', true);
  }

  String get message => code.startsWith('link_lost:')
      ? 'Enlace ANT perdido ($code). Control bloqueado; espera el cierre y reconecta. No se reactivará automáticamente.'
      : switch (code) {
          'control_transport_uncertain' => 'No se conoce el resultado de la comunicación. Control bloqueado hasta reconectar; puedes intentar detener.',
          'continuous_physical_validation_required' => 'Modo continuo bloqueado: requiere validación física de parada y búfer ANT.',
          'ready' => 'Condiciones cumplidas. Puedes abrir la confirmación; todavía no se transmite ninguna orden.',
          'test_enabled' =>
            'Prueba habilitada. Desmarcar inicia la parada controlada.',
          'starting' =>
            'Conectando: esperando el estado de la nueva sesión ANT.',
          'command_in_progress' =>
            'Hay una operación en curso. Espera su respuesta.',
          'no_training_session' =>
            'No hay entrenamiento activo. Pulsa «Iniciar entrenamiento».',
          'session_not_ready' => 'Falta el identificador de la sesión actual. Esperando estado de Kotlin.',
          'session_stopping' || 'session_stopped' => 'La sesión está cerrándose o ya finalizó. Vuelve a conectar para otra prueba.',
          'api_fault_requires_reconnect' || 'session_requires_reconnect' => 'Hubo un fallo en la prueba. Finaliza y vuelve a conectar; no se reintentan órdenes.',
          'test_timeout' => 'Se alcanzó el máximo de 30 segundos. Espera el cierre y vuelve a conectar.',
          'wrong_target' =>
            'El control solo está permitido para el dispositivo 30064/112/5.',
          'dedicated_channel_required' => 'Canal de solo recepción: finaliza y pulsa «Iniciar entrenamiento» para abrir el canal específico.',
          'dedicated_identity_required' => 'Falta el canal específico o verificar la identidad. Finaliza y conecta con «Iniciar entrenamiento».',
          'channel_not_open' => 'El canal específico todavía no está abierto. Espera a que finalice la conexión.',
          'radio_unavailable' => 'La radio ANT o el canal dejaron de estar disponibles. Finaliza y vuelve a conectar.',
          'session_closed' =>
            'La sesión nativa está cerrada. Inicia un entrenamiento nuevo.',
          'active_channel_identity_not_verified' => 'Todavía no coinciden los ID seleccionado, configurado, leído del adaptador y recibido. Consulta las condiciones de seguridad.',
          'identity_not_verified' => 'Esperando un paquete con la identidad exacta del dispositivo seleccionado.',
          'manufacturer_model_not_verified' => 'Esperando la página 0x50 de esta sesión: fabricante 67 y modelo 22.',
          'signal_not_fresh' =>
            'No hay una página reciente del rodillo (menos de 3 segundos).',
          'control_suspended' => 'Control suspendido por telemetría parcial. Puedes seguir recibiendo datos. Para volver a autorizar el control, inicia otra conexión.',
          'telemetry_not_fresh' => 'Esperando velocidad, potencia y cadencia válidas y recientes (menos de 10 segundos).',
          'native_state_missing' =>
            'Kotlin todavía no ha confirmado las condiciones de seguridad.',
          _ =>
            'Kotlin mantiene el bloqueo: $code. Exporta el diagnóstico JSON.',
        };
}
