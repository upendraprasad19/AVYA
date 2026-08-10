// Contract for diagnose e3b9d7 — streak-guardian sent self-contradicting pushes.
//
// THE BUG (founder's phone, 2026-08-05): a single notification read
// "Don't break your 28-day streak" beside a streak of 0 days, and titled itself
// "You hit a PR recently!" about a PR set 75 days earlier.
//
// TWO INDEPENDENT ROOT CAUSES, both writer/reader drift:
//
//  1. TWO-CACHE DISAGREEMENT. Eligibility selected + gated on
//     `user_progress.current_streak_weeks` only, while the message body quoted
//     `current_streak_days` from the DAILY SNAPSHOT — a different cache,
//     refreshed by a different writer on a different schedule. The founder's
//     row had current_streak_weeks=4 (frozen; last workout 2026-05-22) and
//     current_streak_days=0. Both numbers now come from THIS row, so they
//     cannot disagree, and `>= 1` means a user whose live streak is already 0
//     is never told they have one to protect.
//
//  2. UNBOUNDED "RECENTLY". The `recent_pr_exercise` title branch had NO
//     recency check at all. The field comes from
//     ai_snapshot_builder._getPRTimelineSummary, which scans every exlog row
//     ever with no date cutoff — so "recently" could mean months ago. Removed
//     rather than date-bounded: `pr-detection` is a separate cron with a
//     correct 20-minute lookback that already owns "you just hit a PR" in real
//     time, so a second, later surface celebrating the same event is redundant
//     even when correctly bounded.
//
// Deno source, not runnable under `flutter test` — this is a source-grep
// contract (presence/absence + ordering). Its SoT registry entry carries
// `presence_only: true` for that reason rather than a fabricated
// behavioral_test_path.
//
// COMMENTS ARE STRIPPED FIRST, and that is load-bearing here, not boilerplate:
// the fix's own comments deliberately name `recentPR` and `recent_pr_exercise`
// to explain what was removed and why. An un-stripped absent-grep would match
// the explanation and pass while the code was broken — or fail while the code
// was right. Per feedback_source_grep_strip_comments_first.md.
//
// Run: flutter test test/contracts/streak_guardian_eligibility_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  late String src;
  late String raw;

  setUpAll(() {
    raw = File('supabase/functions/streak-guardian/index.ts').readAsStringSync();
    src = _strip(raw);
  });

  group('root cause 1 — one row gates the send AND supplies the copy', () {
    test('eligibility SELECTS current_streak_days, not just weeks', () {
      expect(
        RegExp(r'\.select\(\s*"user_id,\s*current_streak_weeks,\s*'
                r'current_streak_days"\s*\)')
            .hasMatch(src),
        isTrue,
        reason: 'the number quoted in the copy must be fetched by the query '
            'that chose the recipient.',
      );
    });

    test('eligibility GATES on current_streak_days >= 1', () {
      // Selecting it is not enough — without the gate a live-0 user is still
      // chosen and still told to protect a streak.
      expect(
        RegExp(r'\.gte\(\s*"current_streak_days"\s*,\s*1\s*\)').hasMatch(src),
        isTrue,
        reason: 'THE FOUNDER CASE: current_streak_days=0 must not be eligible.',
      );
    });

    test('the weeks gate survives — this is additive, not a replacement', () {
      expect(
        RegExp(r'\.gte\(\s*"current_streak_weeks"\s*,\s*2\s*\)').hasMatch(src),
        isTrue,
      );
    });

    test('streakDays reads from the user_progress row, NOT the snapshot', () {
      expect(
        RegExp(r'const\s+streakDays\s*=\s*user\.current_streak_days')
            .hasMatch(src),
        isTrue,
        reason: 'reading it from `snap` is the two-cache drift itself.',
      );
      expect(
        RegExp(r'streakDays\s*=\s*\(?\s*snap[?.]').hasMatch(src),
        isFalse,
        reason: 'the snapshot must not be the source for this number again.',
      );
    });

    test('no weeks*7 fallback re-derives the contradiction', () {
      // `.gte("current_streak_days", 1)` means SQL already excluded NULL (NULL
      // fails `>=`), so a fallback would be unreachable today AND would
      // silently restore the exact two-source contradiction if that gate were
      // ever loosened. The guarantee lives in the query.
      expect(
        RegExp(r'streakDays\s*=.*\?\?\s*streakWeeks\s*\*\s*7').hasMatch(src),
        isFalse,
      );
    });
  });

  group('root cause 2 — the unbounded PR branch is gone from every surface',
      () {
    test('no recentPR identifier survives anywhere in the code', () {
      expect(
        src.contains('recentPR'),
        isFalse,
        reason: 'both the declaration and the title branch are removed.',
      );
    });

    test('the "You hit a PR recently!" title is gone', () {
      expect(src.contains('You hit a PR recently'), isFalse);
    });

    test('recent_pr_exercise is NOT handed to Gemini', () {
      // The load-bearing second half. Dropping it from the title alone would
      // not have been enough: the model writes the body independently and
      // would happily narrate the same unbounded, possibly months-old PR into
      // the copy. The model can only say what it is given.
      expect(
        src.contains('recent_pr_exercise'),
        isFalse,
        reason: 'this is how the contradiction reached the phone even with a '
            'different title.',
      );
    });

    test('the surviving arms of the else-if chain still exist', () {
      // Removing a branch from the MIDDLE of an else-if chain is exactly where
      // a stray brace silently re-nests everything after it. Pin the arms that
      // must remain reachable.
      expect(src.contains('milestone!'), isTrue);
      expect(src.contains('Almost at your goal weight!'), isTrue);
    });

    test('braces and parens balance — the chain was not broken by the removal',
        () {
      // Cheap structural proof for a Deno file no Dart test can execute.
      int net(String s, String open, String close) =>
          s.split(open).length - s.split(close).length;
      expect(net(src, '{', '}'), 0, reason: 'unbalanced braces in index.ts');
      expect(net(src, '(', ')'), 0, reason: 'unbalanced parens in index.ts');
    });
  });

  test('the fix is attributed in-source for the next reader', () {
    // Against the RAW text — the citation lives in a comment by design.
    expect(raw.contains('e3b9d7'), isTrue);
  });
}
