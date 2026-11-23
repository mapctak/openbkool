import 'package:flutter/material.dart';

class SpinningSelector extends StatefulWidget {
  const SpinningSelector({super.key, required this.catalog});
  final Future<List<Map<Object?, Object?>>> catalog;

  @override
  State<SpinningSelector> createState() => _SpinningSelectorState();
}

class _SpinningSelectorState extends State<SpinningSelector> {
  static const durations = [10, 15, 20, 30, 45];
  static const levels = [
    'Muy suave',
    'Suave',
    'Moderado',
    'Intenso',
    'Exigente',
    'Muy exigente',
  ];
  int minutes = 10;
  int level = 1;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Spinning')),
    body: FutureBuilder<List<Map<Object?, Object?>>>(
      future: widget.catalog,
      builder: (context, snapshot) {
        final programs = snapshot.data;
        if (programs == null) {
          return Center(
            child: snapshot.hasError
                ? const Text('No se pudo cargar el catálogo de Spinning.')
                : const CircularProgressIndicator(),
          );
        }
        final program = programs.firstWhere(
          (p) => p['durationMs'] == minutes * 60000 && p['level'] == level,
        );
        final intervals = (program['intervals'] as List).cast<Map>();
        final color = Theme.of(context).colorScheme.primary;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: minutes,
                decoration: const InputDecoration(labelText: 'Duración'),
                items: [
                  for (final m in durations)
                    DropdownMenuItem(value: m, child: Text('$m min')),
                ],
                onChanged: (m) => setState(() => minutes = m!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: level,
                decoration: const InputDecoration(labelText: 'Dificultad'),
                items: [
                  for (var i = 0; i < levels.length; i++)
                    DropdownMenuItem(
                      value: i + 1,
                      child: Text(
                        'Nivel ${i + 1} · ${levels[i]}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => level = value!),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        program['name'] as String,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Pendiente máxima +${(program['maxGrade'] as num).toStringAsFixed(1).replaceAll('.', ',')} %',
                      ),
                      const SizedBox(height: 18),
                      Semantics(
                        label:
                            'Perfil temporal de pendientes de 0 a 8 por ciento',
                        child: SizedBox(
                          width: double.infinity,
                          height: 132,
                          child: CustomPaint(
                            painter: _ProgramProfile(
                              intervals,
                              minutes * 60000,
                              color,
                            ),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [const Text('0 min'), Text('$minutes min')],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Calentamiento físico · Intervalos y recuperaciones · Vuelta a la calma',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, program['id'] as String),
                child: const Text('INICIAR SPINNING'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _ProgramProfile extends CustomPainter {
  const _ProgramProfile(this.intervals, this.duration, this.color);
  final List<Map> intervals;
  final int duration;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = color.withValues(alpha: 0.18),
      );
    }
    final area = Path()..moveTo(0, size.height);
    final line = Path();
    for (var i = 0; i < intervals.length; i++) {
      final interval = intervals[i];
      final left = size.width * (interval['startMs'] as num) / duration;
      final right = size.width * (interval['endMs'] as num) / duration;
      final y = size.height * (1 - (interval['grade'] as num) / 8);
      if (i == 0) {
        line.moveTo(left, y);
      } else {
        line.lineTo(left, y);
      }
      line.lineTo(right, y);
      area
        ..lineTo(left, y)
        ..lineTo(right, y);
    }
    area
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.20));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ProgramProfile oldDelegate) =>
      oldDelegate.intervals != intervals ||
      oldDelegate.duration != duration ||
      oldDelegate.color != color;
}
