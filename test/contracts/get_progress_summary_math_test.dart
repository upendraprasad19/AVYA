// APK Test #12.6 / Obs 8 — pin the math fixes in `getProgressSummary`
// Edge Function tool.
//
// History: founder asked AI coach "show my progress this month" and got
// "Total volume lifted: 79,713 kg" + "Workouts: 2 of 28 planned" — both
// inflated. Two bugs:
//   1. Volume formula was `w * reps * sets` but `reps` is CUMULATIVE
//      across sets per docs/architecture/ai.md — multiplying by sets again
//      triple-counted (founder's actual ~$23k inflated to ~$80k).
//   2. Planned-workouts filter excluded only `paused` and `skipped`, not
//      `rest` — rest days counted as "planned workouts."
//
// These are source-grep tests on the Edge Function TS file. Deno tests
// for the handler require a seeded test DB and are deferred.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    final f = File(
      'supabase/functions/_shared/tools/progress/getProgressSummary.ts',
    );
    expect(f.existsSync(), isTrue, reason: 'tool source must exist');
    source = f.readAsStringSync();
  });

  group('getProgressSummary math fixes — Test #12.6', () {
    test('volume formula does NOT multiply by set_number a third time', () {
      // The bug: `totalVolume += w * reps * sets;`
      // The fix: `totalVolume += w * reps;`
      expect(source, isNot(contains('totalVolume += w * reps * sets')),
          reason:
              'Volume must not multiply by set_number — `reps` is already '
              'CUMULATIVE per docs/architecture/ai.md cloud contract. Was triple-counting.');
      expect(source, contains('totalVolume += w * reps'),
          reason: 'Volume formula must use weight × cumulative_reps.');
    });

    test('planned-workouts filter excludes rest days', () {
      // The bug: filter only excluded "paused" and "skipped".
      // The fix: also exclude "rest" (and null defensively).
      expect(source, contains('s.status !== "rest"'),
          reason: 'Rest days must NOT count as planned workouts.');
      expect(source, contains('s.status !== "paused"'));
      expect(source, contains('s.status !== "skipped"'));
    });
  });
}
