---
reviewed_at: 2026-09-13T19:00:40+05:30
staged_against: 4536b6e54411
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, modelled_on_is_a_checkable_claim, self_attesting_artifact]
findings_count: 11
verdict: accepted
---

# Code Review — OI-189 (`oi189-plan-end-bound`)

Two fresh, context-blind Sonnet subagents, dispatched sequentially so the mutation reviewer
(B) never shared a mutating tree with the read-only reviewer (A): A ran lenses
1/2/3/4/5/7/9/10 read-only; B ran lenses 6/8 (mutation-based) after A returned. Original
staging hash at dispatch time `1a998a56f72b`; this file's `staged_against` is the FINAL hash
after the fixes below, the SKILL.md tuning entry, and the plan-review record's feature-flag
deviation section all landed (`4536b6e54411`) — `docs/reviews/` itself is excluded from the hash
computation, but neither `.claude/skills/` nor `docs/plan-reviews/` is.

## Finding 1 — P1 — blast_radius_mismatch
- **file:line:** `docs/blast_radius.yaml:25` (platform tier `requires:`) vs. the whole staged set
- **claim:** The classifier computes `platform` for this diff, and the platform tier's
  `requires:` list includes `feature_flag` — but nothing in the staged set adds a kill-switch /
  Hive flag / RemoteConfig gate for the new destructive sweep
  (`sweepNonCompletedRowsPastPlanEnd`, which permanently deletes Hive rows) or the new
  unconditional `plan_json` pushes. CLAUDE.md §4.6 requires the feature-flag protocol for any
  change touching sync / plan generator; nothing here is behind a switch.
- **verification:** `dart run scripts/blast_radius_from_diff.dart - <<< "$(git diff --cached --name-only)"` → `platform`; `grep -irn "feature_flag\|kill.switch\|kill_switch" docs/plan-reviews/oi189-plan-end-bound.md docs/superpowers/plans/2026-09-12-oi189-plan-end-bound.md docs/diagnoses/2026-09-12-regen-writers-stop-at-plan-end-b9e4d1.md` → 0 hits.
- **suggested-fix:** Either add a kill-switch gating the sweep + the new durability pushes, or
  have the plan-review record explicitly state the waiver and why (the ADR-0018 precedent for
  a self-attested, founder-ratified deviation).
