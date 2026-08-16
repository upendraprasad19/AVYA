# Free-tier week model ("Hold the Line") — re-scoped project plan

**Date:** 2026-07-20 · **Status:** 🔴 **NOT CONVERGED after review round 2. NOT approved, NOT started.**

> ## ⛔ Round 2 verdict — do not execute this plan as written
>
> Round 2 found **two P0s created by the round-1 corrections themselves**, both inside **A1** — the
> unit designated "foundation, nothing is safe before this," blast `platform`, **default-ON at
> merge**. Both would have shipped live, and both silently disable the previously-shipped `a7d3f1`
> fix. Author re-verified both, including against **live production data**:
>
> **P0-A — the chosen recency signal never advances.** A1 picked `user_progress.updated_at` over
> `plan_json.synced_at`. Live check on `dedsavbjuwgarrhphgnl`: **zero** non-internal triggers on
> `public.user_progress` (`pg_trigger` query), the upsert sends only `{user_id, plan_json}`
> (`sync_workout.dart:1053-1056`), and of **11** rows carrying a plan, **7** have
> `plan_json.synced_at` NEWER than `updated_at`, worst lag **5h48m**. So the cloud side always looks
> older ⇒ local always wins ⇒ the guard silently disables `_restoreWorkoutPlan`'s re-anchor and
> second-device sync. Fix requires either a `moddatetime` trigger migration as a prerequisite unit
> (platform, live-apply gated) **or** using `plan_json.synced_at` with a bounded skew tolerance —
> and either way both readers must widen their `.select('plan_json')`
> (`sync_workout.dart:1090`, `plan_integrity_reconciler.dart:136`), which
> `check_schema_column_refs.dart` gates.
>
> **P0-B — "forward-only `plan_start`" is falsified by the plan's own cited line.**
> `auth_session_bootstrapper.dart:371-380` takes `startDate` from the **cloud** `phase_started_at` —
> a *past* date — and passes it to `generateAndSchedule` (`:383-387`), which writes
> `plan_start = _normalizeToMonday(startDate)` unconditionally (`read_service:149/152`). That is a
> legitimate **backward** write on login-restore, and per `plan_integrity_reconciler.dart:144-149`
> that re-anchor **is** the `a7d3f1` fix. Forward-only would pin `plan_start` to a throwaway local
> value for exactly the reinstall cohort A1 claims to protect.
>
> **Three consecutive rounds have surfaced new material issues** (9 P0s → 8 more → 2 P0 + 3 P1).
> §4.12: *"when successive reviews keep surfacing new material issues, that is the signal the unit is
> too large — split it and ship the smallest converged piece, don't review the large thing a fifth
> time."*
>
> **Recommended smallest converged piece: Unit B (telemetry) ALONE.** `feature` blast, no ordering
> dependency, five event sites verified exact (`plan_expired_card.dart:50/58/61/93/102`), no in-repo
> consumers, and untouched by any of the three rounds. It is also the unit whose own rationale is
> that later units should emit into a sink that already exists.
>
> **A1 cannot be re-reviewed until:** the recency signal is decided (trigger migration vs
> `synced_at`); forward-only is replaced with something that survives
> `auth_session_bootstrapper.dart:371-387`; and the plan states explicitly how the guard interacts
> with the `a7d3f1` heal it currently disables.
>
> **Also still unresolved (round 2, not yet fixed in this document):** `train_provider:822` and
> `reports_screen:1379` escape the D2a/D2b seam and belong in D2a; `train_provider:825` is an
> unassigned sibling of `ai_snapshot_builder:1206`; `generateAndScheduleFromDate` is only
> *conditionally* assigned (itself the §4.2 shape this plan condemns) **and** is F1's unstated
> precondition — a mid-phase regen leaves `plan_start` stale, so F1's `plan_start + 14d` would read
> week-3 rows of a superseded plan; P0-14 (the `graduation_screen.dart:141-142` bare `catch (_) {}`)
> and P0-16 have no disposition; F1/F2 carry no `Closes:` line, so the final ledger is not buildable;
> `phase_roadmap_screen.dart:55/94` is double-assigned to D1 and D2b; F2 carries two contradictory
> Blast declarations; `holdWeek`'s target is not Monday-aligned (`write_service:181-183`), so a late
> hold makes `plan_end` a non-Sunday and hold blocks drift out of phase with
> `getWeek(w) = plan_start + (w-1)*7`; and `write_service:209` should be **`:208`**.
**Input:** [free-tier-hold-findings.md](../../plan-reviews/free-tier-hold-findings.md) (16 P0s, 11 P1s)
**Predecessor:** Unit 0 shipped separately as `cc5dba79` (the two all-users bugs this work surfaced)
**Review round 1:** two context-blind reviewers (ordering/data-integrity; completeness/unit-sizing).
Verdict: **not approvable as drafted.** Every load-bearing finding was re-verified against source by
the author before being accepted — several reviewer claims were themselves corrected in the process.

