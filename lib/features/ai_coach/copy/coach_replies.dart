// F17 · Test #9 — on-brand reply copy for gated states.
//
// Mirrored on the server at supabase/functions/_shared/coach_replies.ts.
// Used as fallback display when the server response doesn't include a
// pre-formatted counter line, or for client-side toasts.
//
// OI-153 (2026-09-12) — no copy here may promise "unlimited": PRO media reads
// have a visible daily ceiling (50 images / 10 videos per IST day). Pinned by
// test/contracts/coach_replies_test.dart, which also pins EVERY server key
// byte-identical to its twin here.
class CoachReplies {
  CoachReplies._();

  /// F11 welcome bubble shown on chat empty state.
  static const String welcomeBridge =
      'Bridge here, Recruit. Standing by for orders. '
      '*Workouts, nutrition, recovery* — fire away.';

  /// F14 — 5 lifetime free image analyses
  static String freeImageCounter(int remaining) {
    if (remaining > 1) {
      return 'ⓘ $remaining of 5 free analyses left. [Upgrade to PRO →]';
    }
    if (remaining == 1) {
      return 'ⓘ Last free analysis used. [Upgrade to PRO →]';
    }
    return "ⓘ You've used your 5 free analyses. [Upgrade →]";
  }

  static const String imagePaywallExhausted =
      "Photo received, Recruit. "
      "You've used your 5 free analyses. "
      '[Upgrade to PRO →] for image + video reads every day.';

  /// OI-162 slice 3b — the fail-CLOSED path's copy. When the quota ledger is
  /// unreadable the server refuses, and reusing [imagePaywallExhausted] would
  /// claim the user spent 5 analyses when they may have spent none. Mirrors
  /// `imageQuotaUnavailable` in the server's coach_replies.ts.
  static const String imageQuotaUnavailable =
      'Photo received, Recruit. Bridge cannot reach the quota log right now, '
      'so it is standing down rather than guessing. '
      'Try again in a moment — this is not a limit.';

  /// OI-153 — rank-free twins for the PRO ledger fault and the tier-read
  /// fault. Mirror `imageLedgerUnavailable` / `videoLedgerUnavailable`.
  static const String imageLedgerUnavailable =
      'Photo received. Bridge cannot reach the quota log right now, '
      'so it is standing down rather than guessing. '
      'Try again in a moment — this is not a limit.';

  static const String videoLedgerUnavailable =
      'Video received. Bridge cannot reach the quota log right now, '
      'so it is standing down rather than guessing. '
      'Try again in a moment — this is not a limit.';

  /// OI-153 — the PRO daily ceiling, reached. Mirrors the server FUNCTIONS
  /// `proImageDailyCapReached(cap)` / `proVideoDailyCapReached(cap)`; the
  /// number is passed in, never typed here.
  static String proImageDailyCapReached(int cap) {
    return 'Photo received. That is $cap image reads today — the PRO daily ceiling. '
        'Bridge resets the counter at midnight IST; '
        'send it again after 00:00 and it goes straight through.';
  }

  static String proVideoDailyCapReached(int cap) {
    return 'Video received. That is $cap video reads today — the PRO daily ceiling. '
        'Bridge resets the counter at midnight IST; '
        'send it again after 00:00 and it goes straight through.';
  }

  /// F15 — always-PRO video
  static const String videoPaywall =
      'Video received, Recruit. Bridge sees it. '
      'Video analysis is a *PRO* capability — form checks, technique '
      'breakdowns, posture reviews. [Upgrade →]';
}
