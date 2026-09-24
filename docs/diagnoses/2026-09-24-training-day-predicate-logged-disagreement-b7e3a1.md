---
bug_id: b7e3a1
date: 2026-09-24
batch: oi126-training-day-predicate-unification
status: fixed
blast_radius: platform
symptom: |
  A `type: 'logged'` schedule row (written by WorkoutWriteService.markCompleted's
  no-prior-schedule branch for AI-coach-only logging, or by the restore synthesize
  path in sync/sync_workout.dart) counts as a training day for the weekly streak
  (isTrainingDayType, exclusion-shaped) but as a REST day at 11 other inline call
  sites (whitelist-shaped: type == 'workout' || type == 'custom_template'),
  including WorkoutScheduleReadService.currentPhaseCompletionRate — the direct
  input to the PRO phase-advance gate — plus the home rest-day banner, the
  calendar day-status dots, the streak-warning banner eligibility check, the
  AI-insight quick-text, the plan-integrity reconciler's heal-need check, and
  the day-detail bottom sheet (2 sites). A coach-logged or cloud-restored day
  therefore advances a user's streak while simultaneously depressing their
  phase-completion rate and being invisible to 8 other display surfaces.
  Round-1 review of this batch's own plan found 6 of these 11 sites — the
  original OI-126 board filing and the first plan draft named only 5.
concept: training_day_predicate_logged_agreement
sot_registry_entry: training_day_predicate_logged_agreement (new — see docs/sot_registry.yaml)
writers:
  - { file: lib/core/services/workout_write_service.dart, method: "markCompleted (no-prior-schedule branch)", line: 510 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "restore synthesize path", line: 985 }
readers:
  - { file: lib/core/utils/phase_completion.dart, method: "isTrainingDayType (exclusion shape, unaffected)", line: 57 }
  - { file: lib/core/utils/phase_completion.dart, method: "isPhaseCompletionTrainingType (new whitelist, widened to include logged)", line: 76 }
  - { file: lib/shared/repositories/plan_engine/plan_engine_flags.dart, method: "isRestDayConsideringLogged (the shared wrapper every call site delegates to)", line: "new" }
  - { file: lib/features/train/providers/train_provider.dart, method: "workoutDayForDate", line: 637 }
  - { file: lib/features/train/providers/train_provider.dart, method: "week builder (isRest)", line: 813 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "currentPhaseCompletionRate", line: 1412 }
  - { file: lib/features/home/screens/home_screen.dart, method: "today-card isRestDay (build)", line: 617 }
  - { file: lib/features/home/screens/home_screen.dart, method: "today-card isRestDay (row builder)", line: 792 }
  - { file: lib/core/services/plan_integrity_reconciler.dart, method: "needsHeal (isWorkout)", line: 99 }
  - { file: lib/features/home/providers/home_provider.dart, method: "calendar day status", line: 104 }
  - { file: lib/features/home/providers/home_provider.dart, method: "StreakWarningEligibility.build (isWorkoutDayToday)", line: 376 }
  - { file: lib/features/home/providers/home_provider.dart, method: "AI-insight quick-text", line: 679 }
  - { file: lib/features/home/widgets/day_detail_sheet.dart, method: "build (isWorkout)", line: 47 }
  - { file: lib/features/home/widgets/day_detail_sheet.dart, method: "_buildHeader (isWorkout)", line: 105 }
hive_key_prefix: "schedule_ — the per-date rows every reader reads the 'type' field from."
hive_key_formula: "schedule_${formatDateKey(date)}"
sync_methods: not_applicable — no sync method changed, only local read-path predicates.
restore_methods: not_applicable — the restore WRITER (sync_workout.dart:985) is unchanged; only
  downstream READERS of the type it writes changed.
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/contracts/training_day_predicate_wiring_test.dart
ist_handling: not_applicable — no date-key logic touched.
provider_invalidations: none — pure predicate change, no new write, no new invalidation needed.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — reads the current session's already-scoped schedule rows,
  no new box or query scope introduced.
forbidden_patterns_checked:
  - "Did NOT collapse isPhaseCompletionTrainingType onto isTrainingDayType wholesale — a prior
     review round tried exactly that and it was reverted in round 3 (phase_completion.dart's own
     doc comment), because phaseCompletionRate's 2 real callers need the narrower whitelist."
  - "Did NOT scope this batch to only the 5 sites the OI-126 board named — an independent live grep
     found 6 more of the identical pattern; all 11 ship in this batch per CLAUDE.md §4.2."
