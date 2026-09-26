# Design — readiness sensor + deload engine (OI-53, flags 1 & 2 of 12)

**Date:** 2026-09-01
**Branch:** `readiness-flip`
**Blast-radius:** `platform` (`docs/blast_radius.yaml:67` — `lib/shared/repositories/plan_engine/**`)
**Review requirement:** FULL ×2 context-blind + `bpass: accepted`. §4.12.4 explicitly FORBIDS
the lighter `ship_dark_build` tier on a flip-on commit.

> **Supersedes `docs/plans/readiness-flip.md`** (revision 4, three review rounds). That plan
> assumed a pure flag flip preserving the existing pre-workout sheet. The founder redesigned
> the feature mid-review. **The plan's verified ground truth is carried forward here and is
> still accurate**; its behavioral surface and test plan are re-derived below. Do not execute
> the old plan.

---

## 1. What this is

`enable_readiness` collects a daily self-reported readiness check-in. It has been dark since
July 2026; every APK through +39 ships with it off. It is the **sensor**. Three other dark
flags are the **engine** that consumes it — this batch also flips the first of them,
`enable_triggered_deload`.

### Why these two flip together (and why that is not flag-batching)

`docs/ship_dark_pending_review.yaml` warns that batching flips is *"one review pretending to
be thirteen."* This pairing is different, for a mechanical reason verified in source:

`plan_generator.dart:270` — `stashWorkingBase: PlanEngineFlags.triggeredDeloadEnabled`

The deload feature works by stashing each exercise's pre-cut working sets **at plan-generation
time**, then restoring from that stash to turn a planned deload week into a working week.
`deload_evaluator.dart:99-103` guards on stash presence: *"only 7-B-1-flag-ON plans stashed;
legacy → keep"*.

**Therefore a plan generated while the deload flag is OFF can never be lifted.** Flipping
deload later would not help any existing plan — it would take effect only for plans generated
after that flip, requiring a second APK and a second wait. Flipping together starts the stash
immediately, so the feature becomes live on its own as readiness data accumulates.

They are also untestable apart: `deload_evaluator.dart:55-56` early-returns without readiness.

**This is ONE review covering TWO flags, justified by a code-enforced dependency.** The
plan-review record must say so explicitly rather than presenting it as a single-flag flip.

---

## 2. Locked decisions

| # | Decision | Date |
|---|---|---|
| 1 | Readiness stays **PRE-workout**. The post-workout completion screen is a **protected surface** — it is the share/growth moment and takes no data collection, ever. | 2026-09-01 |
| 2 | **Sleep is pulled automatically**; the ask shrinks from 3 questions to 2. | 2026-09-01 |
| 3 | Sleep→axis mapping: `>6.5h → 0`, `4.5–6.5h → 1`, `<4.5h → 2` (both endpoints in the middle band). | 2026-09-01 |
| 4 | Fallback when sleep is unknown: the sheet asks it as a normal tap row, with a nudge to sync — **not** an explanation or apology. | 2026-09-01 |
| 5 | **Readiness is FREE for all.** The Reports paywall branch is removed, not gated. | 2026-08-31 |
| 6 | **No new evening push.** Five nudges already fire 19:00–21:00 IST; a sixth is how apps get muted. Terminal decision, not a deferral. | 2026-08-31 |
| 7 | `enable_readiness` + `enable_triggered_deload` flip in the same commit (§1). | 2026-09-01 |
| 8 | The auto-filled sleep row's marker reads **`◆ SYNCED`**. | 2026-09-01 |

---

## 3. Design

### 3.1 Sleep acquisition — one reader, two writers

Readiness reads **`sleep_log_<istDate>`**, NOT Health Connect directly.

- Reader: **`HealthReadService.sleepHoursForDate(DateTime) → double?`** already exists
  (`health_read_service.dart:60-68`) and already handles both `sleep_hours` (canonical) and
  `duration_hrs` (legacy alias). **Do not write a new reader.**
- That key already has a writer: `HealthWriteService.logSleep` (manual + AI-coach path). So a
  user who tells the Bridge *"slept 5 hours"* gets the auto-fill with no Health Connect
  involved.
