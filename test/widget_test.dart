import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/ble_diagnostics.dart';
import 'package:openbkool/main.dart';

/// Radio simulada. Se incluyen Services Changed y su CCCD para detectar una
/// suscripción implícita del plugin aunque la app no invoque write directamente.
final class TestBlePlatform extends FlutterBluePlusPlatform {
  final adapters = StreamController<BmBluetoothAdapterState>.broadcast(
    sync: true,
  );
  @override
  Stream<BmBluetoothAdapterState> get onAdapterStateChanged => adapters.stream;
  final scans = StreamController<BmScanResponse>.broadcast(sync: true);
  final connections = StreamController<BmConnectionStateResponse>.broadcast(
    sync: true,
  );
  final services = StreamController<BmDiscoverServicesResult>.broadcast(
    sync: true,
  );
  final List<BmScanSettings> settings = [];
  final List<DeviceIdentifier> selected = [];
  bool denyScan = false;
  int writeAttempts = 0;
  int notificationAttempts = 0;

  @override
  Stream<BmScanResponse> get onScanResponse => scans.stream;
  @override
  Stream<BmConnectionStateResponse> get onConnectionStateChanged =>
      connections.stream;
  @override
  Stream<BmDiscoverServicesResult> get onDiscoveredServices => services.stream;
  @override
  Future<bool> isSupported(BmIsSupportedRequest request) async => true;
  @override
  Future<BmBluetoothAdapterState> getAdapterState(
    BmBluetoothAdapterStateRequest request,
  ) async => BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);
  @override
  Future<bool> startScan(BmScanSettings request) async {
    settings.add(request);
    if (denyScan) {
      throw PlatformException(
        code: 'permission_denied',
        message: 'BLUETOOTH_SCAN denied',
      );
    }
    return true;
  }

  @override
  Future<bool> stopScan(BmStopScanRequest request) async => true;

  void advertise(List<BmScanAdvertisement> ads) => scans.add(
    BmScanResponse(
      advertisements: ads,
      success: true,
      errorCode: 0,
      errorString: '',
    ),
  );

  void connection(DeviceIdentifier id, BmConnectionStateEnum state) =>
      connections.add(
        BmConnectionStateResponse(
          remoteId: id,
          connectionState: state,
          disconnectReasonCode: 0,
          disconnectReasonString: 'test',
        ),
      );

  @override
  Future<bool> connect(BmConnectRequest request) async {
    selected.add(request.remoteId);
    connection(request.remoteId, BmConnectionStateEnum.connected);
    return true;
  }

  @override
  Future<bool> disconnect(BmDisconnectRequest request) async {
    connection(request.remoteId, BmConnectionStateEnum.disconnected);
    return true;
  }

  BmBluetoothService service(
    DeviceIdentifier id,
    String uuid, {
    String? parent,
    String? characteristic,
  }) => BmBluetoothService(
    remoteId: id,
    primaryServiceUuid: parent == null ? null : Guid(parent),
    serviceUuid: Guid(uuid),
    characteristics: characteristic == null
        ? []
        : [
            BmBluetoothCharacteristic.fromMap({
              'remote_id': id.str,
              'primary_service_uuid': parent,
              'service_uuid': uuid,
              'characteristic_uuid': characteristic,
              'instance_id': 0,
              'properties': {
                'read': 1,
                'notify': 1,
                'indicate': 1,
                'write': 0,
                'broadcast': 0,
                'write_without_response': 0,
                'authenticated_signed_writes': 0,
                'extended_properties': 0,
                'notify_encryption_required': 0,
                'indicate_encryption_required': 0,
              },
              'descriptors': [
                {
                  'remote_id': id.str,
                  'primary_service_uuid': parent,
                  'service_uuid': uuid,
                  'characteristic_uuid': characteristic,
                  'descriptor_uuid': '2902',
                  'instance_id': 0,
                },
              ],
            }),
          ],
  );

  @override
  Future<bool> discoverServices(BmDiscoverServicesRequest request) async {
    final id = request.remoteId;
    services.add(
      BmDiscoverServicesResult(
        remoteId: id,
        success: true,
        errorCode: 0,
        errorString: '',
        services: [
          service(id, '1801', characteristic: '2a05'),
          service(
            id,
            bkoolConfigService.str128,
            characteristic: 'f03ee002-4910-473c-be46-960948c2f59c',
          ),
          service(id, '1818', characteristic: '2a63'),
          service(
            id,
            '180a',
            parent: bkoolConfigService.str128,
            characteristic: '2a27',
          ),
        ],
      ),
    );
    return true;
  }

  @override
  Future<bool> writeCharacteristic(BmWriteCharacteristicRequest request) async {
    writeAttempts++;
    throw StateError('Escritura GATT prohibida');
  }

  @override
  Future<bool> writeDescriptor(BmWriteDescriptorRequest request) async {
    writeAttempts++;
    throw StateError('Escritura CCCD prohibida');
  }

  @override
  Future<bool> setNotifyValue(BmSetNotifyValueRequest request) async {
    notificationAttempts++;
    throw StateError('Suscripción prohibida');
  }
}

