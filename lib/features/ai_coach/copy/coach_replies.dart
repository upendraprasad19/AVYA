// F17 · Test #9 — on-brand reply copy for gated states.
//
// Mirrored on the server at supabase/functions/_shared/coach_replies.ts.
// Used as fallback display when the server response doesn't include a
// pre-formatted counter line, or for client-side toasts.
class CoachReplies {
  CoachReplies._();

  /// F11 welcome bubble shown on chat empty state.
  static const String welcomeBridge =
      'Bridge here, Recruit. Standing by for orders. '
      '*Workouts, nutrition, recovery* — fire away.';

  /// F14 — 5 lifetime free image analyses
  static String freeImageCounter(int remaining) {
    if (remaining > 1) {
      return 'ⓘ $remaining of 5 free analyses left. [Upgrade for unlimited →]';
    }
    if (remaining == 1) {
      return 'ⓘ Last free analysis used. [Upgrade for unlimited →]';
    }
    return "ⓘ You've used your 5 free analyses. [Upgrade →]";
  }

  static const String imagePaywallExhausted =
      "Photo received, Recruit. "
      "You've used your 5 free analyses. "
      '[Upgrade to PRO →] for unlimited image + video reads.';

  /// F15 — always-PRO video
  static const String videoPaywall =
      'Video received, Recruit. Bridge sees it. '
      'Video analysis is a *PRO* capability — form checks, technique '
      'breakdowns, posture reviews. [Upgrade →]';
}
