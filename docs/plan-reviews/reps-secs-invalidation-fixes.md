---
branch: reps-secs-invalidation-fixes
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/2d63662f9e59-review.md
tier: account
date: 2026-09-28
---

# Plan review — reps-secs-invalidation-fixes

**Scope:** the founder-approved batch fixing 4 originally-confirmed bugs
(duration-controller seeding leak, e8f95e; aggregate pre-normalization,
`workout_write_service.dart`; missing `streakFreezeProvider` invalidation,
9c8958; missing `weeklyNutritionProvider` invalidation, bae4dd) plus a
foreground midnight-timer backstop for `DayRolloverObserver`
(`test/contracts/day_rollover_midnight_timer_test.dart`). The founder's own
open-ended audit framing ("check where all should be using invalidation...
possible areas we might have missed it") led two independent plan-review
rounds to each surface MORE instances of the exact same bug class before
implementation converged — `weeklyReportDataProvider` (b1bfea),
`referralEligibilityProvider` (4018b3), and `usageWeeksProvider` (ff3131) —
all fixed in the same batch per CLAUDE.md §4.2's no-deferrals policy rather
than tagged lower-priority.

**Blast radius: account.** Confirmed live, repeatedly, via
`git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -`
→ `Blast-radius: account` (touches `lib/core/services/day_rollover_service.dart`
and `lib/core/services/workout_write_service.dart`, both under
`lib/core/**`).

## Round summary (2 independent context-blind plan-review rounds)

- **Round 1**: reviewed the founder-approved plan for the original 4 bugs +
  timer backstop. While independently verifying a separate finding the same
  round raised about `UserStatsNotifier.currentStreak` (ultimately RULED
  OUT — see below), the reviewer separately found `weeklyReportDataProvider`
  had NO invalidation anywhere in the app (worse than the other 3 — no
  write-time leg either), identical bug shape. Fixed directly (rollover
  leg); the separable write-time leg (3 domains, 15+ raw call sites, no
  `WidgetRef` inside the plain WriteService methods) filed as **OI-267**
  rather than silently expanded into this batch.
- **Round 2**: an independent audit from a DIFFERENT starting angle — every
  top-level `Provider`/`NotifierProvider` under `lib/features/*/providers/`
  that computes from `DateTime.now()`, cross-checked against
  `day_rollover_service.dart`'s invalidation list — found TWO more
  instances: `referralEligibilityProvider` (4018b3) and
  `usageWeeksProvider` (ff3131). Both already had a working write-time
  invalidation call site (unlike weeklyReportDataProvider), so both were
  simple one-line rollover-leg additions, fixed directly with no fan-out
  complexity.

**UserStatsNotifier false positive, independently re-verified twice:**
Round 1's reviewer claimed `UserStatsNotifier.currentStreak`
(`WorkoutRepository.instance.currentStreak()`, a direct function call, not
`ref.watch`'d) had no rollover-linked invalidation. Verified FALSE by
reading the actual watch chain: `UserStatsNotifier.build()` does
`ref.watch(weekIdentityProvider)`, which itself does
`ref.watch(currentPlanProvider)` — which day-rollover DOES invalidate. So a
rollover invalidates `currentPlanProvider` → cascades through
`weekIdentityProvider` → cascades through `userStatsProvider`'s own watch →
the entire `build()` reruns, recomputing `currentStreak` fresh as a side
effect. Round 2's independent audit, working from a different angle,
re-traced the identical chain and confirmed the same ruling. No fix needed.

## Ground truth verification (this record's own, not just the reviewers')

Every writer/reader pair named in this batch's 6 diagnose-docs was
independently confirmed by direct `Read` against the real files — not
trusted from subagent prose — including a full re-derivation of the final
27-provider `_doRolloverWithRef` invalidation count
(`sed -n '152,296p' day_rollover_service.dart | grep -c 'ref\.invalidate('`
→ 27; breakdown workout 7 + nutrition 6 + health 3 + profile 3 + AI 3 +
misc 5).

Two B-pass rounds ran against this batch:

1. `docs/reviews/b6f1837bf486-review.md` (accepted) — ran against the
   state after the original 4-bug + timer-backstop fixes. 3 findings, all
   resolved: F1 corrected a diagnose-doc's false "tracked via mint_oi.sh"
   claim by actually filing the real OIs (OI-265, OI-266); F2 fixed a
   hardcoded test-cap that should derive from `subscriptionInfoProvider`;
   F3 accepted as non-blocking with no code change.
2. `docs/reviews/2d63662f9e59-review.md` (accepted) — ran against the
   FULL final diff, including round 2's two additional fixes. **3 findings,
   ALL mechanical/citation-class — the §4.12.6 convergence signal**: F1
   (P2) found 8 off-by-one line citations across the 5 new diagnose-docs
   and `sot_registry.yaml` (two of which had already been "corrected" once
   earlier in this batch, by the SAME flawed derivation method, landing
   one line short of correct both times) — all 8 independently re-verified
   against the real files by this record's own author before being fixed;
   F2 (P3) found a stale "~24-provider" count in 2 files, corrected to 27;
   F3 (P3) was purely informational (this record's own existence was the
   resolution). No design defect, no new bug-class instance, no writer/
   reader drift — the review found citation accuracy issues in documents
   describing already-correct code, not defects in the code itself. Per
   CLAUDE.md §4.12.6's `mechanical_only: true` convergence shortcut: this
   round's findings were entirely mechanical, which is the signal this
   batch has converged rather than needing a third round.

Also independently re-verified (not trusted from either B-pass's prose):
mutation-proofs for all 3 `presence_only: true` providers' regression tests
(deletion, not comment-out — a `//`-prefixed line still contains the
checked substring) and Test F (`weeklyReportDataProvider`) — all reddened
exactly as each diagnose-doc claims.

## Verification state at record time

- Full pre-commit gate loop (`sh scripts/pre-commit.sh`): green, including
  Gate 40, Gate-SDB, Gate-DEU, and the tech-debt audit bundle. Blast-radius
  printed `account` on every run.
- `flutter analyze lib/` (whole-tree): 45 pre-existing `info`-level issues,
  0 warnings/errors, 0 new issues introduced by this batch (ran in 4.1s).
- Full `flutter test` (`TZ=Asia/Kolkata`, reading the log's own content
  directly rather than the background-task notification's exit-code field
  — see `memory/feedback_background_task_exit_code_is_last_command.md`):
  **6671 passed, 9 skipped, 2 failed.** Both failures
  (`test/goldens/wardroom/ward_rank_pill_golden_test.dart`, "Lt collapsed
  golden" + "SD1 collapsed golden") are pre-existing, environment-sensitive
  golden pixel-diffs (0.00%, 10px diff — anti-aliasing-level, not a logic
  assertion) confirmed UNRELATED to this batch: `git diff --cached
  --name-only | grep -i "rank_pill\|wardroom"` → zero hits, and this is the
  identical pair of failures already identified and confirmed unrelated
  earlier in this same session, now reproduced a second time after
  substantial unrelated changes in between.

## Out-of-scope discoveries, filed rather than fixed

- **OI-265**: boot-time healer needed for pre-existing `exlog` rows
  corrupted by the duration-controller seeding leak (e8f95e), before its
  fix.
- **OI-266**: `_resolveLoggingType` never consults `customBox`/
  `user_custom_exercises` for a custom exercise's logging type — a
  pre-existing gap found investigating e8f95e, not caused by its fix.
- **OI-267**: `weeklyReportDataProvider` has no write-time invalidation
  across weight/meal/workout logs (3 domains, 15+ raw call sites) — only
  the day-rollover leg was added in this batch; see Round 1 above.
