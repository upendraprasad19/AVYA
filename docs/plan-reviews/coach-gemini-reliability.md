---
branch: coach-gemini-reliability
date: 2026-07-04
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
hermes: accepted
---

# Plan-review record — coach-gemini-reliability (Unit B of the coach-reliability fix-wave)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). This branch is the
**coach (Unit B)** half of the two-merge batch; the restore (Unit A) half lands on its own branch.

## Scope
Six coach fixes surfaced by the live coach walk (test7, 2026-07-04, 9 messages): FC1 (Gemini 2.5
thinking-budget → the coach was silently degraded to Flash-Lite), FC2 (misleading "trouble reaching
the model" over a queued write), FC3 (food-parser had no retry), FC5 (no non-disclosure control),
FC6 (no calorie clamp — a 1M-kcal row could land), FC7 (client `snapshot_json` injected raw at
system trust). Diagnose-docs: 7fbe21 (FC1/2/3), 9c2d4a (FC5/7), 4e8f1b (FC6).

## Review arc (all context-blind; every claim verified against live code + live DB)
- **Round 1 (×2, plan):** correctness lens + risk lens. Both `needs-work`. Caught: per-call
  thinking opt-in (not a shared-default flip — later superseded), the calorie clamp belongs at the
  `logMeal` chokepoint, FC1's Lite-512 fallback trap, the dropped snapshot-injection finding (→FC7),
  FC2 predicate correction.
- **Round 2 (×2, hardened plan):** per-unit. **Refuted my headline restore root cause** (F1 is
  EF cold-start, not serial reads — verified live: test7 near-empty, lightweight step 26.8s) → F1
  moved to Unit A, diagnose-gated. Corrected FC1 opt-in to all 13 Flash callers, FC6 per-item +
  append/edit coverage, FC7 structured-vs-delimit, F3 rescope.
- **Round 3 (bug-introduction, self, verified at fix sites):** caught 4 ways a fix would introduce a
  NEW bug (FC7 consecutive-user-turn 400 → chose delimit-in-place; FC2 exhaustion-message leak; FC3
  retry regressing 17 callers → opt-in param; FC6 3-write-path coverage). Founder chose default-off-
  for-non-Pro (FC1) + delimit-in-place (FC7).
- **B-pass (implementation, fresh Sonnet):** verdict **SHIP** (0 P0/P1). 1 P2 = FC3 retry latency
  ~91s during a Gemini outage → FIXED with a 20s wall-clock deadline in `geminiChat`. Record:
  `docs/reviews/coach-gemini-reliability-bpass.md`.
- **Hermes (cross-lens, Opus):** verdict **ACCEPTED**. Load-bearing systemic question (thinkingBudget:0
  fanned out to 13 Flash callers) resolves in the batch's favour — no cron caller needs thinking
  (every JSON caller uses `jsonMode`; short-copy crons don't reason; Pro exempt). 2 P2 completeness
  gaps FIXED in-batch: restore-path clamp (`_restoreNutritionLogs`), untrusted-data boundary extended
  to coach_memory + retrieval blocks. Record: `docs/reviews/coach-gemini-reliability-hermes.md`.

## Convergence
All review findings fixed in-batch (no deferrals). Pre-commit green (1875 contract tests, all gates,
SoT parity). FC6 behavioral test green; FC1/FC2 Deno tests written (CI). Deploy of `ai-proxy` +
`gemini.ts` is founder-gated (§4.3) and is the live-activation point.
