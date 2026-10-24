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

import '../../scripts/check_context_artifact_budget.dart' show kTrackedArtifacts;

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

  test('every tracked artifact exists on disk', () {
    for (final p in tracked) {
      expect(File(p).existsSync(), isTrue, reason: '$p is tracked but missing');
    }
  });
}