- **The only new sync work:** add `HealthDataType.SLEEP_ASLEEP` to the type list at
  `health_sync_service.dart:28-29` (today: `STEPS`, `WEIGHT` only). The service, permission
  flow and sync loop already run.

⚠ Health Connect treats sleep as a **separate permission** from steps. Denial is expected and
is exactly what §3.3's fallback covers. Sleep sync must fail soft — never block the steps/weight
sync that works today.

### 3.2 The sleep→axis mapping

| Measured sleep | Axis | Reads as | Fatigue flag? |
|---|---|---|---|
| `> 6.5 h` | **0** | Solid | No |
| `>= 4.5 h` and `<= 6.5 h` | **1** | Okay | No |
| `< 4.5 h` | **2** | Rough | **Yes** |

Boundaries are explicit because off-by-one at a threshold is a silent bug class: **exactly
6.5 h and exactly 4.5 h both land in the middle band.**

⚠ **This mapping means `readinessLevelFor` needs NO change.** Sleep still yields 0/1/2, so the
flag-count formula (0 flags → green, 1–2 → yellow, 3 → red) is untouched. An earlier draft
claimed the formula needed rework; that was wrong.

### 3.3 The sheet — two states

Trigger unchanged: `beginWorkoutWithReadiness` from the three Start Workout call sites
(`home_screen.dart:893`, `train/hero_cards.dart:142`, `train/planned_expansion.dart:66`).

**State A — sleep known** (`sleepHoursForDate` non-null): sleep renders as a read-only row
showing the measured value and its band (e.g. `7h 20m` / *Solid*) with `◆ SYNCED` and
"Already synced — nothing to tap". **Two** tap rows remain: SORENESS, ENERGY.

**State B — sleep unknown** (null): sleep renders as the existing three-option tap row, with a
nudge — *"Sync your sleep for a sharper read."* Non-shaming, and it does quiet growth work by
motivating the permission grant. **Three** tap rows.

