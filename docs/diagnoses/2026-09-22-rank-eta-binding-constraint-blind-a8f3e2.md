---
bug_id: a8f3e2
date: 2026-09-22
batch: oi-batching-strategy-e5e359 (Batch A)
status: fixed
blast_radius: account
symptom: |
  OI-230 (founder APK screenshot, Phase 1): AI coach snapshot showed
  self-contradictory rank-promotion info — next_rank.binding_constraint
  correctly named the real bottleneck (e.g. "weeks", remaining.weeks: 3)
  while eta_next_promotion simultaneously claimed {days: 0, date: today}.
  OI-231 (founder observed live): coach addressed a promoted SD1 user as
  "Recruit" (the SD2 term).
concept: rank_monotonic_current_code
sot_registry_entry: rank_monotonic_current_code
writers:
  - { file: lib/core/services/rank_service.dart, method_or_widget: "RankService.evaluateAndPromote", line: 138 }
readers:
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method_or_widget: "_getCurrentRankFromLadder / _getNextRankFromLadder / _getEtaNextPromotion", line: 1384 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: user_profile
cloud_columns:
  - current_rank_code
  - current_rank_achieved_at
contract_test_path: test/ai_coach/snapshot_keys_test.dart
ist_handling:
  - "eta_next_promotion's new 'weeks' branch reuses the pre-existing istDateStr(DateTime.now().add(...)) pattern verbatim (not istNow()), avoiding the double-IST-shift class documented in diagnose fe579a."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — pure read-only snapshot builder, no writes, no cross-account surface touched."
forbidden_patterns_checked:
  - "duplicate Hive read of a registered SoT concept instead of calling its canonical reader"
  - "hardcoded ETA fallback branch shadowing a real, computable binding constraint"
proposed_fix: |
  Three sub-fixes in ai_snapshot_builder.dart, all in the rank/eta helper
  family, found and fixed together because each blocked verifying the
  others:

  1. _getCurrentRankFromLadder() / _getNextRankFromLadder() (OI-231 hygiene
     half): replaced direct `_hive.userBox.get('profile')` reads of
     current_rank_code with RankService.instance.getCurrentRank() — the
     canonical reader this concept's own registry entry names. Round-1
     plan review confirmed OI-231's own filed text already anticipated
     this: getCurrentRank() does the identical read/default, so this does
     NOT explain the reported stale-rank symptom by itself — it is shipped
     as the code-hygiene fix OI-231 recommends independently of its root
     cause, which stays open (blocked on live verification).

  2. current_rank_earned_at dead-key fix, found while doing (1):
     _getCurrentRankFromLadder() was ALSO reading Hive key
     `current_rank_earned_at`, which nothing in the repo writes (grepped
     the whole tree — one reader, zero writers). The real writer
     (rank_service.dart:163,175) uses `current_rank_achieved_at`. Now
     reads `RankService.instance.getCurrentRank().achievedAt`, which reads
     the correct key.

  3. _getEtaNextPromotion() (OI-230): rewritten to branch on the ACTUAL
     binding_constraint _getNextRankFromLadder() selects, not a hardcoded
     remaining['workouts'] lookup. Verified live: no kRankGates entry ever
     sets totalWorkoutsAtLeast (rank_service.dart:18-19, F18 2026-06-07),
     so the old code's branch was UNCONDITIONALLY dead — every user with a
     next rank saw a false "promotion today", not merely some users as the
     filed OI-230 text described.
       - binding == 'weeks': deterministic, cadence-independent
         (remaining.weeks * 7 days).
       - binding == 'workouts': unchanged cadence-based math, kept correct
         though currently unreachable (see above).
       - binding == 'streak_days' / 'deployments': honest
         {days: null, date: null} rather than a fabricated date — neither
         is reliably forecastable from a cadence figure.
       - Any rank whose gate carries completionRateMinimum (officer/MCPO
         track: MCPO, SubLt, Lt, LtCdr, Cdr, Capt) also gets the honest-
         null shape UNCONDITIONALLY, regardless of what binding_constraint
         naively resolves to — round 1/round 2 plan review both flagged
         that _getNextRankFromLadder never models completionRateMinimum in
         `reqs` at all, so for these ranks ANY binding_constraint value
         could be masking the real, unmodeled blocker (confirmed live:
         CPO → MCPO's only OTHER requirement is minWeeksSinceSignup, so
         without this guard the fix would have confidently returned a
         deterministic-but-wrong "weeks" answer for every officer-track
         user — worse than the bug it fixes).

  A fourth latent bug in the same reqs.forEach loop was found and fixed
  for streak_days only, needed to make the 'weeks' branch above reachable
  by any real promotion at all (see impact_analysis): `current` was never
  computed for 'streak_days' (hardcoded 0), so remaining['streak_days']
  always equalled the full requirement — meaning streak_days would ALWAYS
  outrank weeks as the binding constraint for every sailor-track
  transition, regardless of the user's actual streak, making the new
  'weeks' branch permanently dead by a different mechanism. Fixed via
  WorkoutRepository.instance.currentStreak() (cheap, synchronous, already
  imported/used elsewhere in this file). `deployments`' identical
  hardcoded-0 pattern was deliberately NOT fixed — it matches
  RankService.getNextRank()'s own documented tradeoff
  (rank_service.dart:439-444: an accurate count needs a network call the
  client-side fast path avoids). Both the completion-rate-gate modeling
  gap and the deployments gap are filed as OI-240 (materially larger,
  separate units of work — new requirement type + adherence-dependent ETA
  semantics), not fixed in this batch.
