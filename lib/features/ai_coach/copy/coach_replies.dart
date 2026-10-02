// F17 · Test #9 — on-brand reply copy for gated states.
//
// Mirrored on the server at supabase/functions/_shared/coach_replies.ts.
// Used as fallback display when the server response doesn't include a
// pre-formatted counter line, or for client-side toasts.
//
// OI-153 (2026-09-12) — no copy here may promise "unlimited": PRO media reads
// have a visible daily ceiling (10 images / 5 videos per IST day). Pinned by
// test/contracts/coach_replies_test.dart, which also pins EVERY server key
// byte-identical to its twin here.
import 'package:icanbefitter/core/constants/app_constants.dart';

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

  /// Part B (gemini3-limits-caching) — the daily CHAT cap, reached. Client-only
  /// copy (the server's 429 carries `tier` + `limit`, not text). PRO: no
  /// upsell and no rank (they already pay), says WHEN it resets. Free: names
  /// the cap and what PRO adds, in modest terms — no "unlimited", no number
  /// for PRO, no implication of a human coach.
  static String chatDailyLimitReached({required bool isPro, required int limit}) {
    if (isPro) {
      return 'That is $limit messages today — your daily limit. '
          'Bridge resets the count at midnight IST.';
    }
    return 'That is $limit messages today, Recruit — the free daily limit. '
        'Bridge resets the count at midnight IST. '
        'PRO adds dedicated coaching and higher limits.';
  }

  /// Builds [chatDailyLimitReached] from a thrown error's text. The ai-proxy
  /// 429 body is `{error, code: RATE_LIMITED, tier, limit}`; a FunctionException
  /// prints it as a Dart map (`tier: pro`) or JSON (`"tier":"pro"`), so both
  /// shapes parse. A body without them (an older server) falls back to the
  /// caller's own tier and the matching AppConstants cap.
  static String chatRateLimitedFromError(String errStr, {required bool isPro}) {
    final tier = RegExp(r'tier["' "'" r']?\s*:\s*["' "'" r']?(free|pro)\b',
            caseSensitive: false)
        .firstMatch(errStr);
    final limit = RegExp(r'\blimit["' "'" r']?\s*:\s*["' "'" r']?(\d+)',
            caseSensitive: false)
        .firstMatch(errStr);
    final pro = tier == null ? isPro : tier.group(1)!.toLowerCase() == 'pro';
    // `int.tryParse`: a 30-digit "limit" would throw out of the error handler.
    final parsed = limit == null ? null : int.tryParse(limit.group(1)!);
    final cap = parsed ??
        (pro ? AppConstants.proAiMessagesPerDay : AppConstants.freeAiMessagesPerDay);
    return chatDailyLimitReached(isPro: pro, limit: cap);
  }

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
