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

  // OI-162 slice 3b — the fail-CLOSED path needs its OWN copy. When the quota
  // ledger is unreadable the gate now refuses, and reusing
  // `imagePaywallExhausted` would tell the user they had spent 5 analyses when
  // they may have spent none. A refusal the user cannot act on must at least
  // be honest about why, and must not be mistaken for the paywall.
  imageQuotaUnavailable:
    'Photo received, Recruit. Bridge cannot reach the quota log right now, ' +
    'so it is standing down rather than guessing. ' +
    'Try again in a moment — this is not a limit.',

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
