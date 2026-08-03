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
        '(OI-45 finding 5 / Unit 3c; re-justified Unit B / OI-84)', () {
      expect(
        tierFor('lib/features/train/screens/graduation_screen.dart'),
        'account',
        reason: 'graduation_screen.dart is the UI entry point for the PRO '
            'phase advance and gates phases_2_to_12 — a diff touching only '
            'this file must clear the account-tier gate, not classify as '
            'feature.\n'
            'NOTE (Unit B / OI-84, 2026-08-03): the original justification was '
            '"writes the progress map directly (_onPro())". That is no longer '
            'true — the write moved to runGraduationPhaseAdvance in '
            'pro_phase_advance.dart. The TIER is unchanged (see next test for '
            'why the gate did not weaken), but the reason had to be restated: '
            'a rule whose stated justification is false reads as coverage it '
            'does not have.',
      );
    });

    test(
        'the hoist did not move the progress write into a weaker tier '
        '(Unit B / OI-84)', () {
      // The real risk of that hoist: relocating the write into a path that
      // classifies BELOW account would have silently downgraded the gate while
      // every other test still passed. pro_phase_advance.dart carries its own
      // file-scoped account rule (docs/blast_radius.yaml), so it did not — but
      // that has to be asserted, not assumed, or the next move can regress it.
      expect(
        tierFor('lib/shared/services/pro_phase_advance.dart'),
        'account',
        reason: 'pro_phase_advance.dart now owns the graduation progress '
            'write as well as the other three advance paths; it must be at '
            'least as gated as the screen the code came from.',
      );
      // Round-1 review B1: the assertion above covered only ONE of the unit's
      // two extraction targets while claiming to cover "the hoist". The preview
      // card is the other, and it lands at `feature` — CORRECT, not an
      // oversight: it is pure read-only UI. Promoting it would over-gate
      // routine Train-tab edits for no safety gain, the same argument the
      // `train_screen.dart stays feature` case below makes.
      expect(
        tierFor('lib/features/train/widgets/phase2_preview_card.dart'),
        'feature',
        reason: 'the extracted preview card is read-only UI, so feature tier '
            'is right',
      );
      // Round-2 review: the first version of this block claimed "if a WRITE is
      // ever added there, this test says the tier must be revisited". FALSE —
      // tierFor() resolves globs from docs/blast_radius.yaml and never reads
      // file CONTENT, so adding saveProgress(...) to that card would leave it
      // matching lib/features/train/** -> feature and this test green. Rather
      // than only softening the comment, make the promise TRUE with an actual
      // content check: the `feature` tier above is only defensible while the
      // card stays read-only, so assert exactly that.
      final card = File('lib/features/train/widgets/phase2_preview_card.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .replaceAll(RegExp(r'//[^\n]*'), '');
      for (final write in [
        'saveProgress(',
        'updateProgress(',
        'MigratedKey.write',
        '.put(',
        'WriteService',
      ]) {
        expect(card.contains(write), isFalse,
            reason: 'phase2_preview_card.dart must stay READ-ONLY — its '
                'feature tier is justified by having no progress-map write. '
                'Adding $write means the tier claim above is no longer true '
                'and the file needs its own account rule in '
                'docs/blast_radius.yaml.');
      }
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