regression_test_planned:
  - test/ai_coach/snapshot_keys_test.dart
impact_analysis: |
  Client-only, read-only snapshot-building code (AI prompt payload
  construction). No writer touched, no migration, no Edge Function. Blast
  radius: account (ai_coach is explicitly account-tier per root
  CLAUDE.md §4.12.6, not S-eligible).

  Without the streak_days current-computation fix, the new 'weeks' ETA
  branch — while correctly implemented — would have been dead code
  identical in shape to the pre-existing dead 'workouts' branch: every
  sailor-track streak requirement (7/14/30/50) numerically exceeds its
  paired weeks requirement (1/4/12/26) in kRankGates, so with streak's
  `current` hardcoded at 0, remaining['streak_days'] would always equal
  the full (larger) requirement and always win the max-remaining
  selection — 'weeks' could never be selected by any real promotion,
  ever. This was discovered while constructing a realistic test for the
  'weeks' branch (no synthetic/injected ladder data is possible — kRankGates
  is a `const` global) and fixed as part of the same change rather than
  shipping a provably-unreachable branch a second time.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "flutter test test/ai_coach/snapshot_keys_test.dart: 48/48 green. flutter analyze lib/: clean on the touched file." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Behavioral tests seed real Hive rows (userBox['profile'], workoutBox schedule_*/wlog_* keys) via test/helpers/hive_test_setup.dart; no new Hive keys introduced — current_rank_earned_at removed (dead), no replacement key added." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema touched — reads only, and only via the existing UserRepository.getProfile()/Hive path." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "n/a" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "n/a" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "n/a — client-only fix" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "n/a" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "n/a" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "n/a" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "n/a" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "n/a" }
  - { tier: 12, name: "Client → server contract", status: verified, evidence: "eta_next_promotion / current_rank / next_rank remain prompt-passthrough fields (docs/snapshot_contract.yaml) with the same top-level shape; only internal values changed. No captain_manual.ts change in this batch — a null ETA reaching the model untouched is a known residual, noted for a future prompt pass, not blocking this fix." }
