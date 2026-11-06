# Free-tier "Hold the Line" — review findings (input to the re-scoped project)

**Date:** 2026-07-20 · **Status:** input document, not a plan
**Provenance:** two independent context-blind review rounds (3 reviewers round 1, 2 round 2)
over a proposed 5→8-unit plan to generalize a training phase from a fixed 4 weeks to 4+N weeks.

**Outcome:** round 1 found 9 P0s; round 2, on the *hardened* plan, found 8 more — including a
correction that was still false. Per §4.12 ("when successive reviews keep surfacing new material
issues… split and ship the smallest converged piece"), the founder split the batch: **Unit 0
shipped** (diagnoses `a3c8e2`, `b7f30a`); the week-model work is **re-scoped as its own project**,
seeded by this document.

> Every finding below was verified against source by a reviewer. Line numbers are as of
> `main` @ 2026-07-20 and will drift — re-verify before relying on any of them.

---

## Product decisions already made (founder, during the brainstorm)

These are settled and should carry into the re-scope:

1. **Phase genuinely extends** to 4+N weeks (not re-anchored).
2. **Hold week = Peak (wk3), with an auto-deload (wk4) every 4th hold.** Loads stay fixed, so
   "progression" remains the PRO differentiator. Grounded in research: an indefinitely repeated
   deload sits at ~Maintenance Volume (below MEV) and structurally cannot produce adaptation; the
   Delphi consensus defines a deload as *transitional*. No researched competitor loops one week.
3. **Naming: `H n` / `O n` chips** (short, matching `W n` width), date on the **selected** chip only
   (it is the only thing distinguishing H1 from H5), `PHASE I · HOLDING` group header to teach the
   letter once. `PHASE II` stays pinned at W5-W8 so the 12-week roadmap never drifts.
   ⚠ `O` vs `0` is a real legibility risk at 12px — use the tool glyph or `C n`.
4. **Unlimited holds + a non-shaming nudge** (Strava precedent: always count activity, always award
   achievements, gate only the rank comparison).
5. **Rank: leave the emergent free ceiling (LS) and state it explicitly. NO rank-engine change** —
   this deliberately avoids client/server divergence.
6. **Lapsed PRO holds at their last phase** (already supported: the gate covers *generation* only).
7. **Detraining: decay hold loads at copy time** (reduce-only). Compounding is impossible by
   construction because holds source the phase's canonical week, never the previous hold.
8. **Templates: keep the door, fix the dead end, cap optional.** The TRAIN-17 "PRO" charter is
   unenforced in code — treat the charter as stale, not the code.
9. Low-adherence users holding a Peak week they never trained: **accepted**, no branch needed.

---

## P0 findings

| # | Finding | Evidence |
|---|---|---|
| P0-1 | **Restore collapses an extended phase.** Two restore-path writers set `plan_end` unconditionally from the cloud snapshot. Sync is *coalesced*, so a stale snapshot reverts the extension → hold rows fall outside `[plan_start, plan_end]` → invisible → `isPhaseExpired()` true → user thrown back to the expiry card. **Round 2: no unit owned this.** Also note `plan_start` is written unconditionally at the same sites, and `getCurrentWeekNumber` derives from `plan_start` *alone*. | `sync/sync_workout.dart:1114-1118`, `plan_integrity_reconciler.dart:148-149` |
| P0-2 | **Phantom phases → unrecoverable `current_phase` over-advance.** Legacy installs have unstamped rows → 28-day bucketing fallback → a 28-week Phase 1 buckets into 7 blocks → the reconciler monotonically writes `current_phase` 2→8 (its own comment: "unrecoverable"). ⚠ Round 2 correction: this only materializes **after** a phase advance moves `plan_start` — during the hold, hold rows are not "past" rows. A test written to the wrong trigger would pass while the bug survives. | `workout_schedule_read_service.dart:1041/1083-1102`, `phase_progress_reconciler.dart:79-86`, `:1023` |
| P0-3 | **PRO advance gate: relaxing it is inert AND unsafe.** A second expiry guard returns `generated:false`, so relaxing the first is a no-op. And that guard *is* the documented cross-launch idempotency anchor — splash fires the call unawaited every launch; `_advanceInFlight` is in-flight-only. Predicate relaxation ⇒ silently advancing a user out of a deliberate hold, and unbounded phase skipping, each bump permanently raising `deployments_complete`. **Needs consent-gated one-shot intent, not a predicate change.** | `pro_phase_advance.dart:30-35/62`, `workout_schedule_read_service.dart:473`, `user_repository.dart:91-94` |
| P0-4 | **Free hold weeks render as padlocked "PHASE II (PRO)" chips.** `WeekSelector.totalWeeks` is **dead code** (declared, passed, never read); the strip hardcodes `_PhaseGroup` ranges 1-4 / 5-8 (`isPaywalled: !isPro`) / 9-12. Deriving `totalWeeks` changes nothing. | `week_selector.dart:35/147-176`, `screen.dart:274` |
| P0-5 | **Streak identity change crashes `completeWorkout` for every existing user.** `last_streak_week` is read `as int?`; a date-String throws — and `completeWorkout` has **no try/catch**, so it dies *after* `logExercise`/`markCompleted` wrote but *before* badges, rank, sync and invalidation. ⚠ Round 2: a migration is **net-negative** (deriving the date key needs `plan_start`, which may have moved; a wrong key can silently block a legitimate increment). A shape-tolerant read alone is self-healing. Hive-local only — no cloud column. | `train_provider.dart:1600/1612`, `simulation_service.dart:150` |
| P0-6 | **`getProgramWeek` corrupts the 12-week roadmap.** A free Phase-1 holder at hold 3 reports program week 7 → Phase II shown active at "58% complete"; hold 8 → "100%". Reachable directly from the expiry card. | `workout_schedule_read_service.dart:895-896`, `phase_roadmap_screen.dart:52-55/94` |
| P0-7 | **An existing contract test hard-pins the banner** `'WK ${plan.currentWeek} OF 4'`. Either ship "WK 5 OF 4" or redden the suite (rule 20 = P0). | `screen.dart:211`, `test/contracts/phase_relative_week_label_test.dart:62` |
| P0-8 | **The un-clamp has 11 consumers.** `ai_snapshot_builder.dart:88` (leaks into the **AI prompt**), `deload_evaluator.dart:63`, `train_provider.dart:528/734/757/1595`, `workout_schedule_read_service.dart:896`, `home_screen.dart:309-316`, `profile_provider.dart:330`, `reports_screen.dart:1379`, `workout_repository.dart:488`. Note `train_provider.dart:757` (`SelectedWeekNotifier.build`) bypasses the tap predicate entirely. | as listed |
| P0-9 | **`deload_evaluator` guard flips meaning.** `if (getCurrentWeekNumber() < 4) return;` is an "exactly week 4" guard today; un-clamped, *every* hold week passes it and it then mutates `getWeek(4)` — a past week. Ship-dark today (flags OFF) but collides with the "deload every 4th hold" design. | `deload_evaluator.dart:61/63` |
| P0-10 | **A third advance path exists and is un-gated.** `graduation_screen._onPro` calls `generateAndSchedule` directly and writes `current_phase`, never touching `isPhaseExpired()`. An intent flag installed only in `pro_phase_advance.dart` leaves it open. | `graduation_screen.dart:566/648/672` |
| P0-11 | **`PlanIntegrityReconciler` is both the bug and the proposed fix.** It writes `plan_start`/`plan_end` from the cloud snapshot (a P0-1 culprit); what limits its blast radius is a `for (w = 1; w <= 4)` symptom scan. Extending that scan (as proposed) makes the culprit fire *more often*, for exactly the hold users P0-1 protects. The `:148-149` guard must land **first**. | `plan_integrity_reconciler.dart:125/148-149` |
| P0-12 | **`currentPhaseCompletionRate()` hardcodes 4 weeks — and it is the advance gate's own input.** A free holder at week 9 has their rate computed over weeks 1-4 only. The plan redesigned the gate but not what feeds it. | `workout_schedule_read_service.dart:816-827`, consumers `pro_phase_advance.dart:87`, `graduation_screen.dart:591` |
| P0-13 | **A hard 12-week ceiling in four readers**, silently breaking at hold #9 (chips lose ✓, week rows stop rendering, strip truncates — no error, no telemetry). Directly contradicts "unlimited holds": either cap holds at 8 or move all four. | `workout_schedule_read_service.dart:714/729/733/820`, `train_provider.dart:601`, `screen.dart:274` |
| P0-14 | **A second `redoWeek4` caller**, with a bare `catch (_) {}` that swallows failure and navigates anyway. | `graduation_screen.dart:140-147` |
| P0-15 | **Unlisted `isPhaseExpired()` consumer** — the Train tab's expiry branch, i.e. the primary surface a holding user lives on. | `train/screen.dart:152`, also `deload_evaluator.dart:61` |
| P0-16 | **Blast radius is `platform`, not `account`** — `lib/core/services/sync/**` maps to platform, and P0-1 requires touching `sync_workout.dart`. Platform additionally *requires* a `feature_flag` artifact. (Asserted wrong twice; verified by running the tool.) | `docs/blast_radius.yaml:23-25/63` |

---

## P1 findings

- **`plan_start` also needs the restore guard**, not just `plan_end` — `getCurrentWeekNumber` derives from `plan_start` alone, so a regressed value yields an unbounded week feeding all 11 consumers. A safe guard **is** constructible with no schema change (`plan_json` carries `synced_at`, `sync_workout.dart:1050`); the workable shape is monotonic `max(local, cloud)` gated on `plan_start` identity.
- **Stamping `phase` on hold rows backfires for legacy users.** `bucketPastRows` does **not** require all rows stamped — it finds the *first* stamped row and carry-forwards. One stamped row flips the whole set onto the identity path, collapsing a legacy multi-phase user's past phases into one block. It is also a **no-op for modern installs** (the generator already stamps `phase`, and the copy preserves it) — the opposite of the intended effect. (`workout_schedule_read_service.dart:1049-1060`, `:399/:428`)
- **The intent flag has no safe consume point.** Consume-after-success: generation writes `plan_start`/`plan_end` *before* the 28 day-rows, so process death mid-generation leaves the window written, `current_phase` un-bumped, `isPhaseExpired()` now false → the flag is never consumed and the counter never catches up. Consume-before: any propagating failure burns the user's consent. Needs an **idempotency key, not a boolean**. Precedent to copy: `phase_repeat_nudge_pending` (`pro_phase_advance.dart:136-140`, cleared `home_provider.dart:938-957`, registered `user_config_migrator.dart:82-84`) — and note its explicit `HiveUserSession.currentOwnerFullId != null` cross-account belt at `:137`.
- **Home has a second blocker for the advance affordance:** `if (schedule == null && isPhaseExpired())` — during a hold `schedule != null`, so relaxing only the expiry half leaves Home with no affordance at all. (`home_screen.dart:743-748`)
- **`user_progress.current_week` is permanently `1`** — every writer sets the literal 1, no writer advances it — yet it is rendered to users by `weekly-report/index.ts:460` (into the Gemini prompt) and `weekly-recap-ready/index.ts:190` (push copy: "Week 1 debrief ready"), and read a second time at `ai_snapshot_builder.dart:1206`. A holder sees "WK 16" in-app and "Week 1" in the push.
- **`.range(0, 999)` with no pagination** truncates restore at 1000 rows ≈ **2.74 years** of daily schedule rows, ascending — so past the threshold the *current* phase is what gets dropped. Every sibling paginates properly. (`sync/sync_workout.dart:1795-1807`)
- **`_syncWorkoutPlan` serializes every `schedule_*` key** (full exercise arrays) into one `plan_json` on every push, with no window, cap or chunking, and nothing prunes `schedule_*` keys. The 4-week phase was the implicit bound on growth. (`sync/sync_workout.dart:1036-1056`)
- **`getPromotionStatus.ts` derives `deploymentsComplete` from a stale comment** claiming columns don't exist (they do, migration 081) and uses a **non-monotonic** `current_phase - 1`, diverging from both the client and the cron. P0-2's over-advance would flow straight into the coach saying "you have 7 deployments complete". (`_shared/tools/progress/getPromotionStatus.ts:144-158`)
- **`holdWeek` is a get→modify→set on shared state with no lock**, racing the splash's unawaited advance. `upsertScheduled` holds a per-date lock but the `plan_end` write sits outside it. Registry lens **L27 (concurrency) was never applied.** (`workout_schedule_write_service.dart:174-208`, `workout_write_service.dart:525`)
- **Unit 1 is too large for one review round** (~16 edit sites across 12+ files spanning core/services, train, home, profile, ai_coach). Split it.
- **The streak unit should precede the week-model unit** — otherwise `last_streak_week`'s value domain widens from `{1..4}` to `{1..N}` before it is converted, forcing a three-shape tolerant read instead of two.

---

## Additional breaking tests (beyond P0-7)

| Test | Broken by |
|---|---|
| `pro_phase_expiry_surface_test.dart:75/77/92/94/102` — pins `.isPro()`, `.isPhaseExpired()`, `advanceProPhaseIfExpired(ref)` and `reason: 'splash_auto_advance_phase'` | the advance redesign — **it cannot ship without breaking this** |
| `workout_schedule_read_path_behavioral_test.dart:145/168/188` | the un-clamp |
| `week_completion_check_test.dart:50/55` | phase-scoping `completedWeekNumbers` + cycle regrouping |
| `week_selector_past_phases_test.dart:57/72-78` — pins `'~/ 28'` and asserts `'PHASE II'` absent | the 28-day-fallback guard + cycle grouping |
| `workout_schedule_split_invariant_test.dart:46` — `expect(src.contains('redoWeek4'), isTrue)` | renaming `redoWeek4`. (⚠ `scripts/check_workout_schedule_split.dart:11` does **not** break — its only mention is in a file-header comment.) |

Also stale on rename: `docs/sot_registry.yaml:6105` — a **forbidden-pattern regex** listing `redoWeek4` that would silently stop matching `holdWeek`.

---

## Discipline artifacts the plan lacked

- **Closure YAML** (§4.2, ≥4-item batch): `docs/audit/<batch>.closure.yaml`, per-entry `terminal_state:`, no `deferred:` key, Gate 40-validated. A free-text "out of scope" section is the exact shape §4.2 bans.
- **Diagnose-docs** for every `fix:` commit (the plan budgeted only Unit 0's two; ≥4 more are needed).
- **SoT registry — 5 concepts touched**, two with text that becomes factually false: `workout_schedule_read_path` (its description owns `getCurrentWeekNumber`; the reader's `fields_read` says "week-1-to-4"), `workout_schedule_write_path` (names `redoWeek4`), `week_completion_check`, `template_scheduling`, `phase_progress_current_phase`.
- **Ship-dark tiering is not validly claimable** for the hold unit as scoped: byte-identical-OFF would mean its data-integrity fixes don't ship. And the plan-review record is keyed on **branch name at the merge commit**, so a branch mixing ship-dark and un-flagged units cannot self-declare `review_rounds: 1`.
- **Migration / boot-heal for users already affected in the wild** — extended `plan_end` with untouched `plan_start`, non-Sunday `plan_end`, orphan rows. Unit 1 alone flips this cohort's live week from a clamped 4 to 5+ the moment it installs.
- **Clock seam:** `redoWeek4` uses raw `DateTime.now()` (`workout_schedule_write_service.dart:179`), so "hold sourcing" and "`plan_end` stays a Sunday" are not deterministically testable until `holdWeek()` adopts `nowWall()`. (Adopting it is safe — verified release-identical.)
- **Zero telemetry** on the mechanic the retention thesis rests on: `plan_expired_card.dart` logs three events with **no consumer anywhere** in the repo. No hold-count, no distribution, no hold→convert/churn instrumentation. Renaming the `phase_1_day_29_*` keys is therefore free; the real risk is having no measurement at all.

---

## Corrections to the record

- **`longest_gap_days` has NO client/server divergence.** Both sides read a permanently-0 column — there is no writer in `lib/` *or* `supabase/functions/`. The earlier claim that "the server computes it for real" was false. The work remains separable (tracked as its own task), but for a different reason.
- **The template door is not silent.** `template_builder_screen.dart:417-421` surfaces a zero-writable-days message and the template still saves; the skip is at `:405`. Accurate framing: *"the template saves but schedules zero days, with a message."* Also `const maxWeeks = 4` at `:391` caps scheduling independently of `plan_end`.
- **`week_selector.dart` lives under `lib/features/train/widgets/`**, not `screens/train/`.
- **`_PastPhaseGroup`'s `for (w = 1; w <= 4)`** (`week_selector.dart:391`) is *itself* the hardcode that hides extension history — it must be fixed, not reused as a pattern.

---

## Verified-sound (no action needed)

The free rank ceiling really does stay LS (the ladder walk `break`s at the first failure and PO gates on `deploymentsCompleteAtLeast: 2`); holds *lower* completion rate rather than raising it, so they cannot lift anyone over a gate; nutrition is fully decoupled from phase/week; there are no local notifications and no phase-keyed cron; `expiry-reminder`, `workout-window-closing` and `re-engagement` are date/status-driven and unaffected; `scheduled_workouts.week_number > 4` is schema-safe (bare nullable int, no CHECK, no server reader); `swap_service.dart:113-119`'s `_normalizeToMonday` cap is a genuinely good reference pattern for date-keyed week identity; and `holdWeek()` adopting `nowWall()` affects no existing caller or test.
