import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ant_diagnostics.dart';
import 'ant_trainer_search.dart';

class SavedTrainer {
  const SavedTrainer(
    this.number,
    this.type,
    this.transmission, {
    this.model,
    this.manufacturer,
  });
  static const known = SavedTrainer(30064, 112, 5, model: 22, manufacturer: 67);
  final int number, type, transmission;
  final int? model, manufacturer;
  String get id => '$number/$type/$transmission';
  String get name => switch (model) {
    22 => 'Bkool Smart Pro v1',
    24 => 'Bkool Smart Pro v2',
    _ => 'Rodillo ANT seleccionado',
  };
  Map<String, Object?> get device => {
    'protocol': 'BKOOL_V1_PUBLIC',
    'deviceNumber': number,
    'deviceType': type,
    'transmissionType': transmission,
  };
  Map<String, Object?> toJson() => {
    ...device,
    'modelNumber': model,
    'manufacturerId': manufacturer,
  };
  factory SavedTrainer.fromMap(Map map) {
    final n = map['deviceNumber'],
        t = map['deviceType'],
        x = map['transmissionType'];
    if (map['protocol'] != 'BKOOL_V1_PUBLIC' ||
        n is! int ||
        n < 1 ||
        n > 65535 ||
        t != 112 ||
        x is! int ||
        x < 1 ||
        x > 255) {
      throw const FormatException('Identidad ANT V1 inválida');
    }
    return SavedTrainer(
      n,
      112,
      x,
      model: map['modelNumber'] as int?,
      manufacturer: map['manufacturerId'] as int?,
    );
  }
  bool matches(Map? value) =>
      value != null &&
      value['protocol'] == 'BKOOL_V1_PUBLIC' &&
      value['deviceNumber'] == number &&
      value['deviceType'] == type &&
      value['transmissionType'] == transmission;
}

class TrainerPreferences {
  const TrainerPreferences();
  static const channel = MethodChannel('openbkool/preferences');
  Future<SavedTrainer?> load() async {
    final value = await channel.invokeMapMethod<String, dynamic>('loadTrainer');
    return value == null ? null : SavedTrainer.fromMap(value);
  }

  Future<String?> loadControlConsent() =>
      channel.invokeMethod<String>('loadControlConsent');

  Future<void> saveControlConsent(String? record) =>
      channel.invokeMethod<void>('saveControlConsent', record);

  Future<void> save(SavedTrainer trainer) =>
      channel.invokeMethod<void>('saveTrainer', trainer.toJson());
}

enum TrainerConnection {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

TrainerConnection connectionFor(Map<String, Object?> r, SavedTrainer selected) {
  if (r['running'] == true) {
    if (r['status'] == 'stopping_zero_unconfirmed') {
      return TrainerConnection.disconnecting;
    }
    if (r['status'] == 'starting' ||
        r['sessionId'] is! String ||
        (r['sessionId'] as String).isEmpty ||
        !selected.matches(r['selectedDevice'] as Map?)) {
      return TrainerConnection.connecting;
    }
    final t = r['telemetry'] as Map?;
    if (t?['signal'] == 'signal_lost' || t?['signal'] == 'disconnected') {
      return TrainerConnection.error;
    }
    if (r['connectionState'] == 'identity_verified' &&
        t?['signal'] == 'receiving') {
      return TrainerConnection.connected;
    }
    return TrainerConnection.connecting;
  }
  final status = r['status'] as String? ?? 'not_started';
  if (r['clientError'] != null ||
      status.contains('error') ||
      status == 'cleanup_failed' ||
      const {
        'disconnected',
        'channel_death',
        'channel_closed',
        'radio_search_timeout',
        'radio_service_disconnected',
        'training_service_destroyed',
      }.contains(status) ||
      status.startsWith('link_lost')) {
    return TrainerConnection.error;
  }
  return TrainerConnection.disconnected;
}

String connectionLabel(TrainerConnection c) => switch (c) {
  TrainerConnection.disconnected => 'Desconectado',
  TrainerConnection.connecting => 'Conectando',
  TrainerConnection.connected => 'Conectado',
  TrainerConnection.disconnecting => 'Desconectando',
  TrainerConnection.error => 'Error de conexión',
};

class TrainerSession extends ChangeNotifier {
  TrainerSession({
    AntTrainerSearchController? training,
    AntTrainerSearchController? search,
    AntDiagnosticsController? diagnostics,
    this.preferences = const TrainerPreferences(),
  }) : training =
           training ??
           AntTrainerSearchController(channelName: 'openbkool/training'),
       search = search ?? AntTrainerSearchController(),
       diagnostics = diagnostics ?? AntDiagnosticsController() {
    this.training.addListener(_notify);
  }
  final AntTrainerSearchController training, search;
  final AntDiagnosticsController diagnostics;
  final TrainerPreferences preferences;
  SavedTrainer selected = SavedTrainer.known;
  bool loading = true, saving = false, _disposed = false;
  bool _connecting = false;
  static const controlPolicy = 1;
  static const minSlope = -5.0, maxSlope = 15.0;
  String? consentError;
  String? _controlConsent;

  String _consentRecord(SavedTrainer trainer) => jsonEncode({
    ...trainer.device,
    'manufacturerId': 67,
    'modelNumber': 22,
    'policyVersion': controlPolicy,
    'minPercent': minSlope,
    'maxPercent': maxSlope,
  });

  bool get hasControlConsent => _controlConsent == _consentRecord(selected);

  Future<void> setControlConsent(bool granted) async {
    if (loading || saving || (!granted && locked)) return;
    final record = granted ? _consentRecord(selected) : null;
    saving = true;
    consentError = null;
    _notify();
    try {
      await preferences.saveControlConsent(record);
      _controlConsent = record;
    } catch (_) {
      consentError = 'No se pudo guardar el permiso de control.';
    } finally {
      saving = false;
      _notify();
    }
  }

  String? preferenceError;
  int _selectionRevision = 0;
  TrainerConnection get connection => _connecting && !training.running
      ? TrainerConnection.connecting
      : connectionFor(training.snapshot, selected);
  bool get locked =>
      _connecting || training.running || training.commandBusy || saving;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    final revision = _selectionRevision;
    try {
      final saved = await preferences.load();
      if (!_disposed && revision == _selectionRevision && saved != null) {
        selected = saved;
      }
    } catch (error) {
      if (!_disposed && revision == _selectionRevision) {
        preferenceError = 'No se pudo leer el rodillo guardado: $error';
      }
    }
    try {
      _controlConsent = await preferences.loadControlConsent();
    } catch (_) {
      consentError = 'No se pudo leer el permiso de control.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> select(SavedTrainer trainer) async {
    if (locked) {
      throw StateError('Finaliza el entrenamiento antes de cambiar de rodillo');
    }
    _selectionRevision++;
    saving = true;
    preferenceError = null;
    _notify();
    try {
      await preferences.save(trainer);
      if (!_disposed) selected = trainer;
    } catch (error) {
      preferenceError = 'No se pudo guardar el rodillo: $error';
      rethrow;
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<void> connect() async {
    if (loading || locked) return;
    _connecting = true;
    _notify();
    try {
      await training.start('training_connected', device: selected.device);
    } finally {
      _connecting = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    training.removeListener(_notify);
    training.dispose();
    search.dispose();
    diagnostics.dispose();
    super.dispose();
  }
}
