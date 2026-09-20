// F17 · Test #9 — on-brand reply copy for gated states.
// Mirrored on the client at lib/features/ai_coach/copy/coach_replies.dart.
//
// OI-153 (2026-09-12) — no copy in this file may promise "unlimited": PRO
// media reads have a visible daily ceiling (50 images / 10 videos per IST
// day), so the word is false the day the cap fires. Pinned by
// test/contracts/coach_replies_test.dart, which also pins EVERY key here
// byte-identical to its client twin.

export const COACH_REPLIES = {
  videoPaywall:
    'Video received, Recruit. Bridge sees it. ' +
    'Video analysis is a *PRO* capability — form checks, technique ' +
    'breakdowns, posture reviews. [Upgrade →]',

  imagePaywallExhausted:
    "Photo received, Recruit. " +
    "You've used your 5 free analyses. " +
    '[Upgrade to PRO →] for image + video reads every day.',

  // OI-162 slice 3b — the fail-CLOSED path needs its OWN copy. When the quota
  // ledger is unreadable the gate now refuses, and reusing
  // `imagePaywallExhausted` would tell the user they had spent 5 analyses when
  // they may have spent none. A refusal the user cannot act on must at least
  // be honest about why, and must not be mistaken for the paywall.
  imageQuotaUnavailable:
    'Photo received, Recruit. Bridge cannot reach the quota log right now, ' +
    'so it is standing down rather than guessing. ' +
    'Try again in a moment — this is not a limit.',

  // OI-153 — rank-free twins of the above, for the PRO ledger fault AND the
  // tier-read fault (where the tier — and so the rank — is exactly what is
  // unknown). PRO users hold ranks; "Recruit" would be wrong for them.
  imageLedgerUnavailable:
    'Photo received. Bridge cannot reach the quota log right now, ' +
    'so it is standing down rather than guessing. ' +
    'Try again in a moment — this is not a limit.',

  videoLedgerUnavailable:
    'Video received. Bridge cannot reach the quota log right now, ' +
    'so it is standing down rather than guessing. ' +
    'Try again in a moment — this is not a limit.',

  // OI-153 — the PRO daily ceiling, reached. A FUNCTION like
  // `freeImageCounter`, because the cap constants live in ai-media-proxy,
  // which imports this file — the number is passed in, never typed here.
  // No upgrade CTA: the reader already pays. States WHEN it resets.
  proImageDailyCapReached(cap: number): string {
    return `Photo received. That is ${cap} image reads today — the PRO daily ceiling. ` +
      'Bridge resets the counter at midnight IST; ' +
      'send it again after 00:00 and it goes straight through.';
  },

  proVideoDailyCapReached(cap: number): string {
    return `Video received. That is ${cap} video reads today — the PRO daily ceiling. ` +
      'Bridge resets the counter at midnight IST; ' +
      'send it again after 00:00 and it goes straight through.';
  },

  freeImageCounter(remaining: number): string {
    if (remaining > 1) {
      return `ⓘ ${remaining} of 5 free analyses left. [Upgrade to PRO →]`;
    }
    if (remaining === 1) {
      return 'ⓘ Last free analysis used. [Upgrade to PRO →]';
    }
    return "ⓘ You've used your 5 free analyses. [Upgrade →]";
  },
};
