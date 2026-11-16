import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_diagnostics.dart';
import 'ant_diagnostics.dart';
import 'ant_trainer_search.dart';
import 'training.dart';
import 'app_home.dart';
import 'trainer_session.dart';
import 'experimental_slopes.dart';

void main() => runApp(const OpenBkoolApp());

class OpenBkoolApp extends StatelessWidget {
  const OpenBkoolApp({super.key, this.session});
  final TrainerSession? session;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OpenBkool',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: emerald, primary: emerald),
      scaffoldBackgroundColor: const Color(0xFFF4F7F6),
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE0E8E5)),
        ),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF4F7F6)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 56)),
      ),
    ),
    home: OpenBkoolShell(
      session: session,
      advancedBuilder: (session, close) => BleDiagnosticPage(
        antDiagnostics: session.diagnostics,
        antTrainerSearch: session.search,
        training: session.training,
        initialDevice: session.selected.toJson(),
        onDeviceSelected: (d) => session.select(SavedTrainer.fromMap(d)),
        onExit: close,
      ),
    ),
  );
}

class BleDiagnosticPage extends StatefulWidget {
  const BleDiagnosticPage({
    super.key,
    this.antDiagnostics,
    this.antTrainerSearch,
    this.training,
    this.onExit,
    this.initialDevice,
    this.onDeviceSelected,
  });
  final AntDiagnosticsController? antDiagnostics;
  final AntTrainerSearchController? antTrainerSearch, training;
  final VoidCallback? onExit;
  final Map<String, Object?>? initialDevice;
  final Future<void> Function(Map<String, Object?>)? onDeviceSelected;
  @override
  State<BleDiagnosticPage> createState() => _BleDiagnosticPageState();
}

class _BleDiagnosticPageState extends State<BleDiagnosticPage> {
  late final _antDiagnostics =
      widget.antDiagnostics ?? AntDiagnosticsController();
  late final _antTrainerSearch =
      widget.antTrainerSearch ?? AntTrainerSearchController();
  late final _training =
      widget.training ??
      AntTrainerSearchController(channelName: 'openbkool/training');
  static const _permissions = MethodChannel('openbkool/permissions');
  final Map<String, BleObservation> _found = {};
  final List<Map<String, Object?>> _events = [];
  final Map<String, Map<String, Object?>> _discoveries = {};
  final Set<String> _seenThisScan = {};
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _scanningSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  Completer<BluetoothAdapterState>? _adapterReady;
  BluetoothDevice? _device;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  bool _connected = false;
  bool _scanning = false;
  bool _busy = false;

  void _record(String event, String message, {Map<String, Object?>? details}) {
    if (!mounted) return;
    setState(
      () => _events.insert(0, {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'event': event,
        'message': message,
        'details': details ?? <String, Object?>{},
      }),
    );
  }

  void _error(String operation, Object error) {
    _record(
      '${operation}_error',
      'ERROR $operation: $error',
      details: {
        'errorType': error.runtimeType.toString(),
        if (error is PlatformException) 'code': error.code,
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // onScanResults evita recuperar la lista de un escaneo anterior del plugin.
    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      if (!mounted) return;
      for (final result in results) {
        final id = result.device.remoteId.str;
        final previous = _found[id];
        final wasCandidate = previous?.isCandidate ?? false;
        final observation = previous ?? BleObservation(result);
        observation.update(result);
        _found[id] = observation;
        if (_seenThisScan.add(id)) {
          _record(
            'device_seen',
            '${observation.displayName} · $id · ${result.rssi} dBm',
            details: observation.toJson(),
          );
        } else if (!wasCandidate && observation.isCandidate) {
          _record(
            'candidate_hint',
            'Nueva pista de posible Bkool: $id',
            details: observation.toJson(),
          );
        }
      }
      setState(() {});
    }, onError: (Object error) => _error('scan', error));
    _scanningSubscription = FlutterBluePlus.isScanning.listen((value) {
      if (!mounted) return;
      final wasScanning = _scanning;
      setState(() => _scanning = value);
      if (value && !wasScanning) {
        _record('scan_starting', 'Inicio de escaneo BLE sin filtros');
      } else if (!value && wasScanning) {
        _record(
          'scan_stopped',
          'Escaneo finalizado: ${_seenThisScan.length} dispositivos en esta búsqueda',
        );
        if (_seenThisScan.isEmpty) {
          _record(
            'scan_empty',
            'Sin anuncios BLE. Revisa permisos, ubicación, alimentación y otras apps conectadas. Un rodillo solo ANT+ no aparecerá aquí.',
          );
        }
      }
    }, onError: (Object error) => _error('scan_state', error));
  }

