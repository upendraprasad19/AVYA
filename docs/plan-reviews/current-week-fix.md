---
branch: current-week-fix
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/6d8be947e371-review.md
---

# Plan review — current-week-fix (program week → `user_progress.current_week` + AI snapshot)

## What shipped

`user_progress.current_week` was a dead constant `1` (live: 17/17 users). This batch projects the
derived **program week** (`getProgramWeek`, 1..12) into the column on sync and makes both AI-snapshot
week fields emit it, so the weekly-recap push, weekly report, and coach all agree — with **no Edge
Function redeploy** (the two EFs read the column). All behind the default-ON kill-switch
`disable_program_week_projection`; the OFF path is byte-identical to the pre-fix behaviour. The 1..4
clamp on `getCurrentWeekNumber()` and every in-app display string are UNTOUCHED (that is week-model
work). Diagnose `c9f4a2`.

## Review rounds (ground-truth verified against source + live DB)

- **Round 1 — ×2 context-blind plan review** (before code). Reviewer A: consumer/writer inventory +
  program-week correctness (verdict: SAFE for every consumer). Reviewer B: coherence + scope + tests
  (verdict: sound approach, hardening pass). Both verified against source and the live DB
  (`dedsavbjuwgarrhphgnl`: 0 triggers on `user_progress`, 17/17 rows at 1, no cron/DB-function writes
  `current_week`, `getPromotionStatus` does not read it). All findings folded into the plan:
  program-cap→program-week decision, the drop of the false "streak" claim, the unconditional-write
  (F1) fix, the corrected `getProgramWeek` arithmetic (hand-checked phases 1–7 / lapsed-PRO /
  rank-ladder phase 30 → always [1,12]), and the accepted banner-vs-coach coherence split.

- **Round 2 — B-pass** (`docs/reviews/6d8be947e371-review.md`, verdict: accepted). Fresh
  context-blind Sonnet over the staged diff. Caught a real **P1**: a second writer
  (`_replayPendingOnboardingSync`, `sync_service.dart:1085`) re-wrote the frozen `1` on every boot,
  stomping the projection. Fixed by omitting `current_week` from the replay. Plus a rule-21
  behavioral-coverage gap (fixed by extracting `currentWeekColumnProjection` + a behavioral test),
  two P2 citation/cast fixes, and a P3 shim nit. All 5 accepted + fixed in-batch (§4.2).

## Ground-truth evidence

- Live DB queries run during review (triggers, row distribution, cron readers).
- `getProgramWeek` bounds hand-derived from source (`programWeekFor`, `read_service:884-896`).
- Behavioral test `test/contracts/program_week_projection_behavioral_test.dart` — 8/8 green;
  fail-without-fix demonstrated (revert `:1218` → Expected 7 / Actual 1).
- No EF redeploy (both readers pure-interpolate the column; `captain_manual.ts:317` unchanged).

## Platform-tier artifacts

- `feature_flag`: `disable_program_week_projection` (default-ON kill-switch, byte-identical OFF path).
- `behavioral_test_path`: test/contracts/program_week_projection_behavioral_test.dart.
- `code_review_b_pass`: accepted (see `bpass_review`).
- No migration, no EF deploy → no live-prod-apply gate.
