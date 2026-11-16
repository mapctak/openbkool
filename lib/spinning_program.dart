/// Guided targets only. This module has no Flutter, channel or ANT dependency.
enum SpinningPhase {
  warmup('Calentamiento'),
  work('Trabajo'),
  recovery('Recuperación');

  const SpinningPhase(this.label);
  final String label;
}

class SpinningInterval {
  SpinningInterval(this.phase, this.duration, this.targetPercent) {
    if (duration <= Duration.zero || !{0.0, 0.5, 1.0}.contains(targetPercent)) {
      throw ArgumentError(
        'Duración positiva y objetivo 0 / 0,5 / 1 % requeridos',
      );
    }
  }
  final SpinningPhase phase;
  final Duration duration;
  final double targetPercent;
}

class SpinningProgram {
  SpinningProgram(this.id, this.name, Iterable<SpinningInterval> intervals)
    : intervals = List.unmodifiable(intervals) {
    if (this.intervals.isEmpty) throw ArgumentError('Programa sin intervalos');
  }
  final String id, name;
  final List<SpinningInterval> intervals;
  Duration get duration =>
      intervals.fold(Duration.zero, (sum, i) => sum + i.duration);
}

SpinningInterval _phase(SpinningPhase phase, int minutes, double target) =>
    SpinningInterval(phase, Duration(minutes: minutes), target);
final spinningPrograms = List<SpinningProgram>.unmodifiable([
  SpinningProgram('gentle', 'Spinning suave', [
    _phase(SpinningPhase.warmup, 3, 0),
    _phase(SpinningPhase.work, 4, 0.5),
    _phase(SpinningPhase.recovery, 2, 0),
    _phase(SpinningPhase.work, 4, 0.5),
    _phase(SpinningPhase.recovery, 2, 0),
  ]),
  SpinningProgram('progressive', 'Spinning progresivo', [
    _phase(SpinningPhase.warmup, 4, 0),
    _phase(SpinningPhase.work, 4, 0.5),
    _phase(SpinningPhase.work, 4, 1),
    _phase(SpinningPhase.recovery, 2, 0.5),
    _phase(SpinningPhase.work, 4, 1),
    _phase(SpinningPhase.recovery, 2, 0),
  ]),
  SpinningProgram('intervals', 'Spinning por intervalos', [
    _phase(SpinningPhase.warmup, 5, 0),
    for (var i = 0; i < 5; i++) ...[
      _phase(SpinningPhase.work, 2, 1),
      _phase(SpinningPhase.recovery, 2, 0),
    ],
  ]),
  SpinningProgram('endurance', 'Spinning de resistencia', [
    _phase(SpinningPhase.warmup, 5, 0),
    _phase(SpinningPhase.work, 8, 0.5),
    _phase(SpinningPhase.recovery, 2, 0),
    _phase(SpinningPhase.work, 10, 1),
    _phase(SpinningPhase.recovery, 5, 0),
  ]),
]);
