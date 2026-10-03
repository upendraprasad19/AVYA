// test/scripts/exercise_seam_lib_test.dart
//
// Unit test for the pure logic behind `check_exercise_seams.dart` (rule 24 — a
// gate ships with a test that can go RED).
//
// The gate exists because seam counts went 5 → 7 → 10 → 11 across four review
// rounds, each finding one the last had missed. Hand-enumeration of a
// mechanically-enumerable set fails once per round; this replaces "did I
// remember them all?" with "has the inventory moved?".
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/exercise_seam_lib.dart';

const _allow = <String, SeamEntry>{
  'lib/a.dart': SeamEntry(1, 'filters through the capability set'),
};

void main() {
  group('findSeamSites', () {
    test('finds a real call', () {
      final sites = findSeamSites({'lib/a.dart': 'final x = repo.getAll();'});
      expect(sites, hasLength(1));
      expect(sites.first.line, 1);
      expect(sites.first.pattern, '.getAll()');
    });

    test('IGNORES a pattern that only appears in a // comment', () {
      // The gate's first live run caught two of these that a plain grep had
      // counted — sync_community.dart and diet_plan_generator.dart both mention
      // getCustomExercises()/getAll() in prose.
      final sites = findSeamSites({
        'lib/a.dart': '// restored items vanished from getCustomExercises() and',
      });
      expect(sites, isEmpty);
    });

    test('finds a call on a line that ALSO carries a trailing comment', () {
      final sites =
          findSeamSites({'lib/a.dart': 'repo.getAll(); // the real call'});
      expect(sites, hasLength(1));
    });

    test('reports the correct line number', () {
      final sites =
          findSeamSites({'lib/a.dart': 'a\nb\nfinal x = repo.search("q");'});
      expect(sites.single.line, 3);
    });
  });

  group('seamViolations', () {
    test('an unchanged inventory is clean', () {
      final sites = [const SeamSite('lib/a.dart', 4, '.getAll()')];
      expect(seamViolations(sites, allowlist: _allow), isEmpty);
    });

    // ── red paths ────────────────────────────────────────────────────────
    test('a NEW file with a seam is a violation', () {
      // The exercise_picker_sheet case: a whole screen nobody had grepped.
      final sites = [
        const SeamSite('lib/a.dart', 4, '.getAll()'),
        const SeamSite('lib/new_screen.dart', 31, '.getAll()'),
      ];
      final violations = seamViolations(sites, allowlist: _allow);
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('lib/new_screen.dart'));
      expect(violations.join('\n'), contains('NEW exercise-emitting seam'));
    });

    test('an ADDED seam in an already-allowed file is a violation', () {
      // Counting by file alone would miss this; that is why the count is pinned.
      final sites = [
        const SeamSite('lib/a.dart', 4, '.getAll()'),
        const SeamSite('lib/a.dart', 9, 'PlannedExercise('),
      ];
      final violations = seamViolations(sites, allowlist: _allow);
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('expected 1'));
      expect(violations.join('\n'), contains('found 2'));
    });

    test('a REMOVED seam is a violation too', () {
      // Otherwise the allowlist rots into a list of files that no longer exist.
      final violations = seamViolations(const [], allowlist: _allow);
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('no seam sites'));
    });

    test('every violation names the file', () {
      final sites = [const SeamSite('lib/zzz.dart', 1, '.getAll()')];
      final violations = seamViolations(sites, allowlist: _allow);
      for (final v in violations) {
        expect(v, anyOf(contains('lib/zzz.dart'), contains('lib/a.dart')));
      }
    });
  });

  group('the shipped allowlist', () {
    test('every entry carries a non-trivial reason', () {
      // The reason field IS the gate: it records what each site does about
      // capability. An empty one makes the allowlist a rubber stamp.
      for (final e in seamAllowlist.entries) {
        expect(e.value.reason.length, greaterThan(30),
            reason: '${e.key} needs a real reason, not a placeholder');
        expect(e.value.count, greaterThan(0));
      }
    });

    test('the four seams found late are all pinned', () {
      // swap sheet, picker, cardio finisher, warmup/cooldown — rounds 1-4.
      expect(seamAllowlist.keys,
          contains('lib/features/train/widgets/exercise_swap_sheet.dart'));
      expect(
          seamAllowlist.keys,
          contains(
              'lib/features/train/screens/active_workout/exercise_picker_sheet.dart'));
      expect(seamAllowlist.keys,
          contains('lib/shared/repositories/plan_engine/cardio_finisher.dart'));
      expect(seamAllowlist.keys,
          contains('lib/shared/repositories/plan_engine/warmup_cooldown.dart'));
    });
  });
}