proposed_fix: |
  Extracted isPhaseCompletionTrainingType(type) — a whitelist widened by exactly one value
  ('logged') from the pre-existing inline predicate. Extracted PlanEngineFlags.isRestDayConsideringLogged
  as the ONE wrapper all 11 call sites delegate to (rather than 11 independent inline copies of the
  ternary, which is how the original disagreement went unnoticed at some sites and would let a
  future edit silently diverge again). Wired behind a new kill-switch
  (PlanEngineFlags.loggedCountsAsPhaseTrainingDayEnabled, default OFF) — nothing changes for any
  user until a separate, independently reviewed flip-on commit per CLAUDE.md §4.6/§4.12.4. Also
  converged a 6th, un-DRY exclusion-shape inline site (workout_schedule_read_service.dart:1709)
  onto the existing isTrainingDayType helper — pure refactor, unflagged, no behavior change.
regression_test_planned: |
  test/contracts/training_day_predicate_wiring_test.dart — source-grep proof all 11 sites delegate
  to the wrapper (not a re-inlined duplicate) + a negative check against the pre-fix ternary
  reappearing in EITHER phrasing (exclusion, used at the 5 originally-identified sites; inclusion,
  used at Task 4's 6 additionally-discovered sites). Real call-through coverage at 3 of the 11
  sites, chosen for risk + reachability: test/contracts/phase_adherence_rate_test.dart (extended)
  proves currentPhaseCompletionRate's actual output changes — the PRO-advance gate input.
  test/contracts/reconciler_needs_heal_logged_test.dart proves PlanIntegrityReconciler.needsHeal's
  actual output changes, calling the real @visibleForTesting static method.
  test/contracts/streak_warning_eligibility_logged_test.dart proves StreakWarningEligibilityNotifier's
  actual isWorkoutDayToday output changes, driven through a real ProviderContainer (not a
  hand-duplicated reconstruction of the predicate — an earlier draft of this test made exactly that
  mistake and was rewritten after round-2 review caught it). The other 8 of 11 sites rely on the
  source-grep plus flutter analyze plus the existing tests re-run in Tasks 3-4 — a stated, not
  hidden, coverage gap; closing it further (e.g. widget-pump tests for the 4 UI-layer sites in
  home_screen.dart and day_detail_sheet.dart) is out of scope for this ship-dark batch. Mutation-
  proven: reverting the wrapper to ignore the flag entirely reddens all 3 real call-through tests
  (verified in Task 6 Step 9's mutation run).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "11 call sites + 1 DRY convergence; flutter analyze clean; wiring test green, 2 real call-through tests green, mutation-proven." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No new Hive key beyond the flag itself; reads the existing schedule_* 'type' field only." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No server-side data touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function involved." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No new query; existing own-rows reads unchanged." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None involved." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No cloud contract changed — local-read-path predicate only." }
impact_analysis: |
  Severity: P2. Affects any user who has ever had a coach-logged (no prior schedule) or
  cloud-restored-synthesized training day: their phase-completion rate, PRO-advance gate input,
  streak-warning banner, and 7 other display surfaces under-report relative to their real
  (streak-counted) training days. Shipped ship-dark (flag default OFF) — zero live behavior change
  in this batch. The flip-on commit is deliberately out of scope here and needs its own full ×2
  review per §4.12.4, since it changes the PRO-advance gate and 7 display surfaces for every user
  with no further code change of its own.
---

# Training-day predicate disagreement on 'logged' rows (OI-126)

See `docs/audit/open_issues.md` OI-126 for the original board-level framing (which named only 5 of
the 11 real call sites — corrected here) and `lib/core/utils/phase_completion.dart:29-56`'s doc
comment for the in-repo explanation of why two shapes exist at all. This fix closes the one
*unintended* disagreement (on `'logged'`) without collapsing the two shapes into one — they remain
deliberately different, now differing only on truly unrecognized future type strings, which is
documented and out of scope.

## Line-number correction note (Task 7)

The plan document this diagnose-doc was generated from cited PRE-BATCH line numbers for four
reader files, since shifted by imports Tasks 3-4 added earlier in each file. The `writers:`/
`readers:` block above uses the CURRENT (post-Task-4) line numbers, independently verified via
live grep for `PlanEngineFlags.isRestDayConsideringLogged` in each file immediately before this
doc was written:

| File | Line(s) |
|---|---|
| `lib/features/home/screens/home_screen.dart` | 617, 792 |
| `lib/core/services/plan_integrity_reconciler.dart` | 99 |
| `lib/features/home/providers/home_provider.dart` | 104, 376, 679 |
| `lib/features/home/widgets/day_detail_sheet.dart` | 47, 105 |

`lib/features/train/providers/train_provider.dart` (637, 813) and
`lib/core/services/workout_schedule_read_service.dart` (1412) were already correct — both files
had their required imports before this batch (per Task 3's own verified Step 1) and so are
unshifted. The two writer citations
(`workout_write_service.dart:510`, `sync/sync_workout.dart:985`) are likewise unshifted — this
batch only touches readers.