mutation_proven:
  mutated: "git checkout -- lib/features/ai_coach/services/ai_snapshot_builder.dart (full revert to pre-fix HEAD), keeping the new/updated tests."
  result: "flutter test test/ai_coach/snapshot_keys_test.dart: exactly 5 of 48 tests reddened — the earned_at test (expected the seeded current_rank_achieved_at value, got the dead-key sentinel instead), the streak-current regression test (expected remaining.streak_days==4, got 7), and all 3 new/rewritten eta_next_promotion tests (streak_days-binding case expected null and got a fabricated 0/today; weeks-binding case expected binding_constraint=='weeks' and got 'streak_days'; officer/MCPO-guard case expected null and got a fabricated 0/today). 0 false positives across the other 43 tests in the file."
  confirmed_applied: "Diffed the reverted file against the fixed backup before and after restore; re-ran the full suite green (48/48) after restoring from the backup copy."
---

## Summary

Two founder-filed OIs (OI-230, OI-231) plus two bugs found while
implementing their fixes, all in the same small function family in
`ai_snapshot_builder.dart` that builds the AI coach's rank/promotion
snapshot fields.

## Root cause

- **OI-230**: `_getEtaNextPromotion()` read only `remaining['workouts']`
  and short-circuited to a fabricated "0 days, today" whenever it was
  absent — which, since no `kRankGate` entry ever sets
  `totalWorkoutsAtLeast`, was **every single time**, for every user.
- **OI-231 (hygiene half)**: `_getCurrentRankFromLadder()` /
  `_getNextRankFromLadder()` duplicated `RankService.getCurrentRank()`'s
  own Hive read instead of calling it — a real SoT-reader violation, though
  round-1 plan review confirmed (by reading `getCurrentRank()`'s source)
  that it reads the identical key/default, so this alone does not explain
  OI-231's reported stale-rank-address symptom. That symptom's root cause
  (stale Hive data vs. a pure model instruction-adherence miss) remains
  genuinely unresolved and needs a live repro — OI-231 stays OPEN.
- **Found while fixing**: `_getCurrentRankFromLadder()` also read a second,
  entirely dead Hive key (`current_rank_earned_at` — zero writers anywhere
  in the repo), and `_getNextRankFromLadder()` never computed a real
  `current` value for the `streak_days` constraint type (hardcoded 0),
  making its `remaining` map — and by extension `binding_constraint` — always
  overstate how far a user is from a streak-gated rank.

## Fix

See `proposed_fix` in the frontmatter for the full four-part breakdown.
Net effect: `eta_next_promotion` now reflects the real binding constraint
(deterministic for `weeks`, honest "cannot estimate" for `streak_days`/
`deployments`/completion-rate-gated ranks), `current_rank.earned_at` reflects
the real achievement date, and `next_rank.remaining.streak_days` reflects
the user's actual streak instead of always showing the full requirement.

A related, larger gap — officer/MCPO ranks' `completionRateMinimum` gate is
not modeled in `_getNextRankFromLadder`'s `remaining` map at all, and
`deployments`' `current` is deliberately left at 0 (matching
`RankService.getNextRank()`'s own network-call-avoidance tradeoff) — is
filed as **OI-240**, not fixed here.

## Verification

- `flutter test test/ai_coach/snapshot_keys_test.dart`: 48/48 green.
- Mutation proof: full revert of the source fix (tests kept) reddens
  exactly the 5 tests that exercise it; 0 collateral failures.
- Two independent context-blind plan-review rounds run before
  implementation (root CLAUDE.md §4.12) — round 1 found 4 must-fix issues
  (missing officer/MCPO guard, wrong OI-231 closure framing, 2 tests that
  would silently break, a bug-history citation gap); round 2 (on the
  hardened plan) found 2 more (OI-228's compound Bug A/Bug B split, the
  cross-branch OI-number collision risk) plus confirmed the 'workouts'
  branch is permanently dead code.

## Files changed

- Modified: `lib/features/ai_coach/services/ai_snapshot_builder.dart`
- Modified: `test/ai_coach/snapshot_keys_test.dart`
- Modified: `docs/sot_registry.yaml` (rank_monotonic_current_code readers)
- Modified: `lib/core/services/CLAUDE.md` (SoT table row)
- Modified: `docs/audit/open_issues.md` / `docs/audit/closed_issues.md` /
  `docs/audit/OPEN_INDEX.md` (OI-230 closed, OI-231 updated, OI-240 filed)
- Created: this diagnose-doc.
