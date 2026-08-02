// Contract test for the CQRS query-naming gate (OI-44 / L26).
//
// This test exists because a gate that has never been shown to FAIL is not a
// gate. `no_top_level_duration_seconds_reads_test` shipped with a failure
// message recommending the exact call that caused the bug it guarded, and
// nobody noticed for weeks because it was only ever observed passing
// (diagnose d4e7c2). So every detection shape is proven against a committed
// fixture of deliberate violations, and every clean shape is proven NOT to
// fire.
//
// Two deliberate choices, both learned the hard way in this batch:
//
//  1. It imports the LIBRARY rather than spawning the CLI. The first version
//     did `Process.runSync(Platform.resolvedExecutable, ['run', gate])` — but
//     under `flutter test` the resolved executable is `flutter_tester`, not
//     `dart`, so it spawned hung flutter_tester processes. Same lib-extraction
//     pattern as `worktree_guard_lib.dart` + its contract test.
//
//  2. The negative control is a committed fixture under `test/fixtures/`, not
//     a violation planted into `lib/` and reverted. Unit 7's round-2 reviewer
//     did the latter and silently destroyed a batch's work when its "revert"
//     restored the file to git HEAD.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/cqrs_query_naming_lib.dart';

const _fixtureRoot = 'test/fixtures/cqrs_gate';

void main() {
  group('CQRS query-naming gate', () {
    late final CqrsScanResult fixture;
    late final CqrsScanResult lib;

    setUpAll(() {
      fixture = scanRoot(_fixtureRoot);
      lib = scanRoot('lib');
    });

    String? patternFor(CqrsScanResult r, String member) {
      for (final v in r.violations) {
        if (v.member == member) return v.pattern;
      }
      return null;
    }

    test('the CLI, the library and the fixture all exist', () {
      expect(File('scripts/check_cqrs_query_naming.dart').existsSync(), isTrue);
      expect(File('scripts/cqrs_query_naming_lib.dart').existsSync(), isTrue);
      expect(File('$_fixtureRoot/violations.dart').existsSync(), isTrue);
    });

    test('DETECTS every mutation shape in the fixture — proves it '
        'discriminates', () {
      // 1. low-level Hive write
      expect(patternFor(fixture, 'getCountAndCache'), 'Hive box.put()');
      // 2. MigratedKey.write
      expect(patternFor(fixture, 'isReadyAndStamp'),
          'MigratedKey.write/delete');
      // 3. repository-pattern writer call — the shape a low-level-only gate
      //    misses, and the shape rule 4 makes the NORM in this codebase.
      expect(patternFor(fixture, 'hasPendingAndCommit'),
          'WriteService/Repository writer call');
      // 4. two-hop same-file delegation (the calculateCurrentStreak shape)
      expect(patternFor(fixture, 'calculateViaDelegate'),
          'delegates to _hopOne()');
    });

    test('the fixture scan is NOT vacuously green', () {
      // Guards against the scanner silently finding nothing (a parser
      // regression would make every other expectation here pass by absence).
      expect(fixture.unexempted(applyExemptions: false).length, 4,
          reason: 'expected exactly the 4 planted violations, got: '
              '${fixture.violations}');
      expect(fixture.membersScanned, greaterThan(4),
          reason: 'the clean controls must also have been scanned');
    });

    test('does NOT flag the clean controls', () {
      // Telemetry confined to a catch block is not a mutation of the query's
      // result. Flagging it would reintroduce the false positive the
      // 2026-07-29 board correction removed (RankService.getCurrentRank).
      expect(patternFor(fixture, 'getValueWithCatchTelemetry'), isNull,
          reason: 'catch-block telemetry must not count as a mutation');

      // Write syntax appearing only inside a string or comment is prose, not
      // code (feedback_source_grep_strip_comments_first.md).
      expect(patternFor(fixture, 'getDescription'), isNull,
          reason: 'strings and comments must be scrubbed before scanning');

      expect(patternFor(fixture, 'getPureCount'), isNull,
          reason: 'a genuinely pure query must not be flagged');

      // The gate polices query-NAMED mutators, not all mutators.
      expect(patternFor(fixture, 'commitSomethingHonestly'), isNull,
          reason: 'an honestly-named writer is not in scope');
    });

    test('lib/ is green — every live violation carries a reasoned exemption',
        () {
      expect(lib.unexempted(), isEmpty,
          reason: 'either the member is pure, or it needs a cqrsExemptions '
              'entry stating why the mutation is deliberate. Unexempted: '
              '${lib.unexempted()}');
    });

    test('no exemption has gone stale', () {
      expect(staleExemptions(lib), isEmpty,
          reason: 'an exemption matching nothing is a graveyard entry. Delete '
              'it — that deletion is the record that the violation closed.');
    });

    test('every exemption carries a real justification', () {
      expect(cqrsExemptions, isNotEmpty);
      cqrsExemptions.forEach((key, reason) {
        expect(reason.trim().length, greaterThan(80),
            reason: 'exemption "$key" needs a real justification, not a '
                'placeholder — an unexplained exemption is how a gate becomes '
                'a graveyard');
      });
    });

    test('the real tree is actually being scanned', () {
      // A scan root that silently resolved to nothing would make the "lib/ is
      // green" assertion above meaningless.
      expect(lib.filesScanned, greaterThan(300));
      expect(lib.membersScanned, greaterThan(50));
    });
  });
}