- **status:** accepted — **resolved 2026-09-13 as a written, founder-ratified deviation** (the
  founder's own choice between adding a flag and waiving with documentation; waiver chosen). See
  `docs/plan-reviews/oi189-plan-end-bound.md`'s "Feature-flag deviation" section for the full
  record: no kill-switch ships; the 27-test / 22-mutation-leg / two-prod-census-at-0-rows safety
  net is the documented substitute, matching the 2026-08-11 `commit-merge-push-process` ADR-0018
  precedent for the same registry field. No code change.

## Finding 2 — P2 — writer_reader_drift (display-reader)
- **file:line:** `lib/features/ai_coach/widgets/tool_confirm_card.dart:409-410` (`_executedMessage`, unchanged by this diff)
- **claim:** After this diff, a sweep-only regen can return SUCCESS with `count: 0, cleared: N`.
  `_executedMessage` keys purely on `intent.type` and always renders `'Plan regenerated'` for
  `regenerate_plan_block`, regardless of `result.data` — misleading a user who triggered only a
  sweep with zero new workouts laid out. `result.data`'s `count`/`cleared` fields have zero
  readers anywhere in `lib/`.
- **verification:** `grep -rn "data\['cleared'\]\|data\['count'\]" lib/features/ai_coach/widgets/ lib/features/ai_coach/providers/` → 0 matches outside `tool_dispatcher.dart`'s writer sites.
- **suggested-fix:** Thread the result through to the card (a `ToolIntent` field), per OI-190.
- **status:** spawn_followup_task — **already filed** as an OI-190 input by this same batch's
  own round-2 F12 / round-4 F7 (see `docs/audit/open_issues.md`'s OI-190 "Input added
  2026-09-13" bullet, written before this review dispatched) — a catastrophic-tier EF change
  (`regeneratePlanBlock.ts`'s `previewSummary`) is entangled with the client fix, so it is
  correctly scoped to its own unit rather than this one. No new task spawned; pointing at the
  existing one.

## Finding 3 — P3 — self_attesting_artifact (stale citation)
- **file:line:** `docs/diagnoses/2026-09-12-regen-writers-stop-at-plan-end-b9e4d1.md`'s `writers:`
  entry for writer B's push, originally `line: 613`
- **claim:** Line 613 is `reason: 'regen_from_date_plan_window_push'));` (inside the catch
  block), not the push call itself, which is at line 610.
- **verification:** `git show :lib/core/services/workout_schedule_read_service.dart | sed -n '609,613p'`
- **suggested-fix:** Cite line 610.
- **status:** accepted — fixed (citation now `line: 610`).

## Finding 4 — P3 — self_attesting_artifact (stale citation, bundled entry)
- **file:line:** same diagnose-doc, writer A's citation, originally `line: 344` covering both
  `bool pushPlanWindow = false,` (actually line 208) and the gated push (line 344)
- **claim:** One citation bundled two distinct locations 136 lines apart under one line number.
- **verification:** `git show :lib/core/services/workout_schedule_read_service.dart | sed -n '208p;344p'`
- **suggested-fix:** Split into two entries.
- **status:** accepted — fixed (two separate `writers:` entries now: `line: 208` for the
  parameter, `line: 344` for the gated push).

## Finding 5 — P3 — split_self_consistency
- **file:line:** `docs/superpowers/plans/2026-09-12-oi189-plan-end-bound.md`, task-checklist Steps
  3 and 8 (originally lines ~1240, ~1260)
- **claim:** The plan's own task-instruction bullets still told the implementer to write
  `blast_radius: account` into the diagnose-doc and plan-review record frontmatter, while the
  plan's own header (line 20) documents the round-4 correction to `platform`.
- **verification:** `git show :docs/superpowers/plans/2026-09-12-oi189-plan-end-bound.md | grep -n "blast_radius"`
- **suggested-fix:** Update the two stale task bullets, or note they predate the correction.
- **status:** accepted — fixed (both bullets now say `platform`, with a pointer to the Global
  Constraints correction).

## Finding 6 — P2 — guard_without_its_mirror (mutation-verified)
- **file:line:** `lib/core/services/sync/sync_workout.dart:2103` (new `pausedForSimulation`
  guard) × `lib/features/dev/simulation_service.dart` (end-of-run flush list, pre-existing)
- **claim:** Every simulated phase advance in a year-sim run fires with
  `pausedForSimulation == true`, so `pushWorkoutPlanForSyncDomain()` no-ops on all of them
  (confirmed: `simulation_service.dart:551` → `autoGenerateNextPhaseIfNeeded` →
  `generateAndSchedule(pushPlanWindow: true)` → the new guard). Nothing in the post-loop flush
  list (`syncWorkoutDataNow`, `syncNutritionDataNow`, `syncWeightNow`, `syncSleepNow`,
  `syncMeasurementsNow`, `pushStepsLogsForSyncDomain`, `evaluateAndPromote`, `pushSnapshot`)
  carries `plan_json` — `syncWorkoutDataNow`'s fan-out is templates/logs/exercise-logs/
  schedule-completions/scheduled-workouts/streaks only. `weeklyFullSync` (the only other
  `_syncWorkoutPlan` caller) is never called from `simulation_service.dart`. The new guard's own
  comment ("Cloud catches up at the next weeklyFullSync, as before") is therefore false for the
  sim harness specifically — a full sim run leaves the sim account's cloud `plan_json` window
  stale, reproducing the c9e4b7 scenario for that account.
- **verification:** `grep -n "weeklyFullSync\|checkAndSync" lib/features/dev/simulation_service.dart` → 0 matches (before the fix).
- **suggested-fix:** Add a `plan_json` push to the end-of-run flush list.
- **status:** accepted — fixed. Added `await flush('workout plan window', sync.pushWorkoutPlanForSyncDomain);`
  to the flush list (`simulation_service.dart:309`), between the `workout` and `nutrition+water`
  flushes. New test: `test/contracts/oi189_plan_end_bound_behavioral_test.dart`, "simulation_service
  end-of-run flush pushes the workout plan window (review B-1)" — a source pin (the sim harness
  itself is `kDebugMode`-gated, dev-only, so a live behavioural test is not feasible). Mutation
  M21 (delete the flush line): 1 red on exactly this pin.

## Finding 7 — P2 — guard_without_its_mirror (defense-in-depth, currently unreachable)
- **file:line:** `lib/core/services/workout_schedule_read_service.dart:1614` (sweep's
  completed-row exemption, pre-fix)
- **claim:** The completed exemption only ran `if (isSchedule)` — a `displaced_*` shadow's own
  `status` was never read, so a completed row backed up into `displaced_*` would have been swept
  like any orphan, contradicting the function's own doc-comment ("Completed rows are history and
  stay"). The only current writer of `displaced_*` (`template_service.dart`'s
  `assignTemplateToDate`) explicitly refuses that shape (`:93-96`), so this was not reachable
  through the current codebase — but the sweep's own safety property should not depend on a
  DIFFERENT file's discipline.
- **verification:** Probe test (seed `displaced_*` with `status: 'completed'` past `plan_end`,
  call the sweep) — pre-fix: `removed=1`, row deleted.
- **suggested-fix:** Add the same `status == 'completed'` check for `isDisplaced` rows.
- **status:** accepted — fixed. The `else` branch now checks `status == 'completed'` for
  displaced rows too. New test: "a displaced_ shadow with status: completed past plan_end
  survives". Mutation M20 (remove the new branch): 1 red on exactly this test.

## Finding 8 — P2 — asserted_fixture_value (coverage gap)
- **file:line:** `lib/features/ai_coach/widgets/diff_preview/regenerate_plan_diff.dart:166-183`
  and the byte-identical `_phaseNote` in `switch_goal_diff.dart` (pre-fix)
- **claim:** Zero test coverage anywhere in `test/` for `_phaseNote`'s three message forms or
  either widget's `totalWeeks == 0` branch — 87 lines of user-facing copy/branching, structurally
  untestable because the method was library-private on a private `State` class.
- **verification:** `grep -rln "_phaseNote\|RegeneratePlanDiff\|SwitchGoalDiff" test/` → 0 hits (pre-fix).
- **suggested-fix:** Extract to a pure function (or add a widget test).
- **status:** accepted — fixed. Extracted `phaseNote()`/`phaseDayLabel()` to a new shared file
  `lib/features/ai_coach/widgets/diff_preview/phase_note.dart`; both widgets' private methods now
  delegate (same name, same call sites, zero behaviour change — verified byte-identical bodies
  before extracting). 6 new unit tests cover all three forms, the `clears==0` vs `>0` branch, and
  singular/plural wording. Mutation M22 (invert the singular/plural ternary): 2 red, both on the
  predicted assertions — the only leg in the table that reddens two tests by design, since the
  inverted ternary breaks both the singular case and the "2 workouts" plural case.

## Finding 9 — P2 — asserted_fixture_value (mirror case, pre-existing function, out of scope)
- **file:line:** `lib/core/services/workout_schedule_read_service.dart:1642`
  (`_scheduledWorkoutDays`, PRE-EXISTING, untouched by this diff)
- **claim:** The sweep's doc-comment implies removing swept orphans is sufficient to flip
  `isPhaseExpired()` true. But `_scheduledWorkoutDays` (backing `isPhaseExpiredFrom`) filters
  only by `type`, never `status` — a FUTURE-dated `completed` row past `plan_end` is correctly
  PRESERVED by the sweep (it is history) but still counted as a "real scheduled day", keeping
  `isPhaseExpired()` false. This reproduces the exact OI-174 symptom for this one row shape. The
  new test file's own fixture comment already names this caveat and sidesteps it by dating its
  completed row in the past.
- **verification:** Probe test (future-dated completed row, plan_end in the past) —
  `swept.removed=0`, `isPhaseExpired()` stays `false` before AND after the sweep.
- **suggested-fix:** Either document as an accepted residual or widen
  `isPhaseExpiredFrom`/`_scheduledWorkoutDays` to exclude completed rows — the latter touches a
  different, pre-existing function with its own blast radius.
- **status:** spawn_followup_task — documented as a fourth OI-174 residual (the entry already
  tracks three related residuals from this same unit's scope boundary); not fixed here because it
  is a pre-existing function this unit's writer-C-bound-plus-sweep contract does not own.

## Finding 10 — P3 — self_attesting_artifact (census reproducibility)
- **file:line:** `docs/diagnoses/2026-09-12-regen-writers-stop-at-plan-end-b9e4d1.md`'s census line
- **claim:** "`grep -rl` over test/ for the nine touched basenames → 92 files, 849 tests, all
  green" does not name the nine basenames, so it is not independently reproducible.
  Reviewer B's own best-effort reproduction (the 8 touched `lib/` basenames + the test file) got
  87 files / 784 tests — smaller but still green, so it read like a discrepancy rather than an
  incomplete instruction.
- **verification:** Diffed the 87-file reproduction against the original 92-file census
  (recovered from this session's own scratch artifacts); the 5 missing files all import
  `workout_schedule_service.dart` — the FACADE `pushPlanWindow` is deliberately NOT forwarded
  into (M12 + the "not reachable from the facade" pin). Ten basenames with that one added
  reproduces exactly 92/92 files.
- **suggested-fix:** Name the basenames explicitly.
- **status:** accepted — fixed. The census line now lists all ten basenames and the exact
  reproducible command; re-run against the current tree (post all fixes above) → 92 files, 857
  tests (849 + the 8 new B-pass-remediation tests), all green.

## Finding 11 — P3 — asserted_fixture_value (informational, no defect)
- **file:line:** `lib/core/services/workout_schedule_read_service.dart:1627` (the sweep's return
  record literal)
- **claim:** Swapping the `workouts:`/`removed:` fields reddens only 1 of the (then-19) tests —
  the dedicated helper test. Every other test that exercises the sweep indirectly uses fixtures
  where `workouts == removed` numerically (no rest/off/`displaced_*` rows mixed into the swept
  set), so the swap is undetectable through those paths.
- **verification:** Mutation run — `+18 -1`, only the helper test reddened.
- **suggested-fix:** None required — the reviewer's own note says so; recorded for completeness
  per lens 8(c)'s "explain a mutation that reddens fewer than expected" instruction.
- **status:** false_alarm — true observation, not a defect. The field-identity contract is real
  but sufficiently pinned by the one dedicated test; every OTHER call path's fixtures happening
  to make the two fields numerically equal is a property of those fixtures, not a gap in the
  production code.

## Lenses returning clean (reviewer A)
- **function_exception_swallow**: `git diff --cached | grep -n "functions\.invoke\|callFunction"` → 0. Read `ErrorTelemetry.recordNonFatal` in full — never rethrows, both legs self-guarded.
- **unawaited_no_error_sink**: all 8 new `unawaited(ErrorTelemetry.recordNonFatal(...))` sites match the pre-existing `holdWeek` shape exactly; traced ordering at all push sites — every push happens after the relevant Hive writes.
- **secrets_in_tree**: `git diff --cached | grep -ncE 'sk-|rzp_live_|AKIA|-----BEGIN|eyJ[A-Za-z0-9_-]{20,}|service_role'` → 1 hit, false positive (`"task-by-task."` substring in plan boilerplate). Zero real secrets.
- **modelled_on_is_a_checkable_claim**: diffed the sweep's "same rule the in-window delete loop applies" claim against the pre-existing delete loop — consistent. Confirmed `assignTemplateToDate` rejects assignment onto a completed row, so the sweep's unconditional `displaced_*` deletion (pre-Finding-7-fix) was safe by construction for the only live writer. Diffed the two widgets' `_phaseNote`/`_dayLabel` bodies byte-identical before extracting.
- **blast_radius (raw classifier output)**: `platform`, matching every staged doc's declared tier.
- **missing_input**: confirmed the sweep's date comparison normalises both sides to Y/M/D regardless of a time component on the stored ISO string; confirmed `reason:` is a real named parameter of `recordNonFatal`; re-ran the test file (19/19 at dispatch time) and `flutter analyze lib/ test/` (0/0 warnings) — both matched the author's claims.

## Author-claim checks
| claim (where) | how checked | result |
|---|---|---|
| 19/19 (then) behavioral tests pass | ran the file | confirmed, "All tests passed!" |
| `flutter analyze` 0 errors/0 warnings | ran + counted via `^\s*warning -` | confirmed, 0/0 (248 pre-existing infos) |
| Blast radius `platform` | ran the classifier | confirmed |
| `check_sot_registry_parity` passes | ran the gate | confirmed at dispatch time; re-broken by the B-2 fix's line shift, re-fixed and re-confirmed after (see Finding 7's remediation) |
| `validate_diagnose_doc` passes | ran the validator | confirmed, both before and after the remediation edits |
| `pushPlanWindow` exactly 2 call sites, absent elsewhere | `grep -rn "pushPlanWindow" lib/` | confirmed |
| Prod census A: 10 users, 369 keys, 0 past `plan_end_date` | re-ran the exact SQL, read-only, live | confirmed exactly |
| Prod census B: 369 rows, 0 past `plan_end` any status | re-ran the exact SQL, read-only, live | confirmed exactly |
| "92 files / 849 tests" census | reproduced with 9 basenames → 87/784 (Finding 10); with the correct 10 → 92/849 exactly | confirmed once the 10th basename was found |
| 5 review rounds, round 5 says converged | counted the dated round headers in the plan's Review log | confirmed, exactly 5 |
| `totalWeeks` never conflated with `requestedWeeks` by a reader | `grep -rn "\.totalWeeks\b" lib/ test/` | confirmed, both readers correct |
| Every writer of `plan_end_date` that moves the window gets the durability push | cross-checked all 6 writers | confirmed |

## Files touched and restored
Reviewer A: read-only, touched no repo file (two scratch files in the scratchpad directory only).
One disclosed `dart run scripts/build_oi_index.dart` write-attempt, confirmed a no-op via
`git diff` before and after.

Reviewer B: mutated `lib/core/services/workout_schedule_read_service.dart`,
`lib/features/ai_coach/services/regenerate_plan_planner.dart`,
`lib/features/ai_coach/services/tool_dispatcher.dart`,
`lib/core/services/sync/sync_workout.dart` — each saved via `cp` before, restored via `cp`
after, confirmed `git diff -- <path> | wc -l` → 0 after every restore. Two temporary probe test
files created, run once, and deleted (never staged).

Post-review remediation (this session, author side): edited
`lib/core/services/workout_schedule_read_service.dart` (Finding 7),
`lib/features/dev/simulation_service.dart` (Finding 6), created
`lib/features/ai_coach/widgets/diff_preview/phase_note.dart` (Finding 8), edited
`lib/features/ai_coach/widgets/diff_preview/regenerate_plan_diff.dart` +
`switch_goal_diff.dart` (Finding 8, delegate to the shared file), extended
`test/contracts/oi189_plan_end_bound_behavioral_test.dart` (+8 tests, +3 mutation legs),
corrected 4 stale citations + the census line in the diagnose-doc, corrected 2 stale
`blast_radius: account` bullets in the plan doc, corrected 3 line_ranges in
`docs/sot_registry.yaml` shifted by Finding 7's fix, updated the board (OI-189 closing bullet,
OI-174 residual bullet, both test-count lines) and regenerated `OPEN_INDEX.md`. Full
`sh scripts/pre-commit.sh` gate loop green after; `flutter test` on the OI-189 file (27/27) and
the 92-file/857-test reproducible census both green; `flutter analyze lib/ test/` unchanged at
0 errors / 0 warnings / 248 pre-existing infos.

## Founder triage notes
Findings 3, 4, 5, 6, 7, 8, 10 fixed in-batch, mutation-proven where a mutation applies (M20-M22).
Finding 11 is false_alarm (informational). Findings 2 and 9 are correctly out-of-scope residuals,
already tracked (OI-190, OI-174) rather than newly spawned. Finding 1 (P1, missing feature-flag)
resolved 2026-09-13: founder chose to waive with a written deviation over adding a kill-switch —
see `docs/plan-reviews/oi189-plan-end-bound.md`'s "Feature-flag deviation" section.

**All 11 findings are now non-pending.** `verdict:` above stays `pending` until the founder's
explicit word for the B-pass AS A WHOLE (distinct from having resolved this one finding) — per
standing instruction, only the founder's own "accepted" flips `verdict:` here and `bpass:` in
the plan-review record.
