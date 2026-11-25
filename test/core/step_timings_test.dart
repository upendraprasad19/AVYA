import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/step_timings.dart';

/// OI-348 Landing 3a (B6): the step timer behind `auth_ensure_timing`.
/// A fake clock (`elapsedMs`) makes the numbers exact.
void main() {
  test('laps record ms since the previous lap, in first-seen order; '
      'a repeated name adds', () {
    var now = 0;
    final t = StepTimings(elapsedMs: () => now);
    now = 120;
    t.lap('open');
    now = 150;
    t.lap('guard');
    now = 200;
    t.lap('open');
    expect(t.laps.keys.toList(), ['open', 'guard']);
    expect(t.laps['open'], 170);
    expect(t.laps['guard'], 30);
    expect(t.totalMs, 200);
  });

  test('summary puts total first', () {
    var now = 0;
    final t = StepTimings(elapsedMs: () => now);
    now = 5;
    t.lap('verify');
    now = 12;
    t.lap('h_lock');
    expect(t.summary(), 'total=12 verify=5 h_lock=7');
  });

  test('a fresh timer has only the total; the real clock moves forward',
      () async {
    final t = StepTimings();
    expect(t.summary(), startsWith('total='));
    expect(t.laps, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    t.lap('wait');
    expect(t.laps['wait'], greaterThanOrEqualTo(15));
  });
}