Both states keep the existing header (*"READINESS CHECK / A quick read so today fits how you
feel. Skippable."*), the primary START WORKOUT button, and SKIP.

Mockups: `docs/mockups/2026-09-01-readiness-preworkout-flow-v1.html` (full 5-step flow),
`-v2.html` (the two states + formula).

### 3.4 Flag mechanics

Both flags invert to kill-switches, following the `enable_equipment_exclusions` precedent
(`e6a8a8ae`, diagnose `e2d6b8`) — key name AND catch-block default both flip:

```dart
// plan_engine_flags.dart:186-192
static bool get readinessEnabled {
  try { return HiveService.instance.configBox.get('disable_readiness') != true; }
  catch (_) { return true; }
}
```
Same shape for `triggeredDeloadEnabled`. Both old `enable_*` keys are RETIRED.

⚠ **Both kill-switches need a dev-panel WRITER — neither exists today.** `grep -rn
"disable_readiness" lib/ test/ scripts/` → zero hits; `dev_panel_screen.dart` writes only
`enable_hold_weeks` (`:255`) and `disable_equipment_exclusions` (`:281`). §4.6 requires the old
path stay *reachable when the gate is closed*; a gate nothing can close is not reachable. The
precedent hit this identical gap — its fix records why at `dev_panel_screen.dart:267-271`.
Mirror `_toggleEquipmentExclusions` (`:275-288`) for each flag.
⚠ Do **not** copy its toast copy — *"regenerate a plan to see the effect"* is wrong for
readiness (it applies on the next Start Workout).

### 3.5 What is REMOVED

- The free-user paywall branch in `reports_screen.dart` (`:534-536` lock icon, `:561-571`
  `showPaywallSheet(feature: 'Readiness Trends')`) — readiness is free (decision 5). The trend
  renders for everyone.

### 3.6 What is KEPT (an earlier decision, since reversed)

An earlier round chose post-workout capture and would have deleted the set-drop and load-cut.
**Decision 1 reversed that.** `_applyReadinessSetDrop` and `_readinessLoadFactor` both STAY.

⚠ `effectiveLoadFactor` (`train_provider.dart:1166-1169`) must not be touched regardless — it
is SHARED with `enable_session_detraining_cut`.

---

## 4. Behavioral surface — everything that goes live

1. **The sheet appears** on Start Workout (3 call sites, §3.3).
2. **RED day: one set dropped**, first isolation exercise with `sets > 1`, `break` after one
   (`train_provider.dart:1322-1333`). Compounds never lose a set.
3. **Compound load prefill cut** — red −10%, yellow −7% (`_readinessLoadFactor:1171-1182`),
   applied at `active_workout/exercise_card.dart:91`. The user can overwrite it.
   ⚠ Two further reads at `:564` (suppresses the "TRY:" hint) and `:680` (`_OverloadIndicator`).
4. **Rows flow to cloud.** `sync_health.dart:71` upserts `readiness_daily`. Migration **105**
   is APPLIED (`applied_migrations.json:690`); own-rows RLS; PK `(user_id,date)`. Restore at
   `sync_service.dart:1403/:1570/:1775` + `sync_health.dart:592`.
5. **⚠ The Reports readiness card wakes up** — `reports_screen.dart:364` calls
   `_buildReadinessTrend()` **unconditionally**; the file has ZERO `PlanEngineFlags`
   references. It is dormant today only because no row has ever existed. Per decision 5 it now
   renders for everyone.
6. **Plans begin stashing** `working_sets`/`working_reps` on week 4 (`plan_generator.dart:270`).
7. **Week-4 deload can be lifted** once ≥3 readiness rows exist in a trailing 14-day window
   (`deload_evaluator.dart`), turning a planned easy week into a working week.

**What does NOT change:** exercise selection. `readiness` has zero hits in
`exercise_selector.dart` and `plan_generator.dart`; the generator is never consulted. **No
shuffle, ever.** On a GREEN day the user sees nothing different.

⚠ **The kill-switch is not a full revert.** Turning `disable_readiness` on stops new writes,
the sheet, the set-drop and the load cut — but rows already written keep rendering the Reports
card. Accepted: the code path reverts verbatim (§4.6's actual requirement); the data persists.
No rule requires hiding a user's own history.

---

## 5. Test plan

### 5.1 ⚠ SIX existing tests BREAK — all must be repointed in this commit

Rule 20: failing tests on `main` are P0. A plan that only ADDS tests ships a red suite.

| # | File:line | Why it breaks | Repoint |
|---|---|---|---|
| 1 | `readiness_checkin_behavioral_test.dart:207` | Never writes the key — relies on the default. | Write `disable_readiness: true`. |
| 2 | `plateau_escalation_behavioral_test.dart:213` | Writes `enable_readiness: false`, a key the new getter no longer reads → silent no-op. `setUp:183-184` enables both flags, so the seeded plateau is DETECTED and `isEmpty` fails. | Write `disable_readiness: true`. |
| 3 | `plateau_rotation_behavioral_test.dart:324` | Same shape (`setUp:155`). | Same. |
| 4 | `deload_eval_behavioral_test.dart:296` | `enableFlags(readiness: false)` (`:203-206`) skips the write conditionally. Seeds good readiness + non-declining compound → post-flip every clause is positive → week LIFTS. | `enableFlags` writes `disable_readiness: true` on that branch. |
| 5 | `deload_eval_behavioral_test.dart:287` | `enableFlags(deload: false)` — same conditional-skip, now for the deload flag. | Same treatment for `disable_triggered_deload`. |
| 6 | `deload_working_base_stash_behavioral_test.dart:81` | `setFlag(false)` **deletes** `enable_triggered_deload` (`:66`), relying on the default. Post-flip the plan DOES stash → `expect(ex.workingSets, isNull)` fails. | `setFlag(false)` writes `disable_triggered_deload: true`. |

⚠ #2–#6 share the dangerous shape: they fail not because an assertion is wrong but because
**the mechanism they think they are disabling is no longer keyed on that string.**

### 5.2 ⚠ SEVEN writes go VESTIGIAL — green, but testing nothing

Worse than breaking, because nothing surfaces them:

`deload_eval_behavioral_test.dart:204`, `:205`, `:643` · `plateau_escalation:184` ·
`plateau_rotation:155` · `readiness_checkin:155` (the `enableReadiness()` helper) ·
`deload_working_base_stash:64`.

⚠ `readiness_checkin_behavioral_test.dart:180`, `:194`, `:202` are NAMED *"flag ON + …"* and
would pass by luck of the new default while no longer exercising the flag.

**Fix:** delete the writes; delete `enableReadiness()` **and its three call sites** (`:182`,
`:195`, `:202` — deleting the helper alone will not compile); rename those tests to
*"default (readiness ON) + …"*; correct the file header at `:3`.

### 5.3 New tests

1. `default (no config key) → readiness ENGAGES` — the inverse of break #1.
2. `disable_readiness kill-switch → byte-identical to pre-flip`.
3. `enable_readiness: false is INERT post-retirement` — makes the §5.1 #2–#6 failure mode
   impossible to reintroduce silently.
4. **Sleep mapping, all six boundary cases:** `6.6→0`, `6.5→1`, `4.5→1`, `4.4→2`, plus a
   typical value each side. Pure function, no Hive.
5. **Sheet state A vs B:** `sleep_log_` present → sleep row is read-only and the logged
   `readiness_<date>` carries the mapped axis; absent → three tap rows.
6. `readiness_flag_no_hive_default_test.dart` — **no `setUpAll`, no Hive init**, asserts
   `readinessEnabled` is `true`. Covers the catch-block half (§6, Mutation C). Feasible:
   `hive_service.dart:198-203` throws `StateError` when uninitialised, and
   `test/plan_generator/generator_matrix.dart:183-185` documents a live no-Hive context in this
   suite.
7. Equivalents of 1–3 for `disable_triggered_deload`.

---

## 6. Mutation plan (rule 21 — mutate it and run it)

Tests written by the author of a fix inherit its blind spot.

- **A — revert the getter** to `get('enable_readiness') == true` / `catch → false`, in place.
  Expect §5.3.1 and §5.3.3 to redden.
  ⚠ **Under A, breaks #1–#6 and §5.3.2 all stay GREEN — and that is not protection.** Each
  writes `disable_readiness: true`; the reverted getter reads `enable_readiness`, finds null,
  falls to the OLD `false` default, and lands on OFF — the same outcome, for an unrelated
  reason.
- **B — flip the polarity**, keeping the new key: `!= true` → `== true`. Traced for #1:
  `disable_readiness: true` → wrongly ON → set drops → `'2'` vs expected `'3'` → REDDENS. This
  is the mutation that actually exercises the repointed tests.
- **C — the catch-block half alone**: `catch (_) => true` → `=> false`. §5.3.6 must redden.

**For all three:** confirm the mutation applied (`grep -c` the token before and after, or run
the broken form once). A regex that silently matched nothing makes a green run read as proof of
nothing. Record what was mutated and how many tests reddened **in the commit body** (there is
no diagnose-doc — see §7).

---

## 7. Non-code artifacts (same commit)

- **`docs/plan-reviews/readiness-flip.md`** — CI hard-fails the merge without it
  (`check_plan_review_record_exists.dart`; ≥platform also requires `bpass: accepted`). Needs
  `---` frontmatter with line-anchored `^key:` fields: `branch: readiness-flip`,
  `review_rounds: >= 2`, `ground_truth_verified: true`, `verdict: converged`,
  `bpass: accepted`, `bpass_review:`. **No `tier: ship_dark_build`.** Must state the two-flag
  coupling (§1) openly.
- **`docs/ship_dark_pending_review.yaml`** — the `enable_readiness` (`:215-227`) and
  `enable_triggered_deload` (`:237-246`) entries get `flip_reviewed: true` + a `note:` naming
  branch and the discriminating test. ⚠ **Keep them in `pending:`** — `resolved:` (`:471`) is
  empty and unused, and the equipment precedent stayed in `pending:` (`:184-213`). Leave
  `flip_commit: null`; a commit cannot record its own sha.
- **`docs/sot_registry.yaml:7854-7897`** — update the kill-switch name/default.
  ⚠ `reader_manifest_complete: true` (`:7876`) is FALSE: it lists three readers and **four**
  are missing — `reports_screen.dart:505`, `deload_evaluator.dart:169`,
  `plateau_scan.dart:195-210`, `volume_titration.dart:112-132`. Add all four. Also stale
  in-entry: `:7867` cites `exercise_card.dart:89` (prefill is `:91`); `:7875` says "both START
  buttons" (there are three); `:7886-7889` says "one multiplication" (there are three).
- **⚠ FOUR documents assert an invariant this commit falsifies** — that titration is safe
  *because* readiness is dark. It stops being true the moment rows accumulate:
  `plan_engine/CLAUDE.md:122` (**auto-loaded** for anyone working in that subtree, so the next
  flip author would be handed a false assurance), `volume_titration.dart:14`,
  `sot_registry.yaml:8246`, `docs/plans/batch9-volume-titration.md:111-112` and `:237`.
  Correct all four. **Do NOT** add a guard inside `_recovered()` — `plateau_scan` (`:81`,`:83`)
  and `deload_evaluator` (`:55-56`) gate at their entry points; a third style buried in a
  helper diverges from the pattern for an already-unreachable path.
  ⚠ `ship_dark_pending_review.yaml:245` belongs to `enable_triggered_deload`, whose dependency
  IS code-enforced — leave it. `enable_volume_titration` (`:256-262`) has **no `note:` at all**;
  add one recording that its readiness dependency is now live and unguarded.
- Docstrings naming a retired key or falsified default: `plan_engine_flags.dart:179-185`
  (the getter's OWN docstring — most misleading), `:212-214`, `:378-380`;
  `deload_evaluator.dart:14`; `plateau_scan.dart:18`; `day_rollover_service.dart:174`;
  `plan_engine/CLAUDE.md:68`, `:215`; `sot_registry.yaml:7986`, `:8031`, `:8317`, `:8373`.
  ⚠ Do NOT rewrite `docs/plan-reviews/*` or `docs/reviews/*` — historical records.
- `readiness_sheet.dart:3-4` and `sot_registry.yaml:7875` say "the two START buttons"; there
  are three.
- `train/screen.dart:32` imports `readiness_sheet.dart` and uses nothing from it — dead import
  in the blast zone. CI analyze is *"zero warnings allowed"*; confirm INFO-level, drop it here.
- OI-53 board entry: 12 → **10** remaining, recording both flips and the founder's dated
  decision (the entry currently reads `Blocked on: FOUNDER`, unverifiable from the repo).
- Commit type: **`feat:`**, no diagnose-doc — nothing is broken; a dormant feature is being
  activated. `feat:` correctly falls outside rule 22's `^(fix|bug|regression)` regex.

---

## 8. Risks and open items

1. **Sparse data.** The engine needs ≥3 check-ins per 14 days. A user who always taps SKIP
   generates nothing and the deload never fires. Accepted: skippable is a deliberate product
   choice, and the sheet is now two taps.
2. **Sleep permission denial** → State B forever for that user. Handled, not eliminated.
3. **The current plan has no stash.** Plans generated before this flip cannot be lifted
   (§1). **The device test must generate a fresh plan** (phase advance or regeneration) before
   the deload is observable — otherwise nothing will happen and it will read as a bug.
4. **OI-95 residual:** with §3.4's toggles the kill-switches work in debug; there is still no
   release-build surface. Pre-existing, tracked at OI-95, out of scope.
**No open items.** (The `◆ SYNCED` marker was the last one; ratified 2026-09-01 — decision 8.)

---

## 9. Non-goals

- No new evening push (decision 6).
- No change to exercise selection — readiness cannot and will not shuffle a plan.
- No touching the post-workout completion/share screen (decision 1).
- Not flipping the other 10 OI-53 flags.
- Not prefilling soreness/energy from any measured source — they are irreducibly subjective.
