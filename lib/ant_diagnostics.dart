import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AntDiagnosticsController extends ChangeNotifier {
  static const channel = MethodChannel('openbkool/ant');
  bool busy = false;
  bool _disposed = false;
  Map<String, Object?> snapshot = {'status': 'not_checked'};

  Future<void> inspect() async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        snapshot = {
          'status': 'unsupported_platform',
          'checkedAt': DateTime.now().toUtc().toIso8601String(),
          'errors': [
            {
              'stage': 'platform',
              'message': 'Esta consulta ANT solo está disponible en Android.',
            },
          ],
        };
      } else {
        final result = await channel.invokeMapMethod<String, dynamic>(
          'inspectCapabilities',
        );
        if (result == null) {
          throw StateError('El diagnóstico ANT devolvió un resultado vacío');
        }
        snapshot = Map<String, Object?>.from(result);
      }
    } catch (error) {
      snapshot = {
        'status': 'channel_error',
        'checkedAt': DateTime.now().toUtc().toIso8601String(),
        'errors': [
          {
            'stage': 'method_channel',
            'message': error.toString(),
            if (error is PlatformException) 'code': error.code,
          },
        ],
      };
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AntDiagnosticPage extends StatelessWidget {
  const AntDiagnosticPage({
    super.key,
    required this.controller,
    required this.onExport,
  });
  final AntDiagnosticsController controller;
  final Future<void> Function() onExport;

  String _flag(Object? value) => switch (value) {
    true => 'Sí',
    false => 'No',
    _ => 'No comprobado',
  };
  Map<dynamic, dynamic> _section(Map<String, Object?> report, String key) =>
      report[key] is Map ? report[key] as Map : const {};
  String _package(Map<dynamic, dynamic> package) {
    if (package['installed'] == false) return 'No instalado';
    if (package['installed'] != true) return 'No comprobado';
    return 'Instalado · ${package['enabled'] == true ? 'habilitado' : 'deshabilitado'}'
        ' · versión ${package['versionName'] ?? 'desconocida'}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Diagnóstico ANT+')),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final report = controller.snapshot;
        final hardware = _section(report, 'builtInHardware');
        final provider = _section(report, 'channelProvider');
        final radio = _section(report, 'radio');
        final android = _section(report, 'android');
        final errors = report['errors'] as List? ?? const [];
        final adapters = report['adapters'] as List? ?? const [];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Servicios instalados y radio disponible son comprobaciones diferentes. '
              'Esta pantalla solo consulta capacidades y reserva/libera temporalmente un canal sin asignar ni abrir. '
              'No busca rodillos ni configura redes o firmware.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: controller.busy ? null : controller.inspect,
              icon: const Icon(Icons.sensors),
              label: Text(
                controller.busy
                    ? 'Consultando ANT…'
                    : 'Comprobar capacidades ANT',
              ),
            ),
            if (controller.busy) const LinearProgressIndicator(),
            ListTile(
              title: const Text('Resultado de la consulta'),
              subtitle: Text(switch (report['status']) {
                'not_checked' => 'Todavía no se ha consultado',
                'completed' => 'Consulta completada',
                'partial' => 'Consulta parcial: revisa los errores',
                'timeout' =>
                  'Tiempo de espera agotado; disponibilidad no confirmada',
                'radio_service_unavailable' =>
                  'ANT Radio Service no disponible',
                'unsupported_platform' => 'Consulta disponible solo en Android',
                'channel_error' => 'Error del canal de diagnóstico',
                _ => 'Consulta incompleta: ${report['status']}',
              }),
            ),
            if (controller.busy && report['checkedAt'] != null)
              const Text(
                'Los datos mostrados pertenecen a la consulta anterior hasta recibir la nueva respuesta.',
              ),
            if (report['checkedAt'] != null)
              Text('Fecha: ${report['checkedAt']}'),
            if (android.isNotEmpty)
              ListTile(
                title: const Text('Android del teléfono'),
                subtitle: Text(
                  '${android['manufacturer']} ${android['model']} · Android ${android['release']} '
                  '(API ${android['sdkInt']}) · target ${android['targetSdk']}\nANTLib ${report['antLibVersion']}',
                ),
              ),
            if (android['newerThanSdkDocumented'] == true)
              const Text(
                'El SDK ANT documenta soporte hasta Android 13 (API 33). '
                'Esta versión de Android es posterior: el resultado de enlace y reserva es la comprobación efectiva; no se garantiza compatibilidad del servicio.',
              ),
            ListTile(
              title: const Text('Hardware ANT integrado'),
              subtitle: Text(
                'Declarado por Android: ${_flag(hardware['declared'])}\n'
                'Adaptador integrado observado por ANT Radio Service: ${_flag(hardware['observed'])}',
              ),
            ),
            ListTile(
              title: const Text('ANT Radio Service'),
              subtitle: Text(
                '${_package(_section(report, 'radioService'))}\n'
                'Enlace operativo confirmado: ${_flag(report['radioServiceBound'])}',
              ),
            ),
            ListTile(
              title: const Text('ANT+ Plugins Service'),
              subtitle: Text(_package(_section(report, 'pluginsService'))),
            ),
            ListTile(
              title: const Text('ANT USB Service (opcional)'),
              subtitle: Text(_package(_section(report, 'usbService'))),
            ),
            ListTile(
              title: const Text('Proveedor de canales ANT'),
              subtitle: Text(
                'Responde por IPC: ${_flag(provider['responsive'])}\n'
                'Canales libres: ${provider['availableChannels'] ?? 'No comprobado'}\n'
                'Operativo con canales libres: ${_flag(provider['operational'])}\n'
                'Interfaz legacy ocupada: ${_flag(provider['legacyInterfaceInUse'])}',
              ),
            ),
            ListTile(
              title: const Text('Acceso a una radio ANT'),
              subtitle: Text(
                'Reserva de canal sin abrir obtenida: ${_flag(radio['reservationAcquired'])}\n'
                'Radio accesible en esta consulta: ${_flag(radio['accessible'])}\n'
                'Reserva liberada: ${_flag(radio['released'])}',
              ),
            ),
            if (radio['status'] == 'no_free_channels')
              const Text(
                'No hay canales libres. Puede faltar una radio operativa o estar ocupada/deshabilitada; esto no demuestra ausencia de hardware.',
              ),
            if (adapters.isEmpty)
              const Text(
                'No se han observado adaptadores. Si hubo errores, timeout o un servicio antiguo, la presencia de hardware queda sin confirmar.',
              ),
            for (final adapter in adapters)
              ListTile(
                title: Text(
                  'Adaptador ${adapter['builtIn'] == true ? 'integrado' : 'externo'}',
                ),
                subtitle: Text('${adapter['id']} · ${adapter['version']}'),
              ),
            if (errors.isNotEmpty)
              const ListTile(
                title: Text('Errores y limitaciones de la consulta'),
              ),
            for (final error in errors)
              SelectableText(
                '[${error['stage']}] ${error['reason'] ?? error['code'] ?? error['type'] ?? ''} ${error['message']}',
              ),
            const SizedBox(height: 16),
            const Text(
              'Instalar los servicios no añade una radio ANT al teléfono. Un adaptador USB requiere hardware compatible y su servicio. '
              'No se retiran canales a otras aplicaciones; cero canales libres no equivale a cero radios.',
            ),
            OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.copy),
              label: const Text('Exportar diagnóstico JSON'),
            ),
          ],
        );
      },
    ),
  );
}
