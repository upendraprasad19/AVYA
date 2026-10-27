// Pins the CONTENTS of `kTrackedArtifacts` in
// scripts/check_context_artifact_budget.dart.
//
// Why this exists (context-lean batch, 2026-09-29, round-2 review finding):
// the budget gate's other tests exercise the decision logic and the exit codes
// with synthetic fixtures, but none asserted WHICH real files are tracked. So
// deleting one of the seven paths this batch added (the two trimmed skills and
// five trimmed nested CLAUDE.md files) reddened ZERO tests, and the gate then
// printed `SKIPPED <path> — not readable` with exit 0 — a path dropped from
// tracking looked identical to a transient read failure. A guard that can be
// silently removed is not a guard.
//
// Two directions, both required:
//  * every path in the recorded baseline (`backups/context_artifact_sizes.json`)
//    is still tracked — catches removing an entry from the list;
//  * every tracked path has a baseline — catches adding one and forgetting
//    `--record` (the gate would only ever say SKIPPED for it).
// Plus an explicit by-name pin of the ten paths, so shrinking BOTH the list and
// the baseline together (the way to dodge the two-way check) is still red.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/build_local_indexes.dart' show ensureLocalIndexes;
import '../../scripts/check_context_artifact_budget.dart' show kTrackedArtifacts;
import '../helpers/dart_source_slice.dart';

const _pinned = <String>{
  'CLAUDE.md',
  'docs/audit/OPEN_INDEX.md',
  'docs/audit/open_issues.md',
  '.claude/skills/code-review/SKILL.md',
  '.claude/skills/debugging/SKILL.md',
  'supabase/functions/CLAUDE.md',
  'lib/features/train/CLAUDE.md',
  'lib/features/auth/CLAUDE.md',
  'lib/core/services/CLAUDE.md',
  'lib/features/ai_coach/CLAUDE.md',
  'lib/shared/repositories/plan_engine/CLAUDE.md',
  'supabase/migrations/CLAUDE.md',
  'lib/features/onboarding/CLAUDE.md',
};

void main() {
  final tracked = kTrackedArtifacts.toSet();

  // A2 (merge-conflict-treadmill): docs/audit/OPEN_INDEX.md is a gitignored LOCAL BUILD PRODUCT,
  // so a fresh clone or worktree has none, and `every tracked artifact exists on disk` below
  // would fail on a bare `flutter test`, on `PRE_COMMIT_FULL=1` and on /build-apk's suite gate.
  // The test builds the one index it reads for itself (the OI index only: nothing in test/
  // reads docs/diagnoses/INDEX.md). CI also builds both before the shards; this keeps a local
  // run self-sufficient.
  setUpAll(() {
    final rc = ensureLocalIndexes(Directory.current.path);
    if (rc != 0) {
      fail('could not build docs/audit/OPEN_INDEX.md (exit $rc); run '
          '`dart run scripts/build_local_indexes.dart` and read what it says');
    }
  });

  // The existence test below is red ONLY on a tree that has no OPEN_INDEX.md, which is exactly the
  // tree `setUpAll` exists for (a fresh worktree, a bare `flutter test`, /build-apk's suite gate)
  // and exactly NOT the tree anyone runs this on after a build: removing the `setUpAll` stays
  // green everywhere it is run. So the wiring itself is pinned, in comment-stripped source
  // (presence only, like every source grep): the call, inside a `setUpAll`, before any test.
  test('PRESENCE: this file builds the one index it reads, in setUpAll, before its first test', () {
    final src = stripDartComments(
        File('test/scripts/context_artifact_tracked_list_test.dart').readAsStringSync());
    // The needles are split in two so that the text searched for does not occur in THIS test's own
    // source: a needle that quotes itself would be found here even with the real setUpAll deleted.
    final setUp = src.indexOf('setUpAll(() ' '{');
    final build = src.indexOf('ensureLocalIndexes(Directory' '.current.path)');
    final firstTest = src.indexOf("  test('the tracked list contains every" " pinned");
    expect(setUp, isNonNegative, reason: 'the setUpAll block is gone');
    expect(build, greaterThan(setUp), reason: 'ensureLocalIndexes must be called INSIDE the setUpAll');
    expect(build, lessThan(firstTest), reason: 'and before the first test, or it builds too late');
  });

  test('the tracked list contains every pinned context artifact', () {
    expect(_pinned.difference(tracked), isEmpty,
        reason: 'a context artifact was dropped from kTrackedArtifacts; it '
            'would silently stop being budgeted');
  });

  test('tracked list and recorded baseline name the same files', () {
    final raw = jsonDecode(
        File('backups/context_artifact_sizes.json').readAsStringSync());
    final baseline = (raw as Map<String, dynamic>).keys.toSet();
    expect(baseline.difference(tracked), isEmpty,
        reason: 'baseline holds a path the gate no longer tracks');
    expect(tracked.difference(baseline), isEmpty,
        reason: 'a tracked path has no baseline — run '
            '`dart run scripts/check_context_artifact_budget.dart --record`');
  });

  // NOTE for the budget baseline: OPEN_INDEX.md is measured AS BUILT LOCALLY (a stamp line adds
  // about 87 B); an absent file is SKIPPED by the gate (fails open), a present one is compared
  // with `backups/context_artifact_sizes.json`.
  test('every tracked artifact exists on disk', () {
    for (final p in tracked) {
      expect(File(p).existsSync(), isTrue, reason: '$p is tracked but missing');
    }
  });
}
