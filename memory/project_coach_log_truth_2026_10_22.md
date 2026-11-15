# coach-log-truth: the coach stops saying "Logged" before anything is saved (OI-368, OI-369) · 2026-10-22

Branch `coach-log-truth` · PR #145, merged `5cc8c0aa` (main CI green) · plan `docs/plans/coach-log-truth.md` rev 13 ·
record `docs/plan-reviews/coach-log-truth.md` (13 rounds, converged, `bpass: accepted`) · closure
`docs/audit/coach-log-truth.closure.yaml` (28 mutations, all red) · B-pass `docs/reviews/66201d574cf4-review.md`
(0 P0/P1, 1 P2, 7 P3) · diagnose `90a784`.

**Not live yet.** `ai-proxy` and `ai-media-proxy` are not deployed: the founder's go came on 2026-10-22, but the
cloud session had no Supabase deploy token and the MCP deploy tool flattens `_shared/tools/` (deploy skill §6.4).
The deploy runs from local Claude Code. OI-368/369 stay OPEN until the deploy plus the plan §5.7 measurement (the
founder's live check and a next-day read of `ai_coach_interactions` and the `[write-claim-detect]` counts).

## How this batch started

The founder's A12 web walk (2026-10-21) caught two false claims: "Roger. Logged." with no tool call at all
(OI-368), and "Logged." while a LOG SET card still waited for APPLY, then DISMISS (OI-369). Every prompt piece
taught the model a save was instant (`FITNESS DATA LOGGING — INSTANT:`), and the queued tool response said nothing
about wording.

## What shipped

- **L1:** the queued `functionResponse` carries a note: not saved yet, tap APPLY.
- **L2:** both proxies' ICBF blocks move to `_shared/write_claim_prompt.ts`; the header says nothing is saved when
  the coach replies; the rule teaches the founder-approved "Queued. …" lines (the media variant names no tool);
  the meal/template tool descriptions and the day-swap example stop claiming a save.
- **Detector (log only):** `[write-claim-detect]` labels every reply that claims a save or carries a prescribed
  line; it never rewrites a reply and never logs reply text or the user id.
- **Kill switch:** `DISABLE_WRITE_CLAIM_RULE` exactly `"true"` = every piece byte-identical to origin/main
  `37c7498e` (golden recorded by an independent capture script). Removal tracked as OI-374.

## Things worth carrying forward

**1. A server cannot check a claim about what is on the user's screen.** Two review rounds broke the first design
(rewrite the reply server-side) because the server does not know which cards the client is showing. The founder
re-scoped to "teach the truth, measure, and only then add a client-side guard". When a check needs state that only
one side holds, put the check on that side or measure first.

**2. A labeller that stops at the first hit hides the case you care about.** The detector labelled only the first
claim sentence, so "Squat logged yesterday… Done." or "You haven't logged anything yet. Done." looked harmless in
the log line the measurement reads (B-pass P2). It now counts `unsafe_claims` over every sentence. Same family:
normalise before matching (curly apostrophes, wrapped or double-spaced prescribed lines).

**3. Arguments are evaluated before the callee's try.** The detector call sites built their ctx object inline, so
a throw there would 500 after the row was written. The helper now takes a thunk invoked inside its own try. A
"never throws" helper only protects what it evaluates itself.

**4. A kill switch is only as good as its OFF proof.** The OFF golden was captured by a script independent of the
code under test, so "byte-identical when off" is a measured fact, not a claim. Recompute it, do not trust the
fixture you wrote alongside the change.

**5. Decide where the deploy runs before the merge.** The plan named the deploy as a separate founder go but not
the machine. The cloud container had no token, so the go could not be acted on in the same session. Name the
deploy host (local VPS session with the root `.supabase/` token and `.env`) in the plan.

## Open after this batch

OI-368/369 (deploy + §5.7 measurement), OI-374 (remove the kill switch after the measurement), F5 (should the
"Tap APPLY to confirm." line name the confirm sheet; founder copy call, plan §7).
