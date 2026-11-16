import 'package:flutter_test/flutter_test.dart';
import 'package:openbkool/spinning_program.dart';
import 'package:openbkool/spinning_engine.dart';

void main() {
  test('four immutable programs have exact totals and safe targets', () {
    expect(spinningPrograms.map((p) => p.duration.inMinutes), [15, 20, 25, 30]);
    for (final p in spinningPrograms) {
      expect(p.intervals.first.phase, SpinningPhase.warmup);
      expect(p.intervals.last.phase, SpinningPhase.recovery);
      for (final i in p.intervals) {
        expect(i.duration > Duration.zero, true);
        expect({0.0, 0.5, 1.0}.contains(i.targetPercent), true);
      }
      expect(() => p.intervals.clear(), throwsUnsupportedError);
    }
    expect(
      () => SpinningInterval(SpinningPhase.work, Duration.zero, 1),
      throwsArgumentError,
    );
    expect(
      () => SpinningInterval(SpinningPhase.work, const Duration(minutes: 1), 2),
      throwsArgumentError,
    );
    expect(
      () => SpinningInterval(
        SpinningPhase.work,
        const Duration(minutes: 1),
        0.25,
      ),
      throwsArgumentError,
    );
  });
  test(
    'every exact boundary selects next interval and end has no active target',
    () {
      for (final p in spinningPrograms) {
        var now = Duration.zero;
        final e = SpinningEngine(p, now: () => now);
        e.start();
        var boundary = Duration.zero;
        for (var i = 0; i < p.intervals.length; i++) {
          expect(e.intervalIndex, i);
          expect(e.current, p.intervals[i]);
          expect(
            e.next,
            i + 1 < p.intervals.length ? p.intervals[i + 1] : null,
          );
          boundary += p.intervals[i].duration;
          now = boundary - const Duration(milliseconds: 1);
          e.tick();
          expect(e.intervalIndex, i);
          now = boundary;
          e.tick();
        }
        expect(e.state, SpinningState.completed);
        expect(e.elapsed, p.duration);
        expect(e.remaining, Duration.zero);
        expect(e.current, isNull);
        expect(e.next, isNull);
      }
    },
  );
  test('pause and resume exclude paused time and repeated calls do not extend timeline', () {
    var now = Duration.zero;
    final e = SpinningEngine(spinningPrograms.first, now: () => now);
    now = const Duration(hours: 1);
    e.tick();
    expect(e.elapsed, Duration.zero);
    e.start();
    now += const Duration(seconds: 20);
    e.pause();
    expect(e.elapsed, const Duration(seconds: 20));
    expect(e.state, SpinningState.paused);
    now += const Duration(hours: 5);
    e.pause();
    e.tick();
    expect(e.elapsed, const Duration(seconds: 20));
    e.resume();
    e.resume();
    now += const Duration(seconds: 10);
    e.tick();
    expect(e.elapsed, const Duration(seconds: 30));
    e.finish();
    now += const Duration(hours: 1);
    e.resume();
    e.start();
    e.tick();
    expect(e.state, SpinningState.finished);
    expect(e.elapsed, const Duration(seconds: 30));
    expect(e.current, isNull);
  });
  test('a delayed tick catches up across intervals and clamps completion', () {
    var now = Duration.zero;
    final e = SpinningEngine(spinningPrograms.first, now: () => now);
    e.start();
    now = const Duration(minutes: 10);
    e.tick();
    expect(e.intervalIndex, 3);
    expect(e.intervalRemaining, const Duration(minutes: 3));
    now = const Duration(days: 1);
    e.tick();
    expect(e.state, SpinningState.completed);
    expect(e.elapsed, const Duration(minutes: 15));
    e.resume();
    expect(e.current, isNull);
  });
}