BmScanAdvertisement advertisement(
  String id, {
  String name = '',
  String? platformName,
  List<String> uuids = const [],
  int rssi = -40,
}) => BmScanAdvertisement(
  remoteId: DeviceIdentifier(id),
  platformName: platformName,
  advName: name,
  connectable: false,
  txPowerLevel: null,
  appearance: null,
  manufacturerData: {
    123: [1, 2],
  },
  serviceData: {},
  serviceUuids: uuids.map(Guid.new).toList(),
  rssi: rssi,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final radio = TestBlePlatform();
  String? clipboard;
  bool denyPermissionRequest = false;
  bool failAnt = false;
  int antCalls = 0;
  bool failSearch = false;
  final searchCommands = <String>[];
  Map<String, Object?> searchReport = {};
  void emitSearch() {
    ServicesBinding.instance.channelBuffers.push(
      'openbkool/ant_search/events',
      const StandardMethodCodec().encodeSuccessEnvelope(searchReport),
      (_) {},
    );
  }

  Map<String, Object?> antReport = {};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('openbkool/ant_search/events'),
          (call) async {
            if (call.method == 'listen') scheduleMicrotask(emitSearch);
            return null;
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('openbkool/ant_search'), (
          call,
        ) async {
          if (call.method == 'start') {
            if (failSearch) {
              throw PlatformException(
                code: 'ant_busy',
                message: 'Otra operación ANT está usando la radio',
              );
            }
            searchCommands.add('start:${(call.arguments as Map)['mode']}');
            searchReport = {
              ...searchReport,
              'running': true,
              'status': 'running',
              'stage': 'fec_search',
              'resourcesReleased': false,
            };
          } else if (call.method == 'stop') {
            searchCommands.add('stop');
            searchReport = {
              ...searchReport,
              'running': false,
              'status': 'stopped',
              'stage': 'finished',
              'resourcesReleased': true,
            };
          }
          emitSearch();
          return call.method == 'start' ? null : searchReport;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('openbkool/ant'), (
          call,
        ) async {
          expect(call.method, 'inspectCapabilities');
          antCalls++;
          if (failAnt) {
            throw PlatformException(
              code: 'test_failure',
              message: 'Servicio incompatible',
            );
          }
          return antReport;
        });
    FlutterBluePlusPlatform.instance = radio;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('openbkool/permissions'),
          (call) async {
            if (denyPermissionRequest) {
              throw PlatformException(
                code: 'permission_denied',
                message: 'Ubicación denegada',
              );
            }
            return true;
          },
        );
  });
  setUp(() {
    radio.settings.clear();
    radio.selected.clear();
    radio.denyScan = false;
    radio.writeAttempts = 0;
    radio.notificationAttempts = 0;
    denyPermissionRequest = false;
    clipboard = null;
    antCalls = 0;
    failSearch = false;
    searchCommands.clear();
    searchReport = {
      'status': 'not_started',
      'running': false,
      'devices': <Object?>[],
      'messages': <Object?>[],
      'events': <Object?>[],
    };
    failAnt = false;
    antReport = {
      'status': 'completed',
      'checkedAt': '2026-11-12T22:00:00Z',
      'antLibVersion': '4.16.0',
      'android': {
        'sdkInt': 36,
        'release': '16',
        'manufacturer': 'test',
        'model': 'phone',
        'targetSdk': 36,
        'newerThanSdkDocumented': true,
      },
      'builtInHardware': {'declared': false, 'observed': false},
      'radioService': {
        'installed': true,
        'enabled': true,
        'versionName': '4.18.0',
      },
      'pluginsService': {
        'installed': true,
        'enabled': true,
        'versionName': '3.9.0',
      },
      'channelProvider': {
        'responsive': true,
        'operational': false,
        'availableChannels': 0,
      },
      'radio': {
        'accessible': false,
        'status': 'no_free_channels',
        'reservationAcquired': false,
      },
      'adapters': <Object?>[],
      'errors': <Object?>[],
    };
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(const OpenBkoolApp());
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  }

  Future<void> export(WidgetTester tester) async {
    await tester.tap(find.text('Exportar diagnóstico JSON'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Escaneo sin filtros, anuncios parciales, conexión manual y JSON sin escrituras',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Buscar dispositivos BLE'));
      await tester.pumpAndSettle();
      expect(
        radio.settings,
        isNotEmpty,
        reason: tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((t) => t.data)
            .join('\n'),
      );
      final settings = radio.settings.single;
      expect(settings.withServices, isEmpty);
      expect(settings.withNames, isEmpty);
      expect(settings.withKeywords, isEmpty);
      expect(settings.withRemoteIds, isEmpty);
      expect(settings.withMsd, isEmpty);
      expect(settings.withServiceData, isEmpty);
      expect(settings.continuousUpdates, isTrue);
      expect(settings.androidUsesFineLocation, isTrue);

      const unnamed = 'AA:00:00:00:00:01';
      radio.advertise([
        advertisement(
          unnamed,
        ), // Sin UUID, sin nombre y no conectable: seleccionable.
        advertisement('AA:00:00:00:00:02', name: 'bKoOl antiguo', rssi: -50),
        advertisement('AA:00:00:00:00:03', uuids: ['1818'], rssi: -60),
      ]);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('(sin nombre)'), findsNWidgets(2));
      expect(
        find.textContaining('PISTA: nombre contiene BKOOL'),
        findsOneWidget,
      );
      expect(
        find.textContaining('PISTA: Cycling Power 0x1818'),
        findsOneWidget,
      );
      expect(
        find.textContaining('00001818-0000-1000-8000-00805f9b34fb'),
        findsOneWidget,
      );

      // Un paquete sin nombre ni UUID no borra la pista previa.
      radio.advertise([advertisement('AA:00:00:00:00:02', rssi: -70)]);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('bKoOl antiguo'), findsOneWidget);
      await export(tester);
      var report = jsonDecode(clipboard!) as Map<String, dynamic>;
      expect((report['devices'] as List).length, 3);
      expect(report['gattDiscoveries'], isEmpty);
      expect(report['antDiagnostics'], {'status': 'not_checked'});
      expect(antCalls, 0);

      final tile = find.descendant(
        of: find.byKey(const ValueKey('device-$unnamed')),
        matching: find.byType(ListTile),
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(radio.selected.single.str, unnamed);
      expect(
        find.textContaining(
          'Último GATT: servicio propietario Bkool ENCONTRADO',
        ),
        findsOneWidget,
      );
      await export(tester);
      report = jsonDecode(clipboard!) as Map<String, dynamic>;
      final gatt = (report['gattDiscoveries'] as List).single as Map;
      expect(gatt['hasBkoolConfigService'], isTrue);
      expect(
        (gatt['services'] as List).length,
        4,
      ); // Incluye servicio secundario.
      final config = (gatt['services'] as List).cast<Map>().singleWhere(
        (s) => s['uuid'] == bkoolConfigService.str128,
      );
      expect(
        (config['characteristics'] as List).single['uuid'],
        'f03ee002-4910-473c-be46-960948c2f59c',
      );
      expect(
        report['events'],
        contains(
          isA<Map>().having((e) => e['event'], 'evento', 'scan_stopped'),
        ),
      );
      expect(radio.writeAttempts, 0);
      expect(radio.notificationAttempts, 0);

      radio.connection(
        DeviceIdentifier(unnamed),
        BmConnectionStateEnum.disconnected,
      );
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión'), findsOneWidget);
      await export(tester);
      report = jsonDecode(clipboard!) as Map<String, dynamic>;
      expect((report['gattDiscoveries'] as List).length, 1);
      expect(
        report['events'],
        contains(
          isA<Map>().having((e) => e['event'], 'evento', 'disconnected'),
        ),
      );
      await close(tester);
    },
  );

  testWidgets('Permiso denegado se exporta sin iniciar el escaneo', (
    tester,
  ) async {
    denyPermissionRequest = true;
    await open(tester);
    await tester.tap(find.text('Buscar dispositivos BLE'));
    await tester.pumpAndSettle();
    expect(radio.settings, isEmpty);
    await export(tester);
    final report = jsonDecode(clipboard!) as Map;
    expect(
      report['events'],
      contains(
        isA<Map>().having((e) => e['event'], 'evento', 'permission_error'),
      ),
    );
    expect(report['devices'], isEmpty);
    await close(tester);
  });

  testWidgets('Error de escaneo no bloquea reintento y se exporta', (
    tester,
  ) async {
    radio.denyScan = true;
    await open(tester);
    await tester.tap(find.text('Buscar dispositivos BLE'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Buscar dispositivos BLE'),
          )
          .onPressed,
      isNotNull,
    );
    await export(tester);
    final report = jsonDecode(clipboard!) as Map;
    expect(
      report['events'],
      contains(isA<Map>().having((e) => e['event'], 'evento', 'scan_error')),
    );
    radio.denyScan = false;
    await tester.tap(find.text('Buscar dispositivos BLE'));
    await tester.pumpAndSettle();
    expect(radio.settings.length, 2);
    await tester.tap(find.text('Detener escaneo'));
    await tester.pumpAndSettle();
    await close(tester);
  });

  testWidgets(
    'Escaneo vacío termina por timeout y conserva diagnóstico exportable',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Buscar dispositivos BLE'));
      await tester.pumpAndSettle();
      expect(radio.settings.length, 1);
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      await export(tester);
      final report = jsonDecode(clipboard!) as Map;
      expect(report['devices'], isEmpty);
      expect(
        report['events'],
        contains(isA<Map>().having((e) => e['event'], 'evento', 'scan_empty')),
      );
      expect(find.text('Buscar dispositivos BLE'), findsOneWidget);
      await close(tester);
    },
  );
  testWidgets(
    'ANT distingue servicios instalados de radio y preserva BLE al navegar',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Buscar dispositivos BLE'));
      await tester.pumpAndSettle();
      radio.advertise([
        advertisement('AA:00:00:00:00:09', name: 'Bkool conservado'),
      ]);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagnóstico ANT+'));
      await tester.pumpAndSettle();
      expect(
        antCalls,
        0,
      ); // Navegar no reserva ni consulta la radio automáticamente.
      await tester.tap(find.text('Comprobar capacidades ANT'));
      await tester.pumpAndSettle();
      expect(antCalls, 1);
      expect(find.textContaining('Instalado · habilitado'), findsNWidgets(2));
      expect(
        find.textContaining('Radio accesible en esta consulta: No'),
        findsOneWidget,
      );
      expect(find.textContaining('API 36'), findsOneWidget);
      expect(find.textContaining('No hay canales libres.'), findsOneWidget);
      await export(tester);
      var report = jsonDecode(clipboard!) as Map;
      expect(report['antDiagnostics'], antReport);
      expect(
        (report['devices'] as List).single['advertisedName'],
        'Bkool conservado',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Bkool conservado'), findsOneWidget);
      await export(tester);
      report = jsonDecode(clipboard!) as Map;
      expect(report['antDiagnostics'], antReport);
      expect(radio.writeAttempts, 0);
      expect(radio.notificationAttempts, 0);
      await close(tester);
    },
  );

  testWidgets(
    'ANT exporta fallos MethodChannel sin afirmar disponibilidad de radio',
    (tester) async {
      failAnt = true;
      await open(tester);
      await tester.tap(find.text('Diagnóstico ANT+'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprobar capacidades ANT'));
      await tester.pumpAndSettle();
      expect(find.text('Error del canal de diagnóstico'), findsOneWidget);
      expect(
        find.textContaining('Radio accesible en esta consulta: No comprobado'),
        findsOneWidget,
      );
      await export(tester);
      final report = jsonDecode(clipboard!) as Map;
      expect(report['antDiagnostics']['status'], 'channel_error');
      expect(
        (report['antDiagnostics']['errors'] as List).single['code'],
        'test_failure',
      );
      await close(tester);
    },
  );

  testWidgets(
    'ANT confirma radio externa sin atribuir hardware integrado ni requerir Plugins',
    (tester) async {
      antReport['pluginsService'] = {'installed': false};
      antReport['channelProvider'] = {
        'responsive': true,
        'operational': true,
        'availableChannels': 8,
      };
      antReport['radio'] = {
        'accessible': true,
        'reservationAcquired': true,
        'released': true,
      };
      antReport['adapters'] = [
        {'id': 'test-usb', 'builtIn': false, 'version': 'test'},
      ];
      await open(tester);
      await tester.tap(find.text('Diagnóstico ANT+'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprobar capacidades ANT'));
      await tester.pumpAndSettle();
      expect(find.text('Adaptador externo'), findsOneWidget);
      expect(
        find.textContaining('Radio accesible en esta consulta: Sí'),
        findsOneWidget,
      );
      expect(find.textContaining('Declarado por Android: No'), findsOneWidget);
      expect(find.text('No instalado'), findsOneWidget);
      await export(tester);
      final report = jsonDecode(clipboard!) as Map;
      expect(report['antDiagnostics']['radio']['released'], true);
      expect(report['antDiagnostics']['builtInHardware']['declared'], false);
      await close(tester);
    },
  );
  testWidgets(
    'Búsqueda ANT secuencial muestra páginas y exporta los tres diagnósticos',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Buscar rodillos ANT'));
      await tester.pumpAndSettle();
      expect(searchCommands, isEmpty);
      await tester.tap(find.text('Iniciar búsqueda ANT'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(searchCommands, ['start:sequential']);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Iniciar búsqueda ANT'),
            )
            .onPressed,
        isNull,
      );
      searchReport = {
        ...searchReport,
        'stage': 'bkool_v1',
        'devices': [
          {
            'protocol': 'BKOOL_V1_PUBLIC',
            'deviceNumber': 1234,
            'deviceType': 112,
            'transmissionType': 7,
            'manufacturerId': 67,
            'modelNumber': 24,
            'bkoolModel': 'Smart Pro v2',
            'bkoolConfirmed': true,
            'lastSeen': 'test',
          },
        ],
        'messages': [
          {
            'messageType': 'BROADCAST_DATA',
            'messageId': 78,
            'messageIdHex': '4E',
            'deviceNumber': 1234,
            'timestamp': 'test',
            'contentHex': '00 50 FF FF 02 43 00 18 00 80 D2 04 70 07',
            'payloadHex': '50 FF FF 02 43 00 18 00',
          },
        ],
      };
      emitSearch();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('BKOOL Smart Pro v2'), findsOneWidget);
      expect(find.textContaining('50 FF FF 02 43 00 18 00'), findsOneWidget);
      await tester.tap(find.text('Exportar diagnóstico JSON'));
      await tester.pump(const Duration(milliseconds: 300));
      var report = jsonDecode(clipboard!) as Map;
      expect(report['antTrainerSearch']['devices'].single['modelNumber'], 24);
      expect(report.containsKey('antDiagnostics'), isTrue);
      expect(report.containsKey('devices'), isTrue);
      await tester.tap(find.text('Detener búsqueda ANT'));
      await tester.pumpAndSettle();
      expect(searchCommands, ['start:sequential', 'stop']);
      expect(find.text('Recursos liberados: sí'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await export(tester);
      report = jsonDecode(clipboard!) as Map;
      expect(
        report['antTrainerSearch']['devices'].single['deviceNumber'],
        1234,
      );
      await close(tester);
    },
  );

  testWidgets('Volver de la búsqueda ANT detiene y espera la liberación', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Buscar rodillos ANT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Iniciar búsqueda ANT'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(searchCommands, ['start:sequential', 'stop']);
    expect(find.text('OpenBkool · BLE diagnóstico'), findsOneWidget);
    await close(tester);
  });

  testWidgets(
    'Operación ANT ocupada se muestra sin iniciar una búsqueda incompatible',
    (tester) async {
      failSearch = true;
      await open(tester);
      await tester.tap(find.text('Buscar rodillos ANT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iniciar búsqueda ANT'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ant_busy'), findsOneWidget);
      expect(searchCommands, isEmpty);
      await export(tester);
      final report = jsonDecode(clipboard!) as Map;
      expect(report['antTrainerSearch']['status'], 'start_error');
      expect(report['antTrainerSearch']['running'], false);
      await close(tester);
    },
  );
  testWidgets(
    'Fallo ANT identifica la operación exacta y exporta todos sus eventos',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Buscar rodillos ANT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iniciar búsqueda ANT'));
      await tester.pump(const Duration(milliseconds: 600));
      final operationEvents = <Map<String, Object?>>[
        {
          'operationId': 1,
          'operation': 'v1.setPeriod',
          'state': 'started',
          'arguments': {'period': 32768},
        },
        {
          'operationId': 1,
          'operation': 'v1.setPeriod',
          'state': 'failed',
          'durationMs': 1.5,
          'error': {
            'type': 'AntCommandFailedException',
            'failureReason': 'INVALID_REQUEST',
            'message': 'simulado',
          },
        },
        {
          'operationId': 2,
          'operation': 'cleanup.releaseChannel',
          'state': 'succeeded',
        },
      ];
      searchReport = {
        ...searchReport,
        'running': false,
        'status': 'partial',
        'stage': 'finished',
        'resourcesReleased': true,
        'events': <Object?>[],
        'operationEvents': operationEvents,
        'v1Failure': {
          'operation': 'v1.setPeriod',
          'error': operationEvents[1]['error'],
        },
        'channelCapabilities': {
          'backgroundScanning': true,
          'extendedAssign': true,
          'rfMin': 0,
          'rfMax': 124,
        },
      };
      emitSearch();
      await tester.pumpAndSettle();
      expect(find.text('Operación V1 fallida'), findsOneWidget);
      expect(find.textContaining('v1.setPeriod'), findsOneWidget);
      expect(find.textContaining('INVALID_REQUEST'), findsOneWidget);
      await export(tester);
      final report = jsonDecode(clipboard!) as Map;
      expect(report['antTrainerSearch']['operationEvents'], operationEvents);
      expect(
        report['antTrainerSearch']['v1Failure']['operation'],
        'v1.setPeriod',
      );
      expect(
        report['antTrainerSearch']['channelCapabilities']['backgroundScanning'],
        true,
      );
      expect(report['antTrainerSearch']['resourcesReleased'], true);
      await close(tester);
    },
  );
}
