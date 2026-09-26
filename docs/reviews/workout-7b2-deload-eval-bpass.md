---
review: workout-7b2-deload-eval B-pass (7-B-2 triggered-deload eval + un-deload, ship-dark)
branch: workout-7b2-deload-eval
date: 2026-07-17
reviewer: context-blind adversarial subagent (B-pass, §4.3, platform)
blast_radius: platform
verdict: accepted
---

# B-pass — Batch 7-B-2 (triggered-deload eval + un-deload, W2.4)

Context-blind adversarial review of the implemented diff (6 files: 2 new services + the rollover
wiring + a 16-test behavioral proof + SoT + this record's plan-review record) + a live run
(`flutter analyze` clean on all touched files; the behavioral suite green). Branch HEAD == main
`bf2e352b`; diff scope exactly the intended files, no strays.

## Verdict: ACCEPTED — no P0/P1 code findings

All 9 adversarial checks PASS, verified to source:

1. **Flag-OFF byte-identical** — `maybeEvaluate()`'s first two statements are the `enable_triggered_
   deload` + `enable_readiness` guards (pure configBox reads, default false); no Hive write/read/state
   change precedes them → 7-B-1 behaviour preserved (2 flag-off tests confirm).
2. **No unsafe lift path** — `shouldLift = notBackstop && notDeloadPhase && readinessGood &&
   e1rmNoFatigue`, every clause positive-evidence; each of {empty/sparse readiness, zero-compound,
   declining e1RM, unseeded/overdue/future backstop, intended deload phase 4/8/12} resolves to KEEP.
   The Round-1 readiness-vacuous-true defect is genuinely fixed (14-day trailing window + ≥3 entries).
3. **e1RM scan** — per-session representative is MAX Epley over sets (NOT heaviest-by-weight; the
   max-Epley pin test genuinely fails a heaviest-by-weight impl). Compound = EXACT `exercise_type==
   'compound'` via `getByExactName`. Top-2 distinct dated sessions, strict `latest<prior` decline.
4. **Un-deload write** — FULL-row read-modify-write (`Map.from(row)` → every field preserved) via
   `upsertScheduled(planGenerator)` (full-replace + Theme-H completed-guard backstop); row gate
   `status=='planned' && shortened_via==null && is_swapped!=true && date>=today && has-stash` — every
   excluded shape (completed/paused/travel/skipped/swapped/shortened/past) verified to keep. Blob
   dual-write guarded on `week_plans[3].week_character=='deload'`; per-exercise granularity.
5. **Local-only state never syncs** — `last_actual_deload_phase` + `deload_evaluated_for_phase_<N>`
   match no sync fan-out prefix (wlog_/exlog_/schedule_/tmpl_) → never pushed → reinstall-reset safe.
   Idempotency flag SET only on a firm decision → the restore race self-heals (proven).
6. **Durability + repaint** — durability `unawaited`; the awaited eval path is all local Hive I/O (no
   cold-launch block); placed before the invalidation block (repaint); try/catch + recordNonFatal.
7. **COACH-2 + guards** — `generated_via.startsWith('ai_coach')` across all wk4 rows → whole-eval keep;
   cheap-first guard order verified.
8. **Test adequacy** — the max-Epley pin, restore-race keep-and-don't-lock, and flag-off no-op each
   fail if the code were broken (genuine pins).
9. **SoT + record** — accurate; no drift.

## Findings + resolution (all closed IN THIS BATCH — §4.2)

- **P2-A (merge-gate blocker) — CLOSED.** The plan-review record declared `bpass: accepted` +
  `bpass_review: docs/reviews/workout-7b2-deload-eval-bpass.md`, which the keystone gate
  (`check_plan_review_record_exists.dart`, anti-fabrication) requires on disk. THIS file supplies it
  with a line-anchored `verdict: accepted`.
- **P2-B (COACH-2 coverage) — CLOSED.** Added a behavioral test seeding a wk4 row
  `generated_via:'ai_coach_regenerate'` with all lift signals good, asserting the week stays `deload`
  (the whole eval is skipped). A future break of `.startsWith('ai_coach')` now fails a test.
- **P3-A (e1RM recency) — CLOSED.** Added a 35-day recency bound to `DeloadE1rmScan.scan()` (a phase
  is 28d; wk4 evaluates at day 21-27) — stale prior-phase progression no longer reads as current
  "no fatigue"; fewer recent sessions → the ≥2-session gate keeps the deload (safe). New test:
  2 compound sessions both >35d old → keep.
- **P3-B (blob-vs-rows char drift) — CLOSED.** `_liftWeekFour` now early-returns when NO eligible row
  was lifted (all-completed/swapped/past edge) → the blob's `deload` char stays honest + the durability
  sync is skipped. The blob flip only happens alongside ≥1 real row lift.

## Verification after the P2/P3 fixes
`flutter analyze` clean (1 non-fatal info: a justified collection-if). `deload_eval_behavioral_test.dart`
= **16 tests GREEN** (adds COACH-2 + stale-e1RM to the original 14). No migration. Ship-dark.

No open issues.
