// test/contracts/blast_radius_progress_map_writer_paths_test.dart
//
// B-pass finding, progress-map-consolidation batch (2026-07-30, Unit 3a):
// docs/blast_radius.yaml's catch-all comment said "lib/shared/repositories
// ... is account" since the registry was written, but no rule ever
// implemented it — lib/shared/repositories/** fell through the
// lib/shared/** -> feature catch-all (first-match-wins), so a diff touching
// ONLY user_repository.dart (the writer/reader owner of the progress and
// profile Hive maps this whole batch is about) cleared zero review gate.
// Same mechanism caught graduation_screen.dart: it contains a confirmed
// direct progress-map write (OI-45 finding 5 / Unit 3c) but sits under
// lib/features/train/**, which is feature-tier.
//
// This is a REAL classifier-behavior test (spawns the actual
// scripts/blast_radius_from_diff.dart subprocess against real repo paths),
// not a source-grep of the yaml text — per
// feedback_source_grep_false_confidence.md, presence of a glob string in the
// file doesn't prove it actually wins under first-match-wins ordering.
// Mirrors the existing subprocess-invocation pattern in
// blast_radius_content_rule_wired_all_scripts_test.dart.
//
// Run: flutter test test/contracts/blast_radius_progress_map_writer_paths_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String tierFor(String path) {
    final process = Process.runSync(
      'dart',
      ['run', 'scripts/blast_radius_from_diff.dart', path],
      runInShell: true,
    );
    final m = RegExp(r'Blast-radius:\s*(\w+)')
        .firstMatch((process.stdout as String).trim());
    expect(m, isNotNull,
        reason: 'classifier printed no tier for $path:\n${process.stdout}');
    return m!.group(1)!;
  }

  group('blast_radius.yaml — progress-map writer paths are >= account', () {
    test('lib/shared/repositories/user_repository.dart is account', () {
      expect(
        tierFor('lib/shared/repositories/user_repository.dart'),
        'account',
        reason: 'user_repository.dart owns the progress/profile Hive map '
            'writer contracts (Repository pattern, lib/CLAUDE.md) — a diff '
            'touching only this file must clear the account-tier gate '
            '(code_review_b_pass), not silently classify as feature.',
      );
    });

    test(
        'lib/features/train/screens/graduation_screen.dart is account '
        '(OI-45 finding 5 / Unit 3c)', () {
      expect(
        tierFor('lib/features/train/screens/graduation_screen.dart'),
        'account',
        reason: 'graduation_screen.dart writes the progress map directly '
            '(_onPro()) — Unit 3c will fix a confirmed stale-value bug '
            'there, and that diff must not silently classify as feature.',
      );
    });

    test(
        'lib/shared/repositories/plan_engine/** stays platform '
        '(more-specific rule, unaffected by the new account rule)', () {
      expect(
        tierFor('lib/shared/repositories/plan_engine/plan_generator_v4.dart'),
        'platform',
        reason: 'the plan_engine-specific platform rule is declared before '
            'the new lib/shared/repositories/** account rule and must still '
            'win under first-match-wins — this fix must not accidentally '
            'downgrade plan_engine from platform to account.',
      );
    });

    test(
        'other lib/features/train/** files stay feature (the fix is scoped '
        'to graduation_screen.dart, not the whole tree)', () {
      expect(
        tierFor('lib/features/train/screens/train_screen.dart'),
        'feature',
        reason: 'only graduation_screen.dart has a confirmed progress-map '
            'write — blanket-promoting the whole train/** tree would '
            'over-gate routine Train-tab UI changes with no safety gain.',
      );
    });
  });
}
