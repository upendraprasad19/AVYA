// Tests for scripts/schedule_row_builder_gate_lib.dart — the pure half of
// scripts/check_single_schedule_row_builder.dart (OI-166 Unit 1).
//
// MUTATION-PROVEN per CLAUDE.md §4.4 rule 24. Each protective leg has a test
// that reddens when that leg is neutered; the evidence is recorded in
// docs/audit/gate_test_ledger.yaml. A valid mutation leaves the code COMPILING
// and semantically wrong — a compile error is red for the wrong reason.
//
// No subprocess, no network, no disk: this is a pure-function test, so it needs
// no @Timeout annotation (that class is "bounded by work this process does not
// control", per CLAUDE.md §4.9).

import 'package:test/test.dart';

import '../../scripts/schedule_row_builder_gate_lib.dart';

/// A minimal file body that looks like a schedule-row constructor.
const _rowSource = '''
void write() {
  box.put('schedule_\$key', {
    'date': dateKey,
    'week': 1,
    'day_of_week': dayOfWeek,
    'week_character': weekPlan.weekCharacter,
    'status': 'planned',
  });
}
''';

void main() {
  group('constructsScheduleRow', () {
    test('detects a row carrying BOTH literals', () {
      expect(constructsScheduleRow(_rowSource), isTrue);
    });

    // MUTATION LEG 1 — the two-key AND.
    // Neuter: change `&&` to `||` in constructsScheduleRow. Both of these
    // redden, because each file carries exactly one of the two keys.
    test('a file with only day_of_week is NOT a row constructor', () {
      const src = "final m = {'day_of_week': d.weekday - 1};";
      expect(constructsScheduleRow(src), isFalse);
    });

    test('a file with only week_character is NOT a row constructor', () {
      // ⚠ Must use the MAP-KEY form. An earlier version of this test used
      // `row['week_character'] = 'working'` (the index form), which does not
      // contain the literal `'week_character':` at all — so it stayed green
      // under the `&&`→`||` mutation and was not exercising that arm. Found by
      // running the mutation, not by reading the test.
      const src = "final m = {'week_character': 'working'};";
      expect(constructsScheduleRow(src), isFalse);
    });

    test('the deload evaluator MUTATING a row is not a constructor', () {
      // The real shape at deload_evaluator.dart:223 — index assignment, not a
      // map literal. It must never be reported, or the gate fires on the one
      // file that legitimately rewrites an existing row's character.
      //
      // ⚠ WHY THIS PASSES CHANGED on 2026-09-08 and the old comment here was
      // then WRONG. Before the widening it passed because index assignment was
      // invisible to the matcher. It is now VISIBLE, and what saves this
      // fixture is the two-key AND: it never mentions `day_of_week` at all.
      // Stated explicitly because a comment that explains a pass by the wrong
      // mechanism is worse than none — the next person to widen the matcher
      // would read "index assignment is never reported" and believe it.
      const src = "newRow['week_character'] = 'working';";
      expect(constructsScheduleRow(src), isFalse);
    });

    test('...and the MIRROR: add day_of_week and that same shape IS reported',
        () {
      // The other half of the test above. If this ever goes green while the one
      // above also passes, the two-key AND has stopped doing any work.
      const src = "newRow['week_character'] = 'working';\n"
          "newRow['day_of_week'] = 3;";
      expect(constructsScheduleRow(src), isTrue);
    });

    // ── B-pass finding 2 (2026-09-08) — the index-assignment escape ──
    // A reviewer defeated the first version of this gate on the first attempt
    // with the fixture below. These pin the widening.
    test('BOTH keys by index assignment is a row constructor', () {
      const src = '''
final row = <String, dynamic>{};
row['week_character'] = 'baseline';
row['day_of_week'] = d.weekday - 1;
''';
      expect(constructsScheduleRow(src), isTrue,
          reason: 'this exact shape escaped the gate before 2026-09-08');
    });

    test('MIXED forms — literal key for one, index assignment for the other',
        () {
      // Neither the old literal-only matcher nor a hypothetical index-only one
      // would catch this; it needs the per-key OR.
      const src = '''
final row = {'week_character': 'baseline'};
row['day_of_week'] = 2;
''';
      expect(constructsScheduleRow(src), isTrue);
    });

    test('double-quoted keys are matched too', () {
      const src = 'final m = {"day_of_week": 0, "week_character": "baseline"};';
      expect(constructsScheduleRow(src), isTrue);
    });

    test('a READ of both keys is not a constructor', () {
      // The mirror of the assignment tests: `==` and a bare read must not trip
      // it, or every reader in train_provider becomes a violation.
      const src = '''
final a = row['week_character'];
if (row['day_of_week'] == 3) {}
''';
      expect(constructsScheduleRow(src), isFalse);
    });

    test('KNOWN RESIDUAL: named-constant keys still escape — verified, not '
        'assumed', () {
      // Documented in the library header. A source grep cannot close this, and
      // tightening the pattern only moves the boundary. Unit 2's shared builder
      // is the real fix; this gate is the §4.11 detector that precedes it.
      //
      // Pinned as a TEST so the limit is executable rather than prose. If
      // someone genuinely closes this, THIS test reddens and tells them to
      // delete it and update the header — that is the intended signal, not a
      // regression.
      const src = '''
const _kWeekChar = 'week_character';
const _kDow = 'day_of_week';
final row = <String, dynamic>{};
row[_kWeekChar] = 'baseline';
row[_kDow] = 1;
''';
      expect(constructsScheduleRow(src), isFalse,
          reason: 'if this reddens the residual is closed — update the header');
    });

    // MUTATION LEG 2 — comment stripping.
    // Neuter: make stripDartComments return its input unchanged. Both of these
    // redden. This matters in practice: these files document each other, and
    // several quote the very keys the heuristic looks for.
    test('a COMMENTED-OUT row is not counted', () {
      const src = '''
// box.put('schedule_x', {
//   'day_of_week': 0,
//   'week_character': 'baseline',
// });
void nothing() {}
''';
      expect(constructsScheduleRow(src), isFalse);
    });

    test('a doc-comment quoting both keys is not counted', () {
      // ⚠ The quoted keys carry their COLONS. Without them this fixture does
      // not contain the literal the matcher keys on, so it stayed green under
      // the comment-stripping mutation and proved nothing — the same flaw as
      // the week_character fixture above, found the same way.
      const src = '''
/// Mirrors the writer, which stamps 'day_of_week': and 'week_character': on
/// every row. Keep these in sync.
void documented() {}
''';
      expect(constructsScheduleRow(src), isFalse);
    });

    test('a // inside a string literal does not eat the rest of the file', () {
      const src = '''
final url = 'https://example.com/x';
final m = {'day_of_week': 0, 'week_character': 'baseline'};
''';
      expect(constructsScheduleRow(src), isTrue);
    });
  });

  group('scheduleRowViolations', () {
    // THE RED PATH — the gate detecting an unlisted constructor.
    test('reports an unlisted file that constructs a schedule row', () {
      final violations = scheduleRowViolations({
        'lib/features/train/services/rogue_planner.dart': _rowSource,
      });
      expect(violations, hasLength(1));
      expect(violations.single, 'lib/features/train/services/rogue_planner.dart');
    });

    // MUTATION LEG 3 — the allowlist check.
    // Neuter: delete the `scheduleRowAllowlist.containsKey(path)` continue.
    // This reddens (all four allowlisted files become violations).
    test('allowlisted files are not reported', () {
      final violations = scheduleRowViolations({
        for (final p in scheduleRowAllowlist.keys) p: _rowSource,
      });
      expect(violations, isEmpty);
    });

    test('normalises backslash paths so Windows matches the allowlist', () {
      final violations = scheduleRowViolations({
        r'lib\features\ai_coach\services\hotel_workout_planner.dart': _rowSource,
      });
      expect(violations, isEmpty);
    });

    test('output is sorted, so the report is stable across platforms', () {
      final violations = scheduleRowViolations({
        'lib/z_second.dart': _rowSource,
        'lib/a_first.dart': _rowSource,
      });
      expect(violations, ['lib/a_first.dart', 'lib/z_second.dart']);
    });

    test('a file that constructs no row is never reported', () {
      final violations = scheduleRowViolations({
        'lib/features/train/providers/train_provider.dart':
            "final dayOfWeek = (row['day_of_week'] as int?) ?? 0;",
      });
      expect(violations, isEmpty);
    });
  });

  group('scheduleRowAllowlist contents are PINNED', () {
    // Review round 5, P2-12: without this, a fifth implementation can be
    // allowlisted instead of using the shared builder and the gate becomes a
    // rubber stamp. Changing the allowlist must mean editing an assertion that
    // states why — in a diff a reviewer sees.
    test('exactly the four expected entries, with their exemption kind', () {
      expect(scheduleRowAllowlist, {
        'lib/core/services/schedule_row_builder.dart':
            ScheduleRowExemption.permanent,
        'lib/features/ai_coach/services/hotel_workout_planner.dart':
            ScheduleRowExemption.permanent,
        'lib/core/services/workout_schedule_read_service.dart':
            ScheduleRowExemption.pendingUnit2,
        'lib/features/ai_coach/services/regenerate_plan_planner.dart':
            ScheduleRowExemption.pendingUnit2,
      });
    });

    test('the two pendingUnit2 entries are the de-duplication\'s own todo list',
        () {
      final pending = scheduleRowAllowlist.entries
          .where((e) => e.value == ScheduleRowExemption.pendingUnit2)
          .map((e) => e.key)
          .toList()
        ..sort();
      // When OI-166 Unit 2 lands, these two are deleted and
      // check_single_schedule_row_builder.dart's `_hardFail` flips to true.
      expect(pending, [
        'lib/core/services/workout_schedule_read_service.dart',
        'lib/features/ai_coach/services/regenerate_plan_planner.dart',
      ]);
    });
  });

  group('staleAllowlistEntries', () {
    test('flags an allowlisted file that no longer constructs a row', () {
      final stale = staleAllowlistEntries({
        'lib/core/services/workout_schedule_read_service.dart':
            'class WorkoutScheduleReadService {}',
      });
      expect(stale, ['lib/core/services/workout_schedule_read_service.dart']);
    });

    test('an ABSENT allowlisted file is not stale — the builder does not exist yet',
        () {
      // schedule_row_builder.dart is created by Unit 2. Reporting it as stale
      // before then would make the gate noisy from the commit it lands in.
      expect(staleAllowlistEntries(const {}), isEmpty);
    });

    test('a still-constructing allowlisted file is not stale', () {
      final stale = staleAllowlistEntries({
        'lib/features/ai_coach/services/hotel_workout_planner.dart': _rowSource,
      });
      expect(stale, isEmpty);
    });
  });

  group('stripDartComments', () {
    test('removes block comments', () {
      expect(stripDartComments('a/* x */b').trim(), 'ab');
    });

    test('keeps string content that looks like a comment', () {
      expect(stripDartComments("var s = '/* not a comment */';"),
          contains('/* not a comment */'));
    });

    test('handles an escaped quote inside a string', () {
      const src = r"var s = 'it\'s fine'; // gone";
      final out = stripDartComments(src);
      expect(out, contains(r"it\'s fine"));
      expect(out, isNot(contains('gone')));
    });
  });
}
