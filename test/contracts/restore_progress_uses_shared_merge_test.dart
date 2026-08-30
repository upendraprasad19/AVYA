// OI-83 (2026-08-03) — ROUTING pin for the two cloud→Hive `progress` restore
// writers.
//
// This is a SOURCE-GREP test and therefore proves PRESENCE ONLY
// (`feedback_source_grep_false_confidence`). The behaviour it guards — the
// local-max-wins merge itself — is covered by
// `progress_restore_monotonic_behavioral_test.dart`. What this file adds is the
// one thing a behavioral test on a pure helper cannot see: that the two
// production writers actually CALL that helper. They are private and
// network-bound, so nothing else pins the wiring.
//
// Both writers previously built the merge inline, independently, with the same
// expression and neither emitting telemetry — i.e. they had already drifted
// into two copies of one rule. Two copies is how the next one gets fixed and
// the other does not.
//
// Comments are stripped before every absent-pattern assertion
// (`feedback_source_grep_strip_comments_first`) — the OI-83 comments in these
// files describe the old shape in prose, and an unstripped scan would match
// the documentation of the bug and call it the bug.
//
// Run: flutter test test/contracts/restore_progress_uses_shared_merge_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';

/// Strip `/* … */` and `// …` so prose about the old merge cannot be mistaken
/// for the old merge.
String _stripComments(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  const writers = <String>[
    'lib/core/services/sync/sync_profile.dart',
    'lib/core/services/auth_session_bootstrapper.dart',
  ];

  group('restore progress writers route through the shared merge', () {
    for (final path in writers) {
      test('$path calls UserRepository.mergeCloudProgress', () {
        final f = File(path);
        expect(f.existsSync(), isTrue, reason: '$path moved or was renamed');
        final src = _stripComments(f.readAsStringSync());
        expect(src, contains('UserRepository.mergeCloudProgress('),
            reason: 'the OI-83 monotonic guard lives in that helper — a writer '
                'that stops calling it silently re-opens the demotion');
      });

      test('$path reports refused demotions', () {
        final src = _stripComments(File(path).readAsStringSync());
        expect(src, contains('reportProgressDemotionsDeclined('),
            reason: 'a refused demotion that nobody can see is the SILENT half '
                'of this bug; the shared emitter is what makes it visible');
      });

      test("$path writes only merge results to put('progress', …)", () {
        final src = _stripComments(File(path).readAsStringSync());
        final writes = RegExp(r"put\(\s*'progress'\s*,\s*([A-Za-z0-9_.]+)\s*\)")
            .allMatches(src)
            .map((m) => m.group(1)!)
            .toList();
        expect(writes, isNotEmpty,
            reason: 'no progress write found — this pin is now watching '
                'nothing, which reads as coverage it does not have');
        for (final arg in writes) {
          expect(arg, endsWith('.merged'),
              reason: 'progress write takes `$arg`, not a ProgressMergeResult '
                  '— an inline merge here is exactly the pre-OI-83 shape');
        }
      });
    }
  });

  group('login-restore plan regen uses the GUARDED phase', () {
    // B-pass finding 1. The bootstrapper writes the monotonically-guarded
    // `current_phase` to Hive, then a few lines below regenerates the plan when
    // `hasPlan()` is false — and that block used to take its phase from
    // `progressRows.first['current_phase']`, the PRE-merge cloud value. On a
    // restore that had just REFUSED a demotion (local ahead of cloud, not yet
    // pushed) it would generate a plan for the LOWER phase while the counter
    // held the higher one: counter and plan content disagreeing, which is the
    // failure shape OI-85 tracks, reached by a third path the guard did not
    // cover. Presence-only by construction — the behaviour needs a live
    // Supabase session — so it is pinned as an absent-pattern instead.
    test('does not read the raw cloud current_phase for generateAndSchedule',
        () {
      final src = _stripComments(
          File('lib/core/services/auth_session_bootstrapper.dart')
              .readAsStringSync());
      expect(
        src.contains(RegExp(r"progressRows\.first\[\s*'current_phase'\s*\]")),
        isFalse,
        reason: 'the generation phase must come from the post-merge Hive value '
            '(UserRepository.instance.getProgress()), not the pre-merge cloud '
            'row — otherwise a refused demotion still reaches the plan',
      );
    });

    test('reads the phase from UserRepository instead', () {
      final src = _stripComments(
          File('lib/core/services/auth_session_bootstrapper.dart')
              .readAsStringSync());
      expect(
        src.contains(RegExp(
            r"UserRepository\.instance\.getProgress\(\)\?\[\s*'current_phase'\s*\]")),
        isTrue,
        reason: 'positive half — an absent-pattern test alone would also pass '
            'if the whole block were deleted',
      );
    });
  });

  // ── OI-150 Part A: the plan-regen anchor ───────────────────────────────────
  //
  // d1f6b3's B-pass finding F1 repointed the `phase` argument at the guarded
  // Hive value and left the `startDate` argument on the raw pre-merge cloud
  // row — eight lines below, in the same generateAndSchedule call.
  group('plan regen anchors on the guarded value (OI-150)', () {
    test('a present Hive ISO is used verbatim', () {
      final now = DateTime.utc(2026, 8, 30);
      expect(
        AuthSessionBootstrapper.resolvePlanRegenStart(
            hiveIso: '2026-05-25T00:00:00.000Z', now: now),
        DateTime.parse('2026-05-25T00:00:00.000Z'),
      );
    });

    test('a null Hive ISO falls back to now — never to the cloud row', () {
      final now = DateTime.utc(2026, 8, 30);
      expect(
          AuthSessionBootstrapper.resolvePlanRegenStart(
              hiveIso: null, now: now),
          now);
    });

    test('an unparseable Hive ISO falls back to now', () {
      final now = DateTime.utc(2026, 8, 30);
      expect(
          AuthSessionBootstrapper.resolvePlanRegenStart(
              hiveIso: 'not-a-date', now: now),
          now);
    });

    test('the bootstrapper resolves the anchor from the guarded accessor', () {
      final src = _stripComments(
          File('lib/core/services/auth_session_bootstrapper.dart')
              .readAsStringSync());
      // Positive half — the guarded accessor feeds the resolver.
      expect(src.contains('resolvePlanRegenStart('), isTrue);
      expect(
        src.contains(RegExp(
            r'hiveIso:\s*UserRepository\.instance\.getPhaseStartedAtIso\(\)')),
        isTrue,
        reason: 'the anchor must come from the post-merge Hive value, via the '
            'typed accessor rather than a hand-rolled map read',
      );
      // The raw pre-merge cloud read survives ONLY inside the §4.6 kill-switch
      // branch. Pinned by COUNT + the switch's presence rather than by slicing
      // the source at a brace, which would break on a reformat and report it
      // as a missing kill-switch.
      expect(
        AuthSessionBootstrapper.kDisableGuardedPlanRegenAnchorKey,
        'disable_guarded_plan_regen_anchor',
      );
      expect(src, contains(AuthSessionBootstrapper.kDisableGuardedPlanRegenAnchorKey),
          reason: 'the pre-fix path must stay reachable behind a kill-switch');
      expect(
        RegExp(r"progressRows\.first\[\s*'phase_started_at'\s*\]")
            .allMatches(src)
            .length,
        1,
        reason: 'exactly ONE raw-cloud read may remain — the one inside the '
            'kill-switch branch. Two means the guarded path reads it too; '
            'zero means the pre-fix path was deleted rather than gated',
      );
    });
  });
}
