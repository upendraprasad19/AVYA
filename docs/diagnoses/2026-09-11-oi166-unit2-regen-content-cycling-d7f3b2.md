---
bug_id: d7f3b2
date: 2026-09-11
batch: regen-wave-unit2
status: fixed
blast_radius: platform
related_bugs: [a9f3c7]
recurrence: >
  Fifth instance of the schedule-row-stamp-derivation class this OI (166) documents (a9f3c7's own
  `recurrence` calls itself the fourth). Same root shape as a9f3c7 — a value stamped onto a
  schedule row was computed from something OTHER than the row's own real position in the phase
  (there: the clock; here: a loop-relative counter frozen at 1..4, or omitted entirely) — but a
  DIFFERENT concrete symptom: a9f3c7 was about a single ad-hoc hotel-workout row; this is about the
  two PHASE-LAYOUT writers (`generateAndScheduleFromDate` for Edit-Profile regen, and the AI-coach
  `regeneratePlanBlock`/`switchGoal` path) both silently mislabeling or under-provisioning any regen
  that starts past week 4 of an existing phase — the state every `redoWeek4`/`holdWeek` extension,
  or simply staying subscribed past the first month, produces. `docs/sot_registry.yaml`'s
  `deload_decision_reason` entry had already independently documented and filed the C half of this
  gap (the AI-coach path writing NO current_plan blob at all) as OI-166 before this fix landed.
