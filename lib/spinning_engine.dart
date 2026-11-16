import 'spinning_program.dart';

enum SpinningState { ready, running, paused, completed, finished }

/// Clock-driven interval engine. Outputs targets; never invokes a resistance sink.
/// A future integration must be a separate, explicitly authorized adapter.
class SpinningEngine {
  SpinningEngine(this.program, {required this.now});
  final SpinningProgram program;
  final Duration Function() now;
  SpinningState _state = SpinningState.ready;
  Duration _elapsed = Duration.zero;
  Duration? _anchor;
  SpinningState get state => _state;
  Duration get elapsed => _elapsed;
  Duration get remaining => program.duration - _elapsed;
  bool get terminal =>
      _state == SpinningState.completed || _state == SpinningState.finished;

  void start() {
    if (_state != SpinningState.ready) return;
    _anchor = now();
    _state = SpinningState.running;
  }

  void tick() {
    if (_state != SpinningState.running) return;
    final current = now();
    final delta = current - _anchor!;
    if (delta.isNegative) throw StateError('El reloj debe ser monótono');
    _elapsed += delta;
    _anchor = current;
    if (_elapsed >= program.duration) {
      _elapsed = program.duration;
      _anchor = null;
      _state = SpinningState.completed;
    }
  }

  void pause() {
    tick();
    if (_state != SpinningState.running) return;
    _anchor = null;
    _state = SpinningState.paused;
  }

  void resume() {
    if (_state != SpinningState.paused) return;
    _anchor = now();
    _state = SpinningState.running;
  }

  void finish() {
    tick();
    if (terminal) return;
    _anchor = null;
    _state = SpinningState.finished;
  }

  int? get intervalIndex {
    if (terminal) return null;
    var end = Duration.zero;
    for (var i = 0; i < program.intervals.length; i++) {
      end += program.intervals[i].duration;
      if (_elapsed < end) return i;
    }
    return null;
  }

  SpinningInterval? get current =>
      intervalIndex == null ? null : program.intervals[intervalIndex!];
  SpinningInterval? get next =>
      intervalIndex != null && intervalIndex! + 1 < program.intervals.length
      ? program.intervals[intervalIndex! + 1]
      : null;
  Duration get intervalRemaining {
    final index = intervalIndex;
    if (index == null) return Duration.zero;
    return program.intervals
            .take(index + 1)
            .fold(Duration.zero, (sum, i) => sum + i.duration) -
        _elapsed;
  }
}
