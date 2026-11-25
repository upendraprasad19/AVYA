import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/step_timings.dart';

/// OI-348 Landing 3a (B6): `runTimed` wraps `_ensureLocalUser` and sends the
/// one `auth_ensure_timing` line. It must report exactly once whatever the
/// body does, and reporting must never change what the caller sees.
void main() {
  test('success: one line, outcome=ok, result returned', () async {
    final lines = <String>[];
    final t = StepTimings();
    final r = await runTimed<int>(t, () async {
      t.lap('open');
      return 7;
    }, lines.add);
    expect(r, 7);
    expect(lines, hasLength(1));
    expect(lines.single, startsWith('outcome=ok total='));
    expect(lines.single, contains(' open='));
  });

  test('failure: one line, outcome=threw, the SAME error rethrown', () async {
    final lines = <String>[];
    final err = StateError('guard');
    final t = StepTimings();
    await expectLater(
      runTimed<void>(t, () async {
        t.lap('open');
        throw err;
      }, lines.add),
      throwsA(same(err)),
    );
    expect(lines, hasLength(1));
    expect(lines.single, startsWith('outcome=threw total='));
  });

  test('a throwing log never masks the result or the error', () async {
    void badLog(String _) => throw Exception('telemetry down');
    expect(await runTimed<int>(StepTimings(), () async => 3, badLog), 3);
    final err = ArgumentError('body');
    await expectLater(
      runTimed<void>(StepTimings(), () async => throw err, badLog),
      throwsA(same(err)),
    );
  });

  test('the line is sent after the body finished (finally), not before',
      () async {
    final events = <String>[];
    await runTimed<void>(StepTimings(), () async {
      events.add('body');
    }, (_) => events.add('log'));
    expect(events, ['body', 'log']);
  });
}