symptom: >
  Two related pre-fix defects, both reachable by any user regenerating a plan past week 4 of an
  existing phase (extended via redoWeek4, or simply time passing):

  (B) `generateAndScheduleFromDate` always wrote weeks 1-4 relative to the REGEN's own week
  (`monday` = Monday of `fromDate`'s week), never the phase's real `plan_start`. A regen genuinely
  at real week 6 overwrote schedule rows stamped `'week': 1..4` — wrong content (frozen at the
  deload week forever past week 4) AND a wrong label that corrupts any week-based reader
  (phase-arc strip, `getWeek`, deload eval's `week>=4` guard). The day-loop also had no per-day
  upper bound at all (`date.isBefore(today)` only) — reachable via `redoWeek4` on a non-Monday, a
  misaligned `plan_end` let rows land past the stored horizon (round 7 P0, already partially
  addressed by an earlier round of this same document's review but re-verified end-to-end here).

  (C) `RegeneratePlanPlanner.plan()` (the AI-coach `regeneratePlanBlock`/`switchGoal` tools) stamped
  every row `'week': weekIdx + 1` — always 1-based from the REQUEST, never from the phase's real
  `plan_start` — and it NEVER wrote `current_plan` at all, so the phase-arc strip and any
  `current_plan`-derived display went stale after every single AI-coach regen, not just late ones.
concept: >
  The design is: `rawWeekNumberFor(date, planStart) := (date - planStart).days ~/ 7 + 1` (Unit 1,
  unclamped) gives the row's REAL week number; `contentFlavorIndex(w) := (w-1) % 4` (NEW, this
  batch) picks which of the phase's 4 generated `weekPlans` supplies that week's CONTENT, cycling
  baseline/overreach/peak/deload past week 4 instead of freezing or indexing out of bounds. Both
  writers derive `effectiveWeek`/`week` from the row's real position and pick content through
  `contentFlavorIndex`; the `current_plan` blob is spliced (not fully rewritten) so weeks before
  `regenStartWeek` are preserved verbatim.

  Three sub-defects were found and fixed WITHIN this same implementation, before any external
  review — worth recording because two of them are new failure shapes this document's own
  9 rounds of PLAN review never had cause to reach (the plan was reviewed as prose; these are
  runtime-arithmetic divergences only visible once real Hive state is involved):

  1. WEEK-BUCKET vs DATE-RANGE divergence. The natural-looking gate for "should the current_plan
     blob be rewritten" is `regenStartWeek <= lastWeek` (both `rawWeekNumberFor`-derived week
     numbers) — but that is NOT equivalent to the literal `!today.isAfter(planEnd)` whenever
     `planEnd` is mid-week-misaligned (`planEnd % 7 != 6` relative to `planStart`, exactly what a
     redoWeek4 tap on a non-Monday produces). Worked example: `planStart=0, planEnd=30` (misaligned:
     `30%7==2`), `today=31` (genuinely past planEnd). `rawWeekNumberFor(31,0)==rawWeekNumberFor(30,0)
     ==5`, so the week-bucket gate wrongly reports "not empty" while the date gate correctly reports
     "empty". Using the week-bucket form here would have reintroduced a variant of round 5's original
     P0 (blob rewritten with zero backing rows) in exactly this narrow case. Fixed: the gate is the
     literal `!today.isAfter(effectivePlanEnd)`, matching the pre-existing delete loop's own
     `!d.isAfter(planEnd)` style exactly (`workout_schedule_read_service.dart:362`).
  2. FIRST-GENERATION `planEnd` STALENESS. `planEnd` (the pre-existing local at
     `workout_schedule_read_service.dart:358-360`) is read from Hive BEFORE `endDate` (the real,
     about-to-be-stored horizon) is even computed, so on first generation it silently falls back to
     `today + 28` (unaligned to Monday) rather than the real `endDate = monday + 27` this SAME call
     is about to write as `plan_end_date`. Reusing `planEnd` for the new write-loop bound would have
     computed `lastWeek` one week too high on first generation for any signup day other than Monday
     — worked example: `today` a Wednesday → `endDate=27` (real) vs `planEnd` fallback `=30` → wrong
     `lastWeek=5` instead of 4, writing 3 bogus "week 5" schedule rows (wrapped-around content) for
     the majority of new signups. Fixed: `effectivePlanEnd = isFirstGeneration ? endDate : planEnd`
     (`:401`) — a no-op on every regeneration, corrects only first generation.
  3. Both a return-record field AND a REPLICATED commit-site splice (`tool_dispatcher.dart`, two
     call sites) needed exact-qualifier discipline that 8 prior review rounds had already found bugs
     in for OTHER symbols in this same document: `getCachedPhase`/`getCachedRegenStartWeek` need the
     `RegeneratePlanPlanner.instance.` qualifier (the plan's own worked snippet omitted it), and the
     splice's `final box = HiveService.instance.workoutBox;` cannot be redeclared at either commit
     site — both already have an in-scope `box`/`wbox` local from the write loop immediately above.
     Both caught before compiling, not by the analyzer.
  4. A FOURTH, found in POST-IMPLEMENTATION VERIFICATION (not by the implementer, not by the analyzer
     or the test suite as first written — by an independent re-read of the diff against v10's literal
     text). C's `weekPlan` content-selection ternary was collapsed to an UNCONDITIONAL
     `phase.weekPlans[contentFlavorIndex(effectiveWeek)]`, dropping v10's second, independently-guarded
     ternary that keeps the OLD `weekIdx < length ? weekPlans[weekIdx] : .last` ("repeat-last") form
     for the explicit-startDate / no-planStart branch. Because `effectiveWeek` correctly degrades to
     `weekIdx + 1` in that branch, `contentFlavorIndex(weekIdx+1) == weekIdx % 4` for weekIdx>=4 —
     CYCLING — silently replacing the "repeat-last" behaviour v10 required stay untouched for this
     explicitly-out-of-scope branch (an AI-coach future-dated multi-week block, `weeks>4`, with an
     explicit `startDate`, would have gotten different — wrong — content for week 5 onward). Undetected
     by the first-draft test because it used `weeks: 2`, too narrow to reach `weekIdx>=4` — a
     `feedback_green_check_input_set_width` instance: the check was correct, its input set was too
     narrow to see the bug it existed to catch. Fixed by restoring the second, independent ternary
     verbatim per v10; the existing "explicit startDate" test was WIDENED (weeks:2 -> weeks:6) with a
     new assertion pinning week 5's content to `'deload'` (repeat-last), not `'baseline'` (cycling) —
     mutated once (reverted to the unconditional form), confirmed the new assertion reddens for
     exactly this reason, then re-confirmed green after restoring the fix.

     ⚠ **This sub-defect's own fix was NOT STAGED when the mandatory B-pass review ran
     (`docs/reviews/9c7cbabe4d3d-review.md`, Finding 1, P0) — the working-tree fix existed but had
     never been `git add`ed, so the staged index (what would actually have been committed) still
     carried the unconditional, buggy form this paragraph describes as fixed.** Caught by the fresh
     reviewer running `git status`/reproducing against the staged blob directly, not by re-reading the
     diff (which was read from the working tree throughout, the same source-confusion this finding is
     about). Resolved by staging both files in the same commit as this doc. Recorded here as its own
     lesson because it is a distinct failure from the sub-defect itself: verifying a fix against the
     WORKING TREE (`Read`, `flutter test`) is not the same claim as verifying it is STAGED
     (`git diff --cached`, `git status`) — the two diverge silently whenever an `Edit` lands after the
     last `git add`, and nothing about a passing test suite or a clean `Read` output reveals which one
     you checked.
  5. A FIFTH, found by the mandatory B-pass review (Finding 3, P1). Writer B's `current_plan` splice
     is gated on `writeRangeIsNotEmpty` specifically to prevent "a blob rewrite backed by zero rows"
     (sub-defect 1's own round-5 P0). Writer C's two new splices (`tool_dispatcher.dart`) had NO
     equivalent gate — only `splicePhase != null && spliceRegenStartWeek != null`, which answers "was
     this a normal (non-explicit-startDate) regen", not "did any row actually land". Both commit
     sites' write loops can skip EVERY row via the pre-existing "Concurrent-edit safety net" `continue`
     (a schedule date independently completed between `plan()`'s diff-preview computation and the
     user's Confirm tap) — so it was possible to rewrite `current_plan` with fresh cycled content
     backed by zero actual schedule writes, reopening for writer C the exact defect class writer B
     already closed. Fixed by gating both splices on `results.isNotEmpty` (the loop's own tally of
     successfully-written rows) in addition to the two existing null-checks. Regression test: "all
     rows already-completed race" (`oi166_unit2_regen_content_cycling_behavioral_test.dart`) — every
     date in a real `plan()`-computed `rawSchedules` is marked `completed` before dispatch, driven
     through the REAL `ToolDispatcher.execute` path, asserts `current_plan` stays byte-identical to a
     pre-seeded marker. Mutated once (guard reverted to the pre-fix 2-condition form): reddened exactly
     that one test (`+10 -1`), failure was the byte-identical assertion (`Expected` the stale marker,
     `Actual` a freshly-regenerated blob) — proving the rewrite-with-zero-backing-rows defect for real,
     not merely by inspection. Re-confirmed green after restoring the fix.
  6. A SIXTH, found by the mandatory B-pass review (Finding 4, P2). All three `current_plan` splice
     sites (the write-service one and both `tool_dispatcher.dart` copies) cast the existing blob's
     `week_plans` field with `as List<dynamic>?` then each element with `as Map` — both THROW (not
     degrade) if the value is present but the wrong shape, unlike this same file's own
     `currentWaveCharacters()` reader, whose doc comment states it is "Crash-safe: a missing /
     malformed / short blob returns `const []`" — the codebase's already-established defensive posture
     for this exact blob, which the new write-side splices did not carry. A thrown cast is caught by
     `ToolDispatcher.execute`'s outer catch-all AFTER `clearCache` would have run (so the cache leaks)
     and reports `'Could not execute that action.'` even when the write loop above already committed
     real schedule-row writes — a partially-successful regen surfaces as a hard failure. Fixed by
     replacing both casts with `is`-checked safe reads (`rawWeekPlans is List ? rawWeekPlans : null`,
     and an added `existingWeekPlans[i] is Map` guard clause before the per-element `Map.from` cast) at
     all three sites. Regression tests: two new cases in the same suite, each pinning ONE of the two
     casts independently — `week_plans` present-but-not-a-List, and a List whose element 0 is not a
     Map — both driven through the real dispatch path, both asserting no throw (`res.success == true`)
     and a fresh-content fallback at the malformed position. Mutated twice, once per guard, each
     against the `tool_dispatcher.dart _executeRegeneratePlanBlock` copy (the other two sites are
     byte-identical in this exact block per the B-pass's own character-by-character diff, so one
     representative mutation stands for all three): removing the `is Map` guard reddened EXACTLY the
     "entry not a Map" test (`Expected: true / Actual: <false>` on `res.success` — the thrown TypeError
     was swallowed by the outer catch-all) and left "not a List" green; removing the `is List` guard
     reddened EXACTLY the inverse pair. Orthogonal, zero collateral in either direction.
sot_registry_entry: phase_arc_display
sot_registry_note: >
  `phase_arc_display` (already the home for schedule-row week/week_character derivation per
  a9f3c7's precedent, not only the strip widget) gains its FIRST TWO current_plan WRITERS — it was
  read-only through the 7-A batch. The concept description is corrected in place (it said "NO
  writer added", true only for that batch) and the `deload_decision_reason` entry's own
  "AI-coach regen writes NO blob" claim is corrected — that gap is what tool_dispatcher.dart's new
  splice closes. No new concept: the `'week'` field and `current_plan` blob were already registered
  facts of this concept: the field family just wasn't writer-complete.
writers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "contentFlavorIndex — NEW static, content-cycling arithmetic beside rawWeekNumberFor", line: 1319 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "generateAndScheduleFromDate — loop bounds/content-index/anchor redefined to the phase's real regenStartWeek..lastWeek, day-loop gains an upper-bound check", line: 479 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "generateAndScheduleFromDate — current_plan blob splice, gated on the write range being non-empty (replaces the pre-existing unconditional write)", line: 410 }
  - { file: lib/features/ai_coach/services/regenerate_plan_planner.dart, method: "plan() — hoisted planStart/regenStartWeek, effectiveWeek replaces weekIdx+1 at all 3 stamp sites incl. both _restEntry call sites", line: 223 }
  - { file: lib/features/ai_coach/services/regenerate_plan_planner.dart, method: "plan()/cache()/getCachedPhase/getCachedRegenStartWeek/clearCache — widened return record + cache to thread Phase + a NULLABLE regenStartWeek", line: 143 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method: "_executeRegeneratePlanBlock — current_plan splice before clearCache (NEW writer; zero-rows-gated + crash-safe per B-pass findings 3+4)", line: 897 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method: "_executeSwitchGoal — current_plan splice before clearCache (NEW writer, mirrors the above)", line: 1091 }
readers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: phaseArcProvider, line: 906 }
  - { file: lib/features/train/widgets/phase_arc_strip.dart, method_or_widget: "PhaseArcStrip.build — renders current_plan.week_plans" }
  - { file: lib/features/ai_coach/widgets/diff_preview/regenerate_plan_diff.dart, method_or_widget: "_compute — widened .cache(...) call threads result.phase/result.regenStartWeek to the dispatcher", line: 51 }
  - { file: lib/features/ai_coach/widgets/diff_preview/switch_goal_diff.dart, method_or_widget: "_compute — same widened .cache(...) call", line: 64 }
hive_key_prefix: schedule_
hive_key_formula: >
  workoutBox['schedule_<yyyy-MM-dd>'] keys 'week' (now real-phase-relative on both writers, not a
  loop-relative counter) and 'week_character' (now content-cycled past week 4 via
  contentFlavorIndex). workoutBox['current_plan']['week_plans'][0..3]['week_character'] — spliced,
  not fully rewritten, by both writers above.
sync_methods: >
  Unchanged. Both writers already fire their existing fan-out
  (generateAndScheduleFromDate: unawaited syncWorkoutData()+pushSnapshot(); the AI-coach path writes
  each row via WorkoutWriteService.upsertScheduled, whose own fan-out is unchanged) — this batch
  changes only the VALUES written, not the write/sync mechanism.
restore_methods: >
  Not applicable. Neither current_plan nor the schedule-row 'week'/'week_character' fields gain a
  new restore path in this batch; a restored current_plan blob is still the last one synced,
  independent of how it was spliced locally.
cloud_table: scheduled_workouts
cloud_columns: [week_number, day_of_week, scheduled_date]
contract_test_path: test/contracts/oi166_unit2_regen_content_cycling_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 357, fn: "today = istMidnight(fromDate) — unchanged by this batch; the new regenStartWeek/lastWeek/effectivePlanEnd derivations consume this same IST-normalised value, no new clock read." }
provider_invalidations: >
  None added. generateAndScheduleFromDate's existing invalidation (via its own callers) and
  ToolDispatcher.execute's existing _invalidateWorkoutProviders(ref) (already fired for
  'regenerate_plan_block'/'switch_goal') already refresh currentPlanProvider, which now also
  reflects the spliced current_plan — no new provider watch needed.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  not_applicable — every read/write in this batch flows through the existing
  HiveService/WorkoutWriteService user-scoped box layer, unchanged.
forbidden_patterns_checked: >
  - No raw `Hive.box(` — the new tool_dispatcher.dart splices reuse the ALREADY-open
    HiveService.instance.workoutBox local from the write loop immediately above (box/wbox),
    not a fresh box handle.
  - contentFlavorIndex and rawWeekNumberFor have no `catch` above them, matching this file's own
    established guard-discipline note (currentDeloadReason / planWeekAndCharacterFor) — a
    RangeError from an out-of-bounds week index surfaces directly rather than being swallowed,
    which is what let mutation 2 below (the modulo removal) redden for the right reason.
  - `check_single_schedule_row_builder.dart` (§4.11 gate, shipped in Unit 1) still passes — this
    batch does not add a THIRD implementation of "lay out schedule rows for a phase"; it corrects
    the two existing ones (B and C) in place.
proposed_fix: >
  B (generateAndScheduleFromDate): loop bounds become `regenStartWeek-1 .. lastWeek-1` (both
  rawWeekNumberFor-derived from the phase's real plan_start), weekPlan selection becomes
  `plan.weekPlans[contentFlavorIndex(week+1)]`, the day-loop gains an upper-bound
  `date.isAfter(effectivePlanEnd)` check, and the unconditional current_plan write becomes a
  splice gated on `!today.isAfter(effectivePlanEnd)`.
  C (RegeneratePlanPlanner + ToolDispatcher): planStart/regenStartWeek hoisted ONCE before the
  weekIdx loop (never re-derived per iteration — the exact placement round 8 of this document's
  review already fought over for a sibling symbol); effectiveWeek = regenStartWeek + weekIdx
  replaces weekIdx+1 at all 3 stamp sites; the Phase + a nullable regenStartWeek thread through
  plan()'s return record, cache(), two new getters, and clearCache(); ToolDispatcher's two commit
  sites splice current_plan using the same shared formula as B, gated on both cached values being
  non-null.
regression_test_planned: >
  test/contracts/oi166_unit2_regen_content_cycling_behavioral_test.dart — 11 tests (8 original + 3
  added post-B-pass), all green against the real, STAGED fix. Pure: contentFlavorIndex weeks
  1-4/5-8/large numbers (3 tests). Behavioral B:
  extended regen writes exactly 5 days through the stored (extended) plan_end with the real week-5
  stamp and cycled current_plan content; expired regen writes zero rows and leaves current_plan
  byte-identical (round 5 P0 regression test); misaligned-plan_end regen writes no row past
  plan_end even though today shares plan_end's raw-week bucket (round 7 P0 regression test).
  Behavioral C: a late-regenStartWeek AI-coach regen driven through the REAL two-phase contract
  (plan() -> cache() -> the actual ToolDispatcher.execute(), not a hand-rolled splice) proves
  effectiveWeek lands on both a workout-day AND a rest-day row, the cache pair round-trips, and
  current_plan is non-null/spliced/cleared after the real commit-site write; an explicit-startDate
  call produces byte-identical stamping to pre-fix (regenStartWeek returns null, 'week' stays
  weekIdx+1). NEW (sub-defect 5): "all rows already-completed race" — every date in a real
  rawSchedules is independently marked completed before dispatch, driven through the real
  ToolDispatcher.execute path, asserts current_plan stays byte-identical (the zero-backing-rows
  guard). NEW (sub-defect 6, ×2): a malformed existing week_plans (not a List; a List whose element
  0 is not a Map), each driven through the real dispatch path, asserting no throw and a fresh-content
  fallback at the malformed position.

  MUTATION-PROVEN, six mutations total, each run once and reverted:
  (A) removed the day-loop's `|| date.isAfter(effectivePlanEnd)` clause — reddened exactly the
  misaligned-planEnd test, at the assertion for day 31 (a row now existed past plan_end).
  (B) reverted contentFlavorIndex's `(w-1) % 4` to bare `w-1` — reddened both tests v10 named
  (B's extended test, C's late-regenStartWeek test) PLUS 3 legitimate collateral failures (the 2
  pure contentFlavorIndex tests directly, and B's misaligned-planEnd test, which also calls
  contentFlavorIndex(5) and hit the same now-out-of-bounds RangeError as C) — all reddening via the
  same real cause (an out-of-range week index), none via an unrelated compile error.
  (C) forced writeRangeIsNotEmpty to unconditional `true` — reddened exactly the expired test (the
  current_plan byte-identical assertion), no collateral.
  (D, sub-defect 4) collapsed the guarded weekPlan ternary in regenerate_plan_planner.dart back to
  the unconditional contentFlavorIndex form — reddened exactly the widened "explicit startDate"
  test's week-5 assertion (`Expected: 'deload' / Actual: 'baseline'`).
  (E, sub-defect 5) reverted the `results.isNotEmpty` clause in tool_dispatcher.dart's
  _executeRegeneratePlanBlock AND _executeSwitchGoal splice guards — reddened exactly the "all rows
  already-completed race" test (`+10 -1`), the byte-identical assertion (`Expected` the stale
  marker, `Actual` a freshly-regenerated blob), no collateral.
  (F, sub-defect 6) two independent sub-mutations against the same site
  (_executeRegeneratePlanBlock; the other two splice copies are byte-identical per the B-pass's own
  character-by-character diff, so one representative site stands for all three): removing the
  `is Map` per-element guard reddened exactly the "entry not a Map" test and left "not a List"
  green; removing the `is List` guard reddened exactly the inverse pair. Orthogonal, zero collateral
  either direction.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ — 0 errors, 0 warnings; 45 pre-existing infos, none in the 6 edited files." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "oi166_unit2_regen_content_cycling_behavioral_test.dart seeds real Hive boxes (config/migration/exercise/user-session) and asserts schedule_* rows + current_plan directly; 11/11 green (8 original + 3 added post-B-pass), 6/6 mutations reddened as designed (3 pre-existing + 3 new, one per B-pass-fixed sub-defect)." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change; scheduled_workouts.week_number is a pre-existing bare int, unchanged shape." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data migration — this is a local generation-time fix; cloud rows self-heal on the next sync push of a regenerated row." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this batch." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "Client-only change; no Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron path touches either writer." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy change." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage object touched." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read or written." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "The C-side behavioral test drives the REAL ToolDispatcher.execute(ref, intent) dispatch path end-to-end (cache -> commit-site splice -> Hive), not a stand-in." }
impact_analysis: >
  Affects any user whose Edit-Profile or AI-coach regen starts past week 4 of their current phase —
  reachable via a redoWeek4/holdWeek extension, or simply staying on the same phase past the first
  month. Before the fix: B silently mislabeled and eventually froze schedule-row content at the
  deload week forever past week 4, and could (on a misaligned plan_end) write rows past the stored
  horizon; C always mislabeled rows 1-based-from-request and never updated current_plan at all, so
  the phase-arc strip went stale after every single AI-coach regen. After the fix, both writers
  stamp the row's real phase-relative week and cycle content correctly, and current_plan is kept in
  step with both regen paths, gated so a write-range-empty regen (already expired, no extension)
  never rewrites the blob with zero backing rows. No data migration needed — every affected field is
  regenerated fresh on the next regen; no existing row is deleted or moved by this fix itself.

  Deliberately NOT touched (explicit v10/directive scope boundary): C's explicit-startDate branch
  behaviour, C's `weeks` parameter/write-range, `redoWeek4`/`holdWeek` themselves, and converging
  B/C onto a shared schedule_row_builder.dart (tracked separately, not this batch).

  ⚠ **Residual gap, flagged by the B-pass (Finding 2, P1), deliberately left OPEN rather than fixed
  here.** `current_plan.week_plans` content now correctly cycles past week 4 — but the phase-arc
  strip's "NOW" highlight (`getCurrentWeekNumber()`, `workout_schedule_read_service.dart:1334`,
  `rawWeekNumber().clamp(1,4)`) is a DIFFERENT, unchanged, pre-existing mechanism that belongs to a
  separate SoT concept (`hold_week_identity`) this batch does not touch. Past real week 4 —
  reachable TODAY via the already-live `redoWeek4` extension, no flag required — the clamp always
  returns 4, so the strip permanently highlights index 3 regardless of which of
  baseline/overreach/peak/deload the schedule rows (and, since this fix, `current_plan` itself)
  actually cycle to for the real current week. Concretely: at real week 5, the schedule row now
  correctly gets `contentFlavorIndex(5)==0` ("baseline"), while the highlight simultaneously points
  at whatever sits at `week_plans[3]` — "deload" per this fix's own splice — and can also trigger the
  week-4 deload-reason banner. This is NOT strictly a new regression (pre-fix, `current_plan` was
  ALSO unconditionally rewritten to the same canonical order on every regen, so the same clamp
  already existed against different, frozen content) — but this fix makes the divergence VISIBLE and
  variable for the first time, where before it was at least self-consistent (frozen content, frozen
  highlight, both always "deload"). `lib/features/train/CLAUDE.md`'s `hold_week_identity` row already
  documents this clamp as a known gap relative to the not-yet-live `holdWeek` mechanism and explicitly
  warns "do NOT branch inputs where the clamped 4 is HONEST" for its other consumers (the /4 bar, the
  roadmap percentage) — a real redesign of the highlight index is out of scope for this already
  9-round-converged unit and belongs with that concept's own review, not bundled in here. Tracked as
  an explicit addition to OI-175 (`docs/audit/open_issues.md`), not silently left implied-fixed.
---

# OI-166 Unit 2 — regen past week 4 mislabeled/frozen content, AI-coach regen never touched current_plan

See the frontmatter for the full account. The short version: two writers (Edit-Profile regen and
the AI-coach `regeneratePlanBlock`/`switchGoal` tools) both derived a schedule row's `'week'` stamp
and content selection from something other than the row's real position in the phase — a
loop-relative counter capped at 4, in B's case; a bare request-relative index, in C's — so any
regen starting past week 4 either froze on the deload week forever or mislabeled real week 6+ as
week 1-4. C additionally never wrote `current_plan` at all, a gap `docs/sot_registry.yaml`'s
`deload_decision_reason` entry had already found and filed as this same OI number.

This document's own plan (`docs/audit/oi166-unit2-plan-v10.md`) survived 9 rounds of adversarial
prose review before implementation began — and implementation and verification still caught six
more issues across three separate passes, none previously visible because each only manifests
against real Hive arithmetic or a real staged/working-tree divergence rather than plan prose.
Caught by the implementer, before any external review (sub-defects 1-3): a week-bucket-vs-date-range
comparison that diverges exactly when `plan_end` is mid-week-misaligned (the precise state
`redoWeek4` on a non-Monday produces); a first-generation `planEnd` local read from Hive before the
real horizon it will shortly overwrite even exists, silently defaulting to an unaligned `today+28`
fallback; and a hand-written commit-site splice (`tool_dispatcher.dart`, necessarily duplicated
rather than shared, since B and C remain unconverged by design in this Unit) needing the exact
qualifier discipline eight prior review rounds had already spent finding bugs in for other symbols
in the same document. Caught in post-implementation self-verification, independent of the
implementer's own report (sub-defect 4): a collapsed content-selection guard that would have let an
explicit-startDate AI-coach call silently cycle content instead of repeating the last week. Caught by
the mandatory fresh-agent B-pass review, AFTER self-verification had already run (sub-defects 5-6,
plus the staging gap noted at sub-defect 4 above): a missing zero-rows guard on writer C's splice,
mirroring one writer B already had; and three throw-prone casts inconsistent with this same blob's
own established crash-safe reader. Every one of the six was caught and fixed by direct verification
against real code/state before being believed, then re-confirmed by the mutation-proof runs recorded
above — the layering itself (self-check, then an independent fresh reviewer) is what surfaced
sub-defects 5-6, which self-verification alone had missed.
