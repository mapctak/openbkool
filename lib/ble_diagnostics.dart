import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// Identificadores contrastados con docs/protocolo_bkool.md, sección 2.
final cyclingPowerService = Guid('1818');
final bkoolConfigService = Guid('f03eee01-4910-473c-be46-960948c2f59c');

/// Conserva datos vistos en distintos anuncios: un paquete sin nombre/UUID
/// no debe borrar una pista recibida anteriormente en la misma sesión.
class BleObservation {
  BleObservation(ScanResult result)
    : device = result.device,
      firstSeen = result.timeStamp {
    update(result);
  }

  final BluetoothDevice device;
  final DateTime firstSeen;
  late DateTime lastSeen;
  late int rssi;
  late bool connectable;
  String advertisedName = '';
  String platformName = '';
  final Set<Guid> advertisedServices = {};
  final Set<Guid> serviceDataUuids = {};
  final Map<int, List<int>> manufacturerData = {};
  final Map<Guid, List<int>> serviceData = {};

  void update(ScanResult result) {
    lastSeen = result.timeStamp;
    rssi = result.rssi;
    final ad = result.advertisementData;
    connectable = ad.connectable;
    if (ad.advName.isNotEmpty) advertisedName = ad.advName;
    if (device.platformName.isNotEmpty) platformName = device.platformName;
    advertisedServices.addAll(ad.serviceUuids);
    serviceDataUuids.addAll(ad.serviceData.keys);
    manufacturerData.addAll(ad.manufacturerData);
    serviceData.addAll(ad.serviceData);
  }

  String get displayName => advertisedName.isNotEmpty
      ? advertisedName
      : platformName.isNotEmpty
      ? platformName
      : '(sin nombre)';
  bool get nameMatchesBkool =>
      advertisedName.toLowerCase().contains('bkool') ||
      platformName.toLowerCase().contains('bkool');
  bool get advertisesCyclingPower =>
      advertisedServices.contains(cyclingPowerService);
  bool get advertisesBkoolConfig =>
      advertisedServices.contains(bkoolConfigService);
  bool get isCandidate =>
      nameMatchesBkool || advertisesCyclingPower || advertisesBkoolConfig;

  Map<String, Object?> toJson() => {
    'deviceId': device.remoteId.str,
    'advertisedName': advertisedName,
    'platformName': platformName,
    'rssi': rssi,
    'connectable': connectable,
    'firstSeen': firstSeen.toUtc().toIso8601String(),
    'lastSeen': lastSeen.toUtc().toIso8601String(),
    'advertisedServiceUuids': advertisedServices.map((u) => u.str128).toList()
      ..sort(),
    'serviceDataUuids': serviceDataUuids.map((u) => u.str128).toList()..sort(),
    'manufacturerData': manufacturerData.map(
      (id, data) => MapEntry(id.toString(), data),
    ),
    'serviceData': serviceData.map((id, data) => MapEntry(id.str128, data)),
    'hints': {
      'nameContainsBkool': nameMatchesBkool,
      'advertisesCyclingPower': advertisesCyclingPower,
      'advertisesBkoolConfig': advertisesBkoolConfig,
    },
  };
}

/// FBP devuelve servicios primarios; los secundarios se consultan por includedServices.
List<BluetoothService> allGattServices(Iterable<BluetoothService> primary) {
  final seen = <BluetoothService>{};
  void visit(BluetoothService service) {
    if (!seen.add(service)) return;
    for (final included in service.includedServices) {
      visit(included);
    }
  }

  for (final service in primary) {
    visit(service);
  }
  return seen.toList();
}

Map<String, Object?> describeGattServices(List<BluetoothService> services) => {
  'hasBkoolConfigService': services.any((s) => s.uuid == bkoolConfigService),
  'hasCyclingPowerService': services.any((s) => s.uuid == cyclingPowerService),
  'services': services
      .map(
        (s) => {
          'uuid': s.uuid.str128,
          'primary': s.isPrimary,
          'primaryServiceUuid': s.primaryServiceUuid?.str128,
          'characteristics': s.characteristics
              .map(
                (c) => {
                  'uuid': c.uuid.str128,
                  'instanceId': c.instanceId,
                  'properties': {
                    'read': c.properties.read,
                    'write': c.properties.write,
                    'writeWithoutResponse': c.properties.writeWithoutResponse,
                    'notify': c.properties.notify,
                    'indicate': c.properties.indicate,
                  },
                  'descriptors': c.descriptors
                      .map((d) => d.uuid.str128)
                      .toList(),
                },
              )
              .toList(),
        },
      )
      .toList(),
};

Map<String, Object?> diagnosticReport({
  required Iterable<BleObservation> observations,
  required Iterable<Map<String, Object?>> discoveries,
  required List<Map<String, Object?>> events,
  required String adapterState,
  Map<String, Object?> antDiagnostics = const {'status': 'not_checked'},
  Map<String, Object?> antTraining = const {'status': 'not_started'},
  Map<String, Object?> antTrainerSearch = const {
    'status': 'not_started',
    'running': false,
  },
}) => {
  'schemaVersion': 1,
  'application': 'OpenBkool',
  'flutterBluePlusVersion': '2.3.14',
  'exportedAt': DateTime.now().toUtc().toIso8601String(),
  'adapterState': adapterState,
  'scanSettings': {
    'durationSeconds': 30,
    'filters': <String, Object?>{},
    'continuousUpdates': true,
    'androidScanMode': 'lowLatency',
    'androidUsesFineLocation': true,
  },
  'devices': observations.map((o) => o.toJson()).toList(),
  'gattDiscoveries': discoveries.toList(),
  'events': events.reversed.toList(),
  'antDiagnostics': antDiagnostics,
  'antTrainerSearch': antTrainerSearch,
  'antTraining': antTraining,
};