> ### What round 1 changed (read this before re-reviewing)
> 1. **F1's central safety claim was BACKWARDS.** "Compounding is impossible by construction" — the
>    code does the opposite (`write_service:178/209`). The source-week re-anchor is now the unit.
> 2. **Unit A's guard was unsafe two ways** — `max()` cannot protect `plan_start`, and it creates an
>    *unrecoverable* inflated window on a legitimate shrink. Replaced with a split rule
>    (forward-only `plan_start` / identity-gated recency `plan_end`).
> 3. **Unit A's justification was factually wrong** — `isPhaseExpired()` already self-heals. Damage
>    model re-derived from the real reader set.
> 4. **D2 was the §4.2 violation.** "Split it at review time" forced the founder to ratify an unsized
>    unit. Split now, definitively, at a behavioural seam → D2a / D2b. Same for F → F1 / F2.
> 5. **Two orphans assigned** — P0-15 (Train's expiry branch) → E; the reconciler widening → new A2.
>    Plus `ai_snapshot_builder:1206` → H and `generateAndScheduleFromDate` → D2a.
> 6. **Unit C dissolved** — it fixed a crash that cannot occur; the real streak bug moved to D2a.
> 7. **The ledger topology was unbuildable** — one YAML + 9 branches hard-fails Gate 40 on every
>    commit. Now one branch, ledger in the final commit, one push.
> 8. **Two of three ordering constraints were killed**; one new one (G before/with D2a) added.
> 9. **~8 stale citations corrected** against source (`:1600/1612`→`:1684/1696`, `:601`→`:666`,
>    `:757`→`:822`, event count 3→5, and the rename surface 2 sites→13).

---

## Why this plan is shaped differently

The previous attempt was 5 units, then 8. Round 1 found 9 P0s; round 2, on the *hardened*
plan, found 8 more. That is the §4.12 signal that **the units were too large to converge** — not
that the reviewers were being pedantic. A unit that takes two rounds and still yields new
material findings is a unit whose blast surface exceeds what one review can hold.

So the organising constraint is: **every unit must be small enough to converge in ONE round.**
This draft is **11 units** (A1, A2, B, D1, D2a, D2b, E, F1, F2, G, H — C dissolved). "Converge in
one round" describes the *outcome per unit*; the project as a whole still gets the full ×2 before
any code is written.

The second constraint is **ordering is not cosmetic**. Round 1 killed two of the three ordering
constraints this plan originally claimed and added one I had missed. Only the verified ones survive:

| Constraint | Verified evidence | Consequence of wrong order |
|---|---|---|
| Restore guard (A) **before** any reconciler scan widening | `plan_integrity_reconciler.dart:125` gates all network + all writes behind the 1..4 `needsHeal` scan | Widening makes the `:148-149` culprit fire for hold users who are currently exempt |
| Strip fix (G) **with or before** the un-clamp (D2a) | `read_service:846` is `.clamp(1, 4)`; `week_selector.dart:160-163` renders weeks 5-8 as `_PhaseGroup(isPaywalled: !isPro)` | The moment D2a ships, an existing hold user's **current** week renders as a padlocked "PHASE II (PRO)" chip and `train/screen.dart:211` prints `WK 5 OF 4` |

**Killed by round 1 — do not reinstate:**
- ~~"Streak (C) before the week-model unit"~~ — the rationale was that `last_streak_week`'s domain
  widens before *conversion*, but this plan drops the migration, so there is no conversion. Verified:
  exactly two writers, both int (`train_provider.dart:1696` `currentWeekNum`,
  `simulation_service.dart:150` `-1`), not a cloud column, not in the progress restore path. **No code
  path can put a String there**, so the `as int?` at `:1684` cannot throw. C is dissolved (below).
- ~~"Growth bounds with or before the hold mechanic"~~ — the premise ("the 4-week phase was the
  implicit bound on `plan_json` size") is false: `_syncWorkoutPlan` iterates **every** `schedule_*`
  key with no window filter (`sync_workout.dart:1036-1043`) and always has. Growth is a function of
  app tenure, not holds; `.range(0, 999)` already bites PRO users today. The work stays (real
  pre-existing P1) but carries no ordering claim.

---

## Unit sequence

### A1. Restore/reconciler window guard  ⟵ **foundation, nothing is safe before this**
Closes **P0-1** and the `plan_start` half (P1).

Two writers set `plan_end` **and** `plan_start` unconditionally from the cloud snapshot —
verified exact: `sync/sync_workout.dart:1114-1118`, `plan_integrity_reconciler.dart:148-149`.
Sync is *coalesced*, so a stale snapshot reverts an extension.

**Corrected damage model (round 1 killed the original).** The plan previously claimed a reverted
`plan_end` makes hold rows invisible → `isPhaseExpired()` true → expiry card. **That cannot
happen**: `isPhaseExpiredFrom` (`read_service:936-948`) returns `false` if *any* day in
`_scheduledWorkoutDays()` is on-or-after today, and that scan (`:951-966`) walks **every**
`schedule_*` key with no window bound — it is the documented `a1d4f9` fix, whose own comment says
"a future scheduled workout means the plan is still active even if the stored plan_end_date is
stale." `getWeek(w)` is `plan_start`-derived, so rows don't vanish there either.
The **real** damage: `redoWeek4` derives its source as `plan_end − 6d` and its target as
`plan_end + 1` (`write_service:178/181-183`), so a reverted `plan_end` copies the **wrong week onto
already-occupied dates**. Build and test against that, not the expiry card.

**Shape — recency, NOT `max()`.** Round 1 proved `max()` is unsafe two ways:
1. It cannot protect `plan_start`. The `plan_start` failure *is* a `plan_start` divergence, so an
   identity gate on `plan_start` is false exactly when the guard is needed.
2. It creates an **unrecoverable** inflated window on a legitimate shrink. `generateAndSchedule`
   writes `plan_start`/`plan_end = monday+27` **unconditionally** (`read_service:152-153` —
   verified; contrast `generateAndScheduleFromDate:309-314`, which guards on `isFirstGeneration`),
   and two live paths call it with a start that normalizes to the *current* `plan_start` Monday:
   `train_provider.dart:561-565` (`_autoGeneratePlan`) and `auth_session_bootstrapper.dart:371-390`
   (the login-restore path, which interleaves with the guard). `max(+27, stale +55)` resurrects +55
   forever, and weeks 5-8 then have no rows while the window claims they do. `max()` has no way down.

So: **two separate rules.**
- `plan_start` → **forward-only monotonic**, ungated (it only ever advances: `read_service:152`, `:312`).
- `plan_end` → **identity-gated recency**: prefer whichever side is newer. Write a local
  `plan_window_updated_at` in every `plan_end` writer (`read_service:153`, `:313`,
  `write_service:209`) and compare against the cloud snapshot. Prefer server-authored
  `user_progress.updated_at` (exists — verified in `backups/live_schema_columns.json`) over
  `plan_json.synced_at`, which is raw client `DateTime.now()` (`sync_workout.dart:1050`, not
  `nowWall()`, not IST) and therefore clock-skewable.
- **Delete the old "`synced_at` means no schema change" line** — it described a design that never
  read a timestamp.

**Blast:** `platform` (`lib/core/services/sync/**` → `blast_radius.yaml:63`) → requires
`regression_test`, `behavioral_test_path`, `code_review_b_pass`, `feature_flag`.
**Flag:** `enable_plan_window_guard`, **default ON at merge.** Stated explicitly because round 1
showed it matters: default-OFF would make the guard *and* the D2b boot-heal inert, and the
cross-cutting note "runs behind the same guard as A1" would be vacuous. Default-ON means §4.12.4's
ship-dark tier does **not** apply → **A1 gets the full ×2 review.** Budgeted.
**bpass:** needs a `bpass_review:` companion file under `docs/reviews/` containing a line-anchored
`^verdict: accepted$` — the gate anti-fabrication-checks it exists on disk
(`check_plan_review_record_exists.dart:222-237`).

### A2. Reconciler scan widening  ⟵ strictly after A1
Closes **P0-11**. *(Round 1 caught this as an orphan: the previous draft said "don't bundle the
widening into A" and then gave it to no unit — a §4.2 violation.)*

`plan_integrity_reconciler.dart:125-127` is `for (var w = 1; w <= 4; w++)`, feeding `needsHeal` at
`:128`. Left at 4 after the un-clamp, a hold user whose week-5+ rows lost their exercises never
heals — that is diagnose `a7d3f1`'s exact symptom (REST DAY / no exercises / dead START) resurfacing
for hold weeks. Widening is only safe once A1's guard stops `:148-149` re-anchoring the window.

### B. Telemetry for the hold mechanic  ⟵ early by policy
Closes the "zero telemetry" P1.

`plan_expired_card.dart` logs **five** events (round 1 corrected "three") with **no consumer anywhere
in the repo**: `:50` `phase_1_day_29_expired_seen`, `:58` `…_redo_week_4_tapped`, `:61`
`phase_1_cycle_repeat_started`, `:93` `…_upgrade_tapped`, `:102` `…_template_builder_tapped`. There is
no hold-count, no distribution, no hold→convert/churn instrumentation. Per
`feedback_operational_observability_first`, observability is default-highest-risk on a
solo-founder mobile app and dispatches first — and shipping the retention mechanic blind means we
cannot tell whether it worked.

- Renaming the `phase_1_day_29_*` keys is free **in-repo** (no consumer). Caveat round 1 added:
  renaming orphans historical **cloud** rows from the new keys, so "free" is an in-repo claim only.
- **Blast:** `feature`. Cheap, independent, no ordering dependency. Deliberately early so the
  later units emit into a sink that already exists.

### ~~C. Streak identity tolerant read~~ — **DISSOLVED by round 1**

P0-5 as written fixes a crash that **cannot occur**. Verified: `last_streak_week` has exactly two
writers, both int (`train_provider.dart:1696` `currentWeekNum`, `simulation_service.dart:150` `-1`);
it is not a cloud column and not in the progress restore path; and this plan drops the migration, so
no String shape is ever introduced. The `as int?` at `:1684` cannot throw.

What was real in C survives, re-homed and re-scoped:
- **The actual streak bug under holds** (round 1 named it; the findings doc never did): with
  `getCurrentWeekNumber()` clamped at 4 (`read_service:846`), `currentWeekNum != lastStreakWeek` is
  permanently false for a holder, so **the weekly streak stops incrementing forever**. D2a's
  un-clamp is what closes it. → **owned by D2a.**
- **`completeWorkout` has zero try/catch** in its whole body (`:1434`–end, verified), so a failure
  after `logExercise`/`markCompleted` but before badges/rank/sync/invalidation leaves a written
  workout with no downstream effects. Genuine defensive hardening, no ordering dependency.
  → **owned by D2a.**

### D. Week-number correctness — **pre-split into D1/D2**

**D1 — the hardcoded bounds.** Closes **P0-12, P0-13** (and sets up P0-6).
- `currentPhaseCompletionRate()` hardcoding 4 weeks (`read_service:816-827`), consumers
  `pro_phase_advance.dart:87` + `graduation_screen.dart:591`. The coupling is **real in code, dead
  in production** — both short-circuit behind `PlanEngineFlags.adherenceGateEnabled &&`, default OFF
  (`plan_engine_flags.dart:197`), and `read_service:811` self-documents as INERT. So "D1 precedes E"
  is **conditional on that flag**, not an absolute sequence constraint.
- The 12-week ceiling in four readers: `read_service:714/729/733/820`, **`train_provider:666`**
  (`for (int w = 5; w <= 12; w++)` — previously miscited as `:601`, which is `getProfile()`),
  `train/screen.dart:274`. Hold cap is settled **unlimited** ⇒ move all four.
- `getProgramWeek` (`read_service:895-896`) **plus the display arithmetic round 1 found unowned**:
  `phase_roadmap_screen.dart:55` (`((currentWeek / 12) * 100)`) and `:94` (`isActive: currentWeek <= 4`).
- ⚠ **P0-6 is not a live bug today.** With the clamp in place `getProgramWeek(1)` returns 4 → 33%,
  not the 58% the findings claim. It only materialises *after* D2a's un-clamp. D1 prepares the
  arithmetic; don't send an implementer hunting a symptom that isn't there yet.
- `week_selector.dart:391` **moved out of D1 → G** — otherwise D1 and G edit the same 1040-line file
  on two branches, and G's `feature` blast claim is only valid after D1 lands.

**D2a — the un-clamp, and the consumers where the value ESCAPES or MUTATES.**
Closes **P0-8 (part), P0-9**, the real streak bug, and the `completeWorkout` hardening from dissolved C.
- The clamp itself: `read_service:846` `return (diff ~/ 7 + 1).clamp(1, 4);`
- `deload_evaluator.dart:63` — `if (sched.getCurrentWeekNumber() < 4) return;` is an "exactly week 4"
  guard today; un-clamped, every hold week passes and it **mutates `getWeek(4)`**, a past week. Fix
  here so D2a is self-consistent regardless of flag state. Ship-dark today (`:55-56`, two OFF flags)
  but it collides with decision 2's "deload every 4th hold" — and `docs/ship_dark_pending_review.yaml`
  is **empty**, so nothing would surface the collision at flip time. Register it there.
- `ai_snapshot_builder.dart:88` — leaks the live week into the **AI prompt**.
- `train_provider.dart:1679` — feeds the `last_streak_week` write at `:1696`.
- `completeWorkout` try/catch around the post-write chain (inherited from C).
- **The in-the-wild boot-heal lives HERE, not D1** — D1 touches none of the clamp; D2a is what flips
  the existing cohort's live week from 4 to 5+. Idempotent, keyed, behind A1's flag. ⚠ Its mechanism
  must be specified before review and **must not move `plan_start`**: `pastPhaseBlocks()` counts rows
  strictly before `plan_start` (`read_service:1023`) and `PhaseProgressReconciler` monotonically
  writes `current_phase` from that count, so a heal that advances `plan_start` re-creates the
  unrecoverable over-advance.
- **Breaks** `workout_schedule_read_path_behavioral_test.dart:145/168/188` and the *behavioural*
  `test/contracts/deload_eval_behavioral_test.dart` (real week-4 Hive fixture + `plan_end_date`).

**D2b — read-only display consumers.** Closes the rest of **P0-8**.
`home_screen.dart:311`, `profile_provider.dart:330`, `reports_screen.dart:1379`,
`train_provider.dart:593/799/822` (`:822` is `SelectedWeekNotifier.build` — previously miscited as
`:757`, a doc comment), `phase_roadmap_screen.dart:55/94`, and the two pure facades
`workout_schedule_service.dart:166` / `workout_repository.dart:488`.

> **Why D2 was split — and why the previous draft's version was a §4.2 violation.** Round 1 measured
> the un-split D2 at **10 files across 5 feature areas** (`core/services`, `ai_coach`, `home`,
> `profile`, `train`) — the *identical* set the findings doc already rejected as un-convergeable. The
> previous draft said "if D2 still feels too wide at review time, split it by consumer cluster,"
> which is a deferral wearing a scheduling hat: it forces the founder to ratify an unsized unit in
> order to approve the plan at all. The seam is **behavioural** (the value escapes/mutates vs. it is
> merely displayed), not a "consumer cluster".

### E. Advance-gate consent
Closes **P0-3, P0-10**, and the intent-flag P1.

- Relaxing the `isPhaseExpired()` predicate is **inert** (second guard at `read_service:473`
  returns `generated:false`) **and unsafe** (that guard is the documented cross-launch idempotency
  anchor — splash fires the call unawaited every launch; `_advanceInFlight` is in-flight-only).
- Needs a **consent-gated idempotency key, not a boolean and not a predicate change**.
  Consume-after-success leaks (generation writes the window *before* the 28 day-rows, so process
  death mid-generation leaves the flag unconsumable); consume-before burns consent on any failure.
- **Three advance paths**, not one: `pro_phase_advance.dart`, splash auto-advance, and
  `graduation_screen._onPro` (`:566/:648/:672`) which writes `current_phase` without ever touching
  `isPhaseExpired()`.
- Precedent to copy: `phase_repeat_nudge_pending` (`pro_phase_advance.dart:136-140`, cleared
  `home_provider.dart:938-957`, registered `user_config_migrator.dart:82-84`) — including its
  `HiveUserSession.currentOwnerFullId != null` cross-account belt at `:137`.
- 🔴 **P0-15 assigned here — it was orphaned in the previous draft** (the same failure mode that
  helped kill the last plan). `lib/features/train/screens/train/screen.dart:152` —
  `(WorkoutScheduleService.instance.isPhaseExpired()` — is the **Train tab's** expiry branch, the
  primary surface a holding user actually lives on. The previous draft cited `screen.dart:274` and
  `:211` but never `:152`. Pinned by `test/contracts/train_expired_state_test.dart:32-33`
  (`reason: 'Train must gate the hero slot on isPhaseExpired, like Home'`).
- Home has a second blocker — `if (schedule == null && isPhaseExpired())`
  (`home_screen.dart:743-744`); during a hold `schedule != null`, so relaxing only the expiry half
  leaves Home with no affordance at all.
- ⚠ **Correction to the previous draft:** it claimed
  `pro_phase_expiry_surface_test.dart:75/77/92/94/102` "cannot survive the redesign." All five lines
  are correct, but all five are source-grep `contains` checks, and E's own design explicitly does
  **not** relax the predicate — so `.isPro()`, `.isPhaseExpired()`, `advanceProPhaseIfExpired(ref)`
  and `reason: 'splash_auto_advance_phase'` all survive. Do not budget a rewrite that isn't needed.
- **Closes:** P0-3, P0-10, **P0-15**.
- **Blast:** `account`.

### F1. The hold mechanic  ⟵ **the source-week re-anchor is the whole unit**

> 🔴 **Round 1 overturned this unit's central safety claim.** The previous draft said: *"Compounding
> is impossible by construction because holds source the phase's canonical week, never the previous
> hold."* **That is exactly backwards.** Verified at `workout_schedule_write_service.dart:172-209`:
> ```dart
> final week4Start = planEnd.subtract(const Duration(days: 6));   // :178  source ← plan_end
> ...
> final newEnd = rollStart.add(const Duration(days: 6));
> await MigratedKey.write(_planEndKey, newEnd.toIso8601String()); // :209  then ADVANCES plan_end
> ```
> The source is derived from `plan_end`, and the method then advances `plan_end`. **Hold #2 sources
> hold #1's copied rows.** It compounds *by construction*. Layer decision 7's reduce-only decay on
> that chain and loads decay **geometrically toward zero** — a silently degrading plan.
>
> A second, independent defect in the same three lines: the source is the window's **last** week
> (week 4, the *deload*), but locked decision 2 says the hold is **Peak (week 3)**. The existing
> mechanic does not implement the locked design.

**Therefore the re-anchor is not a detail — it is the unit.**
- `holdWeek()` computes its source as **`plan_start + 14d`** (canonical Peak, phase-relative),
  **independent of `plan_end`**. This simultaneously implements decision 2 *and* restores the
  no-compounding property that decision 7's safety rests on.
- **Required behavioural test:** hold *N* and hold *N+1* produce **byte-identical source rows**.
  Without this, the compounding regression is invisible.
- Decay-at-copy (decision 7), reduce-only — safe **only** once the re-anchor is in. State the
  dependency in the code comment so a later refactor can't silently reintroduce `plan_end` sourcing.
- **Clock seam:** adopt `nowWall()` (raw `DateTime.now()` at `write_service:179` — verified),
  release-identical, no existing caller or test affected. Without it neither "hold sourcing" nor
  "`plan_end` stays a Sunday" is deterministically testable.
- **Concurrency (lens L27, never applied):** `holdWeek` is a get→modify→set on shared state with no
  lock, racing the splash's unawaited advance. `upsertScheduled` holds a per-date lock but the
  `plan_end` write sits *outside* it.
- **Rename surface is 3× what the previous draft claimed.** Beyond `graduation_screen.dart:140-147`
  (bare `catch (_) {}` that swallows failure and navigates anyway): the facade
  **`workout_schedule_service.dart:231-232`**, the primary caller `plan_expired_card.dart:60`,
  **seven** `sot_registry.yaml` sites (`:4846, :5939, :6096, :6098, :6101, :6103, :6105` — `:6105` is
  the forbidden-pattern regex that would silently stop matching), and stale doc comments at
  `service_providers.dart:121`, `workout_schedule_read_service.dart:8`,
  `workout_schedule_service.dart:10`, `workout_schedule_write_service.dart:8`.
  **Breaks** `workout_schedule_split_invariant_test.dart:46`.
  (`scripts/check_workout_schedule_split.dart:11` does **not** break — header comment only.)
- **Blast:** `account`.

### F2. Growth bounds  ⟵ independent; no ordering claim
Pre-existing P1s that holds make more visible but do **not** cause (see the killed constraint above).
- `.range(0, 999)` with no pagination truncates restore at ~1000 rows ≈ 2.74 years, **ascending**
  (`sync/sync_workout.dart:1795-1807`), so past the threshold the **current** phase is what gets
  dropped. Every sibling paginates properly (`sync_community.dart:473/497`, `sync_nutrition.dart:567`).
- `_syncWorkoutPlan` serialises every `schedule_*` key into one `plan_json` on every push with no
  window, cap or chunking (`:1036-1056`); nothing prunes `schedule_*`.
- **Blast:** `platform` (`sync/**`) → owes `feature_flag` + `bpass` + `bpass_review` companion,
  same as A1.
- **Blast:** `account`, rising to `platform` via the `sync/**` growth work — likely split F into
  F1 (mechanic) / F2 (growth bounds) at review time.

### G. The week strip UI
Closes **P0-4, P0-7**, and the legibility risk in decision 3.

- `WeekSelector.totalWeeks` is **dead code** — declared, passed from `screen.dart:274`, never
  read. Deriving it fixes nothing. The strip hardcodes `_PhaseGroup` ranges 1-4 / 5-8
  (`isPaywalled: !isPro`) / 9-12, which is why free hold weeks render as padlocked "PHASE II (PRO)"
  chips.
- `H n` / `O n` chips, `PHASE I · HOLDING` group header, date on the **selected** chip only.
  **`O` vs `0` is a real legibility risk at 12px** — use the tool glyph or `C n`; decide before
  building.
- `PHASE II` stays pinned at W5-W8 so the 12-week roadmap never drifts.
- `_PastPhaseGroup`'s `for (var w = 1; w <= 4; w++)` (`week_selector.dart:391`) **moved here from
  D1** — one unit owns this file.
- **Breaks — the previous draft named 2 of 6.** Verified casualties:
  - `phase_relative_week_label_test.dart:62` (hard-pins `'WK ${plan.currentWeek} OF 4'` — ship it and
    you print "WK 5 OF 4")
  - `week_selector_past_phases_test.dart:57/72-78` (pins `'~/ 28'`, asserts `'PHASE II'` absent)
  - 🔴 **`scripts/check_week_selector_phase_labels.dart` — a PRE-COMMIT GATE, not a test.** It
    hard-requires `this.currentPhase` and `_phaseRoman(widget.currentPhase` to survive and **bans**
    `label: 'PHASE I/II/III'`. A gate failure blocks the commit outright, so this constrains the
    strip's design, not just its tests. Must be updated in the same commit.
  - `week_selector_reads_current_phase_test.dart:21/25/27-29/33/37` (same constraints as the gate,
    plus `currentPhase: plan.phase` in `screen.dart` and `pastPhaseBlocks()`)
  - `week_completion_check_test.dart:50/55` — `expect(src.contains('service.completedWeekNumbers()'))`
    and `hasCompletedDay: completedWeeks.contains(w)`; both read `week_selector.dart` source, which
    this unit rewrites. (Listed in the findings' breaking-test table but owned by no unit in the
    previous draft.)
  - `train_expired_state_test.dart` — see E (P0-15).
  - Lower-risk, likely survive but re-check: `test/home/week_number_test.dart:18/22/27/31`,
    `plan_expiry_respects_schedule_test.dart`, `repeat_content_scheduling_test.dart:274/286`,
    `phase_unlock_start_date_test.dart`.
- **Blast:** `feature` — but only **after D1 lands**; G rebases on D1.

### H. Stale `current_week` surfaces  *(renamed from "Server-side surfaces" — round 1: a client
reader falls inside this concern and belonged to no unit)*
Closes the `user_progress.current_week` P1 and the `getPromotionStatus.ts` P1.

- `user_progress.current_week` is **permanently 1** — all 8 writers set the literal or echo it, none
  advances it — yet `weekly-report/index.ts:460` feeds it to Gemini and
  `weekly-recap-ready/index.ts:190` pushes "Week 1 debrief ready". A holder sees "WK 16" in-app
  and "Week 1" in the push.
- 🔴 **`ai_snapshot_builder.dart:1206` assigned here** — `final week = (progress['current_week'] as
  int?) ?? 1;` is a **client** reader of the permanently-1 DB value. It fell between H
  ("server-side") and D2a (which owns `:88`, a *different* field — the live
  `getCurrentWeekNumber()` write). Net effect today: **the same AI snapshot carries a live week at
  `:88` and a frozen 1 at `:1206`.**
- `getPromotionStatus.ts:144-158` derives `deploymentsComplete` from a **stale comment** claiming
  columns don't exist (they do — migration 081) and uses a **non-monotonic** `current_phase - 1`,
  diverging from both client and cron.
- **Blast:** `platform`. Edge Function deploy → **needs its own explicit founder go** at apply
  time (§4.3), separate from plan approval.

---

## Cross-cutting, not a unit

- **P0-2 (phantom phases → unrecoverable `current_phase` over-advance)** has a subtle trigger:
  it only materializes **after** a phase advance moves `plan_start` — during a hold, hold rows are
  not "past" rows. A test written to the wrong trigger passes while the bug survives. Owned by
  **E** (the advance unit), tested at the advance boundary.
- **Do NOT stamp `phase` on hold rows.** `bucketPastRows` finds the *first* stamped row and
  carry-forwards (`read_service:1049-1060`), so one stamped row flips a legacy multi-phase user's
  whole set into one collapsed block — and it is a **no-op for modern installs** (the generator
  already stamps `phase` at `:399/:428` and the copy preserves it). Opposite of the intended effect.
- **Boot-heal — reassigned D1 → D2a** (round 1: D1 as scoped touches none of the clamp; **D2a** is
  what flips the existing cohort's live week from a clamped 4 to 5+, so the heal must ride with D2a).
  Covers extended `plan_end` with untouched `plan_start`, non-Sunday `plan_end`, orphan rows. Runs
  once at boot behind A1's flag, idempotent, keyed so a re-run is a no-op. Full spec lives in D2a —
  including the hard constraint that it **must not move `plan_start`**.
- 🔴 **`generateAndScheduleFromDate` is an unowned hole that holds make systematic.** It deletes
  every non-completed row across `[today, plan_end]` (`read_service:285-304`) but writes
  `plan_start`/`plan_end` only when `isFirstGeneration` (`:309-314`), and materialises only 4 weeks.
  With a hold-extended `plan_end`, an **Edit-Profile regen wipes days 29..N and leaves them orphaned
  inside a window that still claims them.** No unit in either draft mentions this method. Assign it
  to **D2a** (same cohort, same window semantics) or give it its own unit before approval — it must
  not stay unowned.

## Discipline artifacts (the previous plan lacked all of these)

### 🔴 Branch/ledger topology — the previous draft was structurally unbuildable

The previous draft proposed **one** project-level closure YAML **and** "each unit gets its own
branch." Round 1 proved these are mutually exclusive against the live gate:
`validate_audit_closure.dart:305-312` computes `nonTerminalCount = findings.length - closedTally` and
fails **unconditionally** — it is *not* `--strict`-gated (contrast `:256-263`, which is) — and the
validator auto-discovers every `docs/audit/*.closure.yaml` (`:79-81`). It is wired into
`scripts/pre-commit.sh:98` **and** `.github/workflows/test.yml:155`. So the moment a 9-unit ledger is
committed, **every commit and every CI run fails** `closed == N FAIL: 1/9` until the final unit lands.

**Resolution — one branch, sequential commits, one push:**
- **ONE branch** `free-tier-week-model`, units land as sequential commits on it.
- **Each unit is reviewed independently before its commit lands** — that is what keeps review units
  small. The "converge in ONE round" thesis is about the *outcome per unit*, not about running a
  single round for the project.
- **The closure YAML is written in the FINAL commit**, all entries terminal. Nothing is ever
  committed non-terminal, so Gate 40 never sees a partial ledger.
  ⚠ Do **not** mark unstarted units `blocked_on_user` to get green — that is a deferral in ledger
  clothing.
- **ONE merge to `main`, ONE plan-review record** (`docs/plan-reviews/free-tier-week-model.md`)
  documenting every round, **ONE push**. This also satisfies §4.3's consolidation rule, which the
  previous 9-branch/9-push design violated: A1, D1, D2a, D2b have **no standalone user-facing
  value**, and §4.3 bans exactly that splitting reflex.
- Ledger schema requirements round 1 verified and the draft omitted: `closed_count:` must match the
  terminal tally (`:181`); `total_findings:`/`total:` must be within 3 of the list length
  (`:315-318`); every `closed_in_commit` needs **both** a `commit:` and a `verification:`/`notes:`
  field (`:273-279`).

### Other artifacts
- **A diagnose-doc per `fix:` commit** (≥6 more).
- **`bpass_review:` companion is mandatory, and anti-fabrication-checked.**
  `check_plan_review_record_exists.dart:222-237`: `bpass: accepted` without a `bpass_review:` path
  that **exists on disk** and contains a line-anchored `^verdict: accepted$` is a hard fail. The
  previous draft wrote `bpass: accepted` and never mentioned the companion file under `docs/reviews/`.
- **`feature_flag` + `bpass` are owed by more than A1.** `blast_radius.yaml:23-25` — `platform`
  requires `[regression_test, behavioral_test_path, code_review_b_pass, feature_flag]`. That covers
  **A1, F2, and H** (all platform), not A1 alone as the previous draft implied.
- **SoT registry — 5 concepts**, two with text that becomes factually false:
  `workout_schedule_read_path:5893` (its description owns `getCurrentWeekNumber`; `:5923` `fields_read`
  literally reads "computed week-1-to-4 from plan_start_date"), `workout_schedule_write_path:5934`
  (names `redoWeek4`), `week_completion_check:2127`, `template_scheduling:6144`,
  `phase_progress_current_phase:5949`.
- **Ship-dark tiering is NOT validly claimable** for the hold units: §4.12.4 requires a behavioural
  test proving byte-identical output when OFF, which is impossible when the fix *is* the behaviour
  change. (Round 1 confirmed this reasoning is sound; only the 9-branch conclusion drawn from it was
  wrong — see the topology fix above.)
- **Templates:** keep the door, fix the dead end, cap optional (decision 8). Accurate framing —
  `template_builder_screen.dart:417-421` *does* surface a zero-writable-days message and the
  template still saves; the skip is at `:405`, and `const maxWeeks = 4` at `:391` caps scheduling
  independently of `plan_end`. The TRAIN-17 "PRO" charter is unenforced in code; treat the charter
  as stale, not the code.

## Settled — do not re-open

- **Hold cap: unlimited.** Locked decision 4 ("unlimited, with a nudge"). Therefore D1 **moves all
  four** 12-week readers rather than capping at 8. Capping is not a live option.

## One genuine open design question

- **`O n` glyph legibility.** `O` vs `0` at 12px in the chip strip is a real confusion risk that
  the reviews flagged. **Recommendation: keep `H n` for hold and use `C n` for the deload
  ("consolidation") chip** — two unambiguous letters, same width budget, no glyph dependency, and
  it preserves the founder's H/O space-saving intent. Falls to G; does not block A–F.
