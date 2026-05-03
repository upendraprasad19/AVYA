// F17 · Test #9 — on-brand reply copy for gated states.
// Mirrored on the client at lib/features/ai_coach/copy/coach_replies.dart.

export const COACH_REPLIES = {
  videoPaywall:
    'Video received, Recruit. Bridge sees it. ' +
    'Video analysis is a *PRO* capability — form checks, technique ' +
    'breakdowns, posture reviews. [Upgrade →]',

  imagePaywallExhausted:
    "Photo received, Recruit. " +
    "You've used your 5 free analyses. " +
    '[Upgrade to PRO →] for unlimited image + video reads.',

  freeImageCounter(remaining: number): string {
    if (remaining > 1) {
      return `ⓘ ${remaining} of 5 free analyses left. [Upgrade for unlimited →]`;
    }
    if (remaining === 1) {
      return 'ⓘ Last free analysis used. [Upgrade for unlimited →]';
    }
    return "ⓘ You've used your 5 free analyses. [Upgrade →]";
  },
};
