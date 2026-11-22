import 'dart:math' as math;

import 'package:flutter/material.dart';

const dashboardInk = Color(0xff101518);
const dashboardPanel = Color(0xff171e23);
const dashboardMuted = Color(0xffa6b5bc);
const dashboardAccent = Color(0xff67e8c0);

String dashboardDecimal(num value, int digits) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');

String workoutTime(num milliseconds) {
  final seconds = milliseconds.toInt() ~/ 1000;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(seconds ~/ 3600)}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
}

class WorkoutDial extends StatelessWidget {
  const WorkoutDial({
    super.key,
    required this.label,
    required this.unit,
    required this.value,
    required this.maximum,
    required this.accent,
    this.decimals = 0,
  });

  final String label, unit;
  final num? value;
  final double maximum;
  final Color accent;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final reading = value;
    final valid = reading != null && reading.isFinite && reading >= 0;
    final text = valid ? dashboardDecimal(reading, decimals) : '—';
    return Semantics(
      label: label,
      value: valid ? '$text $unit' : 'Sin datos',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: dashboardMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 5),
            AspectRatio(
              aspectRatio: 1.12,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(
                          end: valid
                              ? (reading / maximum).clamp(0.0, 1.0)
                              : 0.0,
                        ),
                        duration: valid
                            ? const Duration(milliseconds: 260)
                            : Duration.zero,
                        curve: Curves.easeOutCubic,
                        builder: (context, position, _) => CustomPaint(
                          painter: _DialPainter(
                            accent,
                            valid ? position : null,
                            maximum.toInt(),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: const Alignment(0, .44),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            text,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              height: 1,
                              fontSize: (constraints.maxWidth * .23).clamp(
                                18.0,
                                47.0,
                              ),
                            ),
                          ),
                          Text(
                            unit,
                            style: const TextStyle(
                              color: dashboardMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter(this.accent, this.position, this.maximum);
  final Color accent;
  final double? position;
  final int maximum;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .48);
    final radius = math.min(size.width, size.height) * .43;
    const start = math.pi * .81;
    const sweep = math.pi * 1.38;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      stroke..color = const Color(0xff38444b),
    );
    if (position case final double fraction) {
      canvas.drawArc(
        rect,
        start,
        sweep * fraction,
        false,
        stroke..color = accent,
      );
    }
    Offset polar(double angle, double length) =>
        center + Offset(math.cos(angle), math.sin(angle)) * length;
    for (var i = 0; i <= 20; i++) {
      final angle = start + sweep * i / 20;
      canvas.drawLine(
        polar(angle, radius - (i % 5 == 0 ? 9 : 6)),
        polar(angle, radius - 13),
        Paint()
          ..color = dashboardMuted.withValues(alpha: i % 5 == 0 ? .8 : .42),
      );
    }
    if (position case final double fraction) {
      final angle = start + sweep * fraction;
      canvas.drawLine(
        center,
        polar(angle, radius - 16),
        Paint()
          ..color = accent
          ..strokeWidth = 2.7
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(center, 3.7, Paint()..color = accent);
    }
    _caption(canvas, '0', Offset(size.width * .07, size.height * .8));
    _caption(
      canvas,
      '$maximum',
      Offset(size.width * .93, size.height * .8),
      right: true,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      position != old.position ||
      accent != old.accent ||
      maximum != old.maximum;
}

void _caption(
  Canvas canvas,
  String text,
  Offset position, {
  bool right = false,
}) {
  final label = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        fontSize: 9,
        fontFamily: 'Roboto',
        color: dashboardMuted,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  label.paint(canvas, position.translate(right ? -label.width : 0, 0));
  label.dispose();
}

class ElevationChart extends StatelessWidget {
  const ElevationChart({
    super.key,
    required this.points,
    required this.distanceMeters,
    required this.height,
  });
  final List<dynamic> points;
  final double distanceMeters, height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Perfil de elevación virtual, distancia en kilómetros y elevación en metros',
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _ElevationPainter(points, distanceMeters),
        size: Size.fromHeight(height),
      ),
    ),
  );
}

class _ElevationPainter extends CustomPainter {
  const _ElevationPainter(this.points, this.distanceMeters);
  final List<dynamic> points;
  final double distanceMeters;

  double _step(double span) {
    final power = math.pow(10, (math.log(span) / math.ln10).floor()).toDouble();
    final fraction = span / power;
    return power *
        (fraction <= 1
            ? 1
            : fraction <= 2
            ? 2
            : fraction <= 5
            ? 5
            : 10);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(37, 13, size.width - 16, size.height - 24);
    if (area.isEmpty) return;
    final series = points
        .whereType<List>()
        .where(
          (point) =>
              point.length == 3 &&
              point.every((value) => value is num && value.isFinite),
        )
        .toList();
    var minY = 0.0;
    var maxY = 0.0;
    for (final point in series) {
      final y = (point[1] as num).toDouble();
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    final padding = math.max(2.0, (maxY - minY) * .12);
    final yStep = _step(math.max(1, (maxY - minY + padding * 2) / 3));
    final bottom = ((minY - padding) / yStep).floor() * yStep;
    final top = ((maxY + padding) / yStep).ceil() * yStep;
    final xStep = _step(math.max(.1, distanceMeters * 1.06 / 4000));
    final right = math.max(
      xStep * 2,
      (distanceMeters * 1.06 / 1000 / xStep).ceil() * xStep,
    );
    double x(double km) => area.left + area.width * km / right;
    double y(double meters) =>
        area.bottom - area.height * (meters - bottom) / (top - bottom);
    final grid = Paint()
      ..color = const Color(0xff304047)
      ..strokeWidth = .7;
    for (var tick = bottom; tick <= top + yStep / 100; tick += yStep) {
      canvas.drawLine(
        Offset(area.left, y(tick)),
        Offset(area.right, y(tick)),
        grid,
      );
      _caption(
        canvas,
        '${tick.round()} m',
        Offset(area.left - 5, y(tick) - 5),
        right: true,
      );
    }
    for (var tick = 0.0; tick <= right + xStep / 100; tick += xStep) {
      canvas.drawLine(
        Offset(x(tick), area.top),
        Offset(x(tick), area.bottom),
        grid,
      );
      _caption(
        canvas,
        '${dashboardDecimal(tick, xStep < 1 ? 1 : 0)} km',
        Offset(x(tick), area.bottom + 6),
        right: tick > right - xStep / 2,
      );
    }
    final line = Path();
    final fill = Path();
    num? segment;
    double? lastX;
    double? lastY;
    for (final point in series) {
      final px = x((point[0] as num) / 1000);
      final py = y((point[1] as num).toDouble());
      final nextSegment = point[2] as num;
      if (nextSegment != segment) {
        if (lastX != null) {
          fill.lineTo(lastX, area.bottom);
          fill.close();
        }
        line.moveTo(px, py);
        fill.moveTo(px, area.bottom);
        fill.lineTo(px, py);
        segment = nextSegment;
      } else {
        line.lineTo(px, py);
        fill.lineTo(px, py);
      }
      lastX = px;
      lastY = py;
    }
    if (lastX != null) {
      fill.lineTo(lastX, area.bottom);
      fill.close();
    }
    canvas.save();
    canvas.clipRect(area.inflate(1));
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x7767e8c0), Color(0x0867e8c0)],
        ).createShader(area),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = dashboardAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    if (lastX != null && lastY != null) {
      canvas.drawCircle(
        Offset(lastX, lastY),
        3,
        Paint()..color = dashboardAccent,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter old) =>
      distanceMeters != old.distanceMeters ||
      points.length != old.points.length;
}