  Future<BluetoothAdapterState> _watchAdapter() {
    if (_adapterState != BluetoothAdapterState.unknown) {
      return Future.value(_adapterState);
    }
    if (_adapterReady != null) return _adapterReady!.future;
    _adapterReady = Completer<BluetoothAdapterState>();
    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      setState(() => _adapterState = state);
      if (state != BluetoothAdapterState.unknown &&
          !_adapterReady!.isCompleted) {
        _adapterReady!.complete(state);
      }
      _record('adapter_state', 'Bluetooth: ${state.name}');
      if (state == BluetoothAdapterState.unauthorized) {
        _record(
          'permission_error',
          'Bluetooth sin autorización. Revisa los permisos en Ajustes.',
        );
      }
    }, onError: (Object error) => _error('adapter', error));
    return _adapterReady!.future;
  }

  Future<bool> _requestPermissions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    _record(
      'permission_request',
      'Solicitando dispositivos cercanos y ubicación para escaneo BLE completo',
    );
    try {
      final granted = await _permissions.invokeMethod<bool>(
        'requestScanPermissions',
      );
      if (granted != true) {
        throw StateError('No se concedieron los permisos de escaneo');
      }
      _record('permission_granted', 'Permisos de escaneo concedidos');
      return true;
    } catch (error) {
      _error('permission', error);
      _record(
        'permission_help',
        'Permite dispositivos cercanos y ubicación precisa. Si la denegación es permanente, abre Ajustes > Aplicaciones > OpenBkool > Permisos.',
      );
      return false;
    }
  }

  Future<void> _scan() async {
    if (_busy || _scanning) return;
    setState(() => _busy = true);
    _seenThisScan.clear();
    _record(
      'scan_requested',
      'Búsqueda solicitada: 30 segundos, sin filtros de nombre, UUID, fabricante ni identificador',
    );
    try {
      if (!await _requestPermissions() || !mounted) return;
      if (!await FlutterBluePlus.isSupported) {
        _record('unsupported', 'BLE no disponible en este dispositivo');
        return;
      }
      if (!mounted) return;
      final state = await _watchAdapter().timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (state != BluetoothAdapterState.on) {
        _record(
          'scan_blocked',
          'Bluetooth ${state.name}: activa Bluetooth y vuelve a buscar',
        );
        return;
      }
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 30),
        // Las listas vacías son explícitas para no filtrar candidatos desconocidos.
        withServices: const [],
        withRemoteIds: const [],
        withNames: const [],
        withKeywords: const [],
        withMsd: const [],
        withServiceData: const [],
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: true,
        androidCheckLocationServices: true,
      );
      if (!mounted) {
        await _stopScan();
        return;
      }
      _record(
        'scan_started',
        'Escaneo activo durante 30 segundos; conserva dispositivos sin nombre y anuncios parciales',
      );
    } catch (error) {
      _error('scan', error);
      _record(
        'scan_help',
        'Revisa dispositivos cercanos, ubicación precisa y los servicios de ubicación. Mantén la pantalla encendida; Android puede limitar búsquedas repetidas.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    if (_busy) return;
    setState(() => _busy = true);
    _record('connect_requested', 'Conexión manual: ${device.remoteId.str}');
    try {
      await _stopScan();
      if (!mounted) return;
      if (_device != null) await _device!.disconnect();
      await _connectionSubscription?.cancel();
      if (!mounted) return;
      _device = device;
      _connected = false;
      _connectionSubscription = device.connectionState.listen((state) {
        if (!mounted || _device != device) return;
        final wasConnected = _connected;
        setState(
          () => _connected = state == BluetoothConnectionState.connected,
        );
        _record('connection_state', '${device.remoteId.str}: ${state.name}');
        if (wasConnected && !_connected) {
          _record(
            'disconnected',
            'Desconectado: ${device.remoteId.str}; motivo: ${device.disconnectReason}',
          );
        }
      }, onError: (Object error) => _error('connection', error));
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
        mtu: null,
      );
      if (!mounted) {
        await _safeDisconnect(device);
        return;
      }
      _record('connected', 'Conectado: ${device.remoteId.str}');
      _record(
        'gatt_requested',
        'Enumerando todos los servicios y características GATT',
      );
      // El valor por defecto true suscribiría Services Changed (escribe CCCD).
      final primaryServices = await device.discoverServices(
        subscribeToServicesChanged: false,
      );
      final services = allGattServices(primaryServices);
      if (!mounted) return;
      if (!device.isConnected) {
        throw StateError('Desconexión durante el descubrimiento GATT');
      }
      final gatt = describeGattServices(services);
      setState(
        () => _discoveries[device.remoteId.str] = {
          'deviceId': device.remoteId.str,
          'name':
              _found[device.remoteId.str]?.displayName ?? device.platformName,
          'discoveredAt': DateTime.now().toUtc().toIso8601String(),
          ...gatt,
        },
      );
      _record(
        'gatt_discovered',
        'Servicios encontrados: ${services.length}',
        details: {'deviceId': device.remoteId.str, ...gatt},
      );
      _record(
        'bkool_service',
        gatt['hasBkoolConfigService'] == true
            ? 'SERVICIO PROPIETARIO BKOOL encontrado: ${bkoolConfigService.str128}'
            : 'Servicio propietario Bkool ausente en este descubrimiento: ${bkoolConfigService.str128}',
      );
      for (final service in services) {
        _record('gatt_service', 'SERVICIO ${service.uuid.str128}');
        for (final c in service.characteristics) {
          _record(
            'gatt_characteristic',
            '  CARACTERÍSTICA ${c.uuid.str128}; '
                'read=${c.properties.read}; write=${c.properties.write}; '
                'writeWithoutResponse=${c.properties.writeWithoutResponse}; '
                'notify=${c.properties.notify}; indicate=${c.properties.indicate}',
          );
        }
      }
    } catch (error) {
      _error('connection_gatt', error);
      await _safeDisconnect(device);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _safeDisconnect(BluetoothDevice device) async {
    try {
      await device.disconnect();
    } catch (error) {
      _error('disconnect', error);
    }
  }

  Future<void> _disconnect() async {
    final device = _device;
    if (_busy || device == null) return;
    setState(() => _busy = true);
    _record(
      'disconnect_requested',
      'Desconexión manual: ${device.remoteId.str}',
    );
    try {
      await _safeDisconnect(device);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    try {
      final report = diagnosticReport(
        observations: _found.values,
        discoveries: _discoveries.values,
        events: _events,
        adapterState: _adapterState.name,
        antDiagnostics: _antDiagnostics.snapshot,
        antTrainerSearch: _antTrainerSearch.snapshot,
        antTraining: _training.snapshot,
      );
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(report)),
      );
      _record('exported', 'Diagnóstico JSON copiado al portapapeles');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('JSON copiado: pégalo en un archivo para guardarlo'),
          ),
        );
      }
    } catch (error) {
      _error('export', error);
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (error) {
      _error('stop_scan', error);
    }
  }

  Future<void> _stopManually() async {
    _record('scan_stop_requested', 'Detención manual del escaneo');
    await _stopScan();
  }

  @override
  void dispose() {
    if (widget.training == null) _training.dispose();
    if (widget.antTrainerSearch == null) _antTrainerSearch.dispose();
    if (widget.antDiagnostics == null) _antDiagnostics.dispose();
    _scanSubscription?.cancel();
    _scanningSubscription?.cancel();
    _adapterSubscription?.cancel();
    _connectionSubscription?.cancel();
    unawaited(_stopScan());
    final device = _device;
    if (device != null) unawaited(_safeDisconnect(device));
    super.dispose();
  }

  Widget _deviceTile(BleObservation observation) {
    final id = observation.device.remoteId.str;
    final gatt = _discoveries[id];
    final proprietary = gatt?['hasBkoolConfigService'] == true;
    final candidate = observation.isCandidate || proprietary;
    return Card(
      key: ValueKey('device-$id'),
      color: candidate
          ? Theme.of(context).colorScheme.secondaryContainer
          : null,
      child: ListTile(
        isThreeLine: false,
        leading: Icon(candidate ? Icons.directions_bike : Icons.bluetooth),
        title: Text(observation.displayName),
        subtitle: Text(
          [
            '$id · RSSI ${observation.rssi} dBm',
            if (observation.advertisedName.isNotEmpty)
              'Nombre anunciado: ${observation.advertisedName}',
            if (observation.platformName.isNotEmpty)
              'Nombre del sistema: ${observation.platformName}',
            if (observation.nameMatchesBkool) 'PISTA: nombre contiene BKOOL',
            if (observation.advertisesCyclingPower)
              'PISTA: Cycling Power 0x1818',
            if (observation.advertisesBkoolConfig)
              'PISTA: servicio Bkool anunciado',
            'UUID anunciados (acumulados): ${observation.advertisedServices.isEmpty ? '(ninguno)' : observation.advertisedServices.map((u) => u.str128).join(', ')}',
            if (observation.serviceDataUuids.isNotEmpty)
              'UUID en service data: ${observation.serviceDataUuids.map((u) => u.str128).join(', ')}',
            'Conectable según anuncio: ${observation.connectable ? 'sí' : 'no'}',
            'Última detección: ${observation.lastSeen.toLocal().toIso8601String()}',
            if (gatt != null)
              'Último GATT: servicio propietario Bkool ${proprietary ? 'ENCONTRADO' : 'ausente'}',
          ].join('\n'),
        ),
        trailing: const Icon(Icons.chevron_right),
        // Incluso anuncios sin nombre, pistas o connectable=true son seleccionables.
        onTap: _busy ? null : () => _connect(observation.device),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _found.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnósticos avanzados'),
        leading: widget.onExit == null
            ? null
            : IconButton(
                tooltip: 'Volver al inicio',
                onPressed: widget.onExit,
                icon: const Icon(Icons.arrow_back),
              ),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.directions_bike),
            title: const Text('Entrenamiento'),
            subtitle: Text(
              'Telemetría y control detallados · ${widget.initialDevice?['deviceNumber'] ?? 30064}/${widget.initialDevice?['deviceType'] ?? 112}/${widget.initialDevice?['transmissionType'] ?? 5}',
            ),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => TrainingPage(
                  controller: _training,
                  initialDevice: widget.initialDevice,
                  onDeviceSelected: widget.onDeviceSelected,
                  searchController: _antTrainerSearch,
                  onExport: _export,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Pendientes experimentales'),
            subtitle: const Text(
              'Diagnóstico por nivel · +2 % y +3 % bloqueados',
            ),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ExperimentalSlopesPage(controller: _training),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.radar),
            title: const Text('Buscar rodillos ANT'),
            subtitle: const Text(
              'FE-C y Bkool V1, por turnos y sin páginas de control',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AntTrainerSearchPage(
                  controller: _antTrainerSearch,
                  onExport: _export,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.sensors),
            title: const Text('Diagnóstico ANT+'),
            subtitle: const Text(
              'Comprobar hardware, servicios y acceso a radio ANT',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AntDiagnosticPage(
                  controller: _antDiagnostics,
                  onExport: _export,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Diagnóstico BLE sin filtros. Las pistas BKOOL y 0x1818 no confirman el modelo. '
              'Puedes seleccionar cualquier dispositivo. Solo conexión y enumeración GATT: sin escrituras, notificaciones ni DFU. '
              'Un rodillo que solo anuncie ANT/ANT+ no aparecerá en BLE.',
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Android: permite dispositivos cercanos y ubicación precisa, y activa Bluetooth y ubicación. '
              'Se solicita ubicación para evitar el filtrado de algunas balizas; no se consulta el GPS.',
            ),
          ),
          ListTile(title: Text('Adaptador: ${_adapterState.name}')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: _scanning || _busy ? null : _scan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(
                _scanning ? 'Escaneando… (30 s)' : 'Buscar dispositivos BLE',
              ),
            ),
          ),
          if (_scanning)
            TextButton(
              onPressed: _busy ? null : _stopManually,
              child: const Text('Detener escaneo'),
            ),
          ListTile(
            title: Text(
              _connected
                  ? 'Conectado: ${_device?.remoteId.str}'
                  : 'Sin conexión',
            ),
            trailing: TextButton(
              onPressed: _connected && !_busy ? _disconnect : null,
              child: const Text('Desconectar'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.copy),
              label: const Text('Exportar diagnóstico JSON'),
            ),
          ),
          ListTile(title: Text('Dispositivos detectados: ${results.length}')),
          if (results.isEmpty)
            const ListTile(subtitle: Text('Todavía no hay dispositivos.')),
          ...results.map(_deviceTile),
          const Divider(),
          const ListTile(
            title: Text('Registro de diagnóstico y GATT (sin escrituras)'),
          ),
          ..._events.map(
            (event) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SelectableText(
                '${event['timestamp']} [${event['event']}] ${event['message']}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
