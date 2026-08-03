---
bug_id: d1f6b3
date: 2026-08-03
batch: Unit A (post-batch residuals) — closes OI-83
status: fixed
blast_radius: platform
symptom: |
  A cloud→Hive `progress` restore silently LOWERS `current_phase` (and two other lifetime
  counters) on a device that advanced locally and has not yet pushed. No guard, no telemetry,
  no trace: the user opens the app, a routine restore runs, and their phase goes backwards.

  Two of the seven `put('progress', …)` writers copied the PostgREST row in wholesale as
  `{...local, for (e in cloud.entries) if (e.value != null) e.key: e.value}` — cloud-non-null-wins
  for EVERY key. The advance-side monotonic guard shipped as `c8f3d1` sits on
  `commitPhaseAdvance`, which neither of these writers calls.

  Second-order effect, same root: because these writers do not take the shared phase-advance
  lock, one can bump `current_phase` WHILE a phase advance is inside that lock running
  `generateAndSchedule`. `commitPhaseAdvance` then correctly declines the counter write — but
  the `schedule_*` rows and the plan window generation already wrote for the phase we did not
  advance to were left describing a phase the user is not on.
concept: phase_progress_current_phase (cloud→Hive restore merge half)
sot_registry_entry: phase_progress_current_phase
writers:
  - { file: lib/shared/repositories/user_repository.dart, line: 299, method: mergeCloudProgress (NEW — the pure local-max-wins merge) }
  - { file: lib/shared/repositories/user_repository.dart, line: 235, method: monotonicProgressFields (the guarded set — 3, after round 1 removed longest_gap_days) }
  - { file: lib/core/services/sync/sync_profile.dart, line: 628, method: _restoreUserProgress — demotion vector 1, now routed }
  - { file: lib/core/services/auth_session_bootstrapper.dart, line: 331, method: post-auth progress pull — demotion vector 2, now routed }
  - { file: lib/shared/services/pro_phase_advance.dart, line: 391, method: reportDeclinedAdvanceLeftStaleRows (NEW — REPORTS the stale-rows condition; repair filed as OI-85) }
  - { file: lib/core/services/plan_integrity_reconciler.dart, line: 112, method: reconcile returns PlanReconcileOutcome instead of void (observability only, no behaviour change) }
readers:
  - { file: lib/shared/repositories/user_repository.dart, line: 79, method: reportProgressDemotionsDeclined (shared telemetry emitter) }
  - { file: lib/shared/services/pro_phase_advance.dart, line: 211, method: runProPhaseAdvance reports the decline it used to discard }
  - { file: lib/features/train/screens/graduation_screen.dart, line: 746, method: _onPro reports the decline inside the lock }
  - { file: lib/core/services/auth_session_bootstrapper.dart, line: 373, method: login-restore plan regen now reads the GUARDED phase from Hive, not the raw cloud row (B-pass F1) }
  - { file: lib/features/train/providers/train_provider.dart, line: 540, method: CurrentPlanNotifier reads current_phase (unchanged reader) }
  - { file: lib/features/train/providers/train_provider.dart, line: 591, method: second current_phase read feeding the plan views (unchanged reader) }
hive_key_prefix: "userBox['progress'] — a single map key, not a prefixed row family"
hive_key_formula: "userBox.get('progress') → Map<String,dynamic>; monotonic sub-keys current_phase | deployments_complete | total_workouts_done"
sync_methods: _syncUserProgress (Hive→cloud push, unchanged), syncProgressNow (fired by updateProgress, unchanged)
restore_methods: _restoreUserProgress (sync_profile.dart), auth_session_bootstrapper post-auth progress pull — BOTH fixed in this batch
cloud_table: user_progress
cloud_columns: current_phase, deployments_complete, total_workouts_done, longest_gap_days, current_week, current_streak_days, current_streak_weeks, streak_progress_version
contract_test_path: test/contracts/progress_restore_monotonic_behavioral_test.dart
ist_handling: not_applicable — these are counters and a phase index, not date keys; no IST boundary is involved
provider_invalidations: currentPlanProvider, todayWorkoutProvider (unchanged — fired by the existing advance paths, not by the restore merge)
telemetry_op_types: progress_restore_demotion_declined, progress_restore_field_malformed, phase_advance_declined_rows_stale (all three HIGH-priority, both twin lists), phase_advance_declined_report_failed
cross_account_guard: not_weakened — both restore writers already run inside an owner-scoped session (GuardedBox / HiveUserSession); the merge is a pure function over two maps and adds no new Hive access path
forbidden_patterns_checked: |
  - No raw Hive.box( introduced — the merge is pure; both callers keep their existing box handle.
  - No `as num?` cast on a possibly-non-numeric value (that form THROWS rather than yielding
    null; caught by this unit's own malformed-row test and replaced with an `is num` test).
  - No new unawaited without an error sink — the only unawaited calls wrap ErrorTelemetry,
    which is itself the sink.
  - No `| head` on any completeness grep (the Unit 6 lesson): the 7-writer enumeration is the
    full, unpiped output of `grep -rn "put('progress'" lib/`.
  - No deferral: every finding from both review rounds is fixed here. The second-order half
    (repairing the rows a declined advance leaves behind) is REPORTED here and its repair filed
    as OI-85 with all three refuted mechanisms recorded — a §4.12.1 split with a terminal board
    record, not a silent drop. What ships is strictly better than main, which has neither the
    guard nor any visibility of the condition.
proposed_fix: |
  1. Pure `UserRepository.mergeCloudProgress` — cloud-non-null-wins for every key EXCEPT the 3
     monotonic ones, which take max(local, cloud). Returns the merged map plus the refused
     demotions so the callers, not the merge, emit telemetry. §4.6 kill-switch
     `disable_progress_restore_monotonic_merge` (round-1 P2: `platform` tier REQUIRES a
     feature_flag per `docs/blast_radius.yaml:25`, and this is a per-field judgement list, not a
     total order — round 1 proved the list can be wrong).
  2. Both demotion-vector writers route through it, and both call the shared
     `reportProgressDemotionsDeclined` so their telemetry cannot drift.
  3. `reportDeclinedAdvanceLeftStaleRows` makes the second-order condition VISIBLE for the first
     time (`phase_advance_declined_rows_stale`, carrying intended vs live phase). It does NOT
     repair — three mechanisms were designed and each refuted, the last two by review; see that
     function's doc comment and OI-85. `PlanIntegrityReconciler.reconcile` returns a
     `PlanReconcileOutcome` instead of `void` so no caller can report a repair a silent
     early-exit never performed.
  4. Correct the comment at sync_profile.dart:592-609, which justified the wholesale merge with
     a premise that is true for streak_progress_version and false for a client-advanced field.
regression_test_planned: |
  test/contracts/progress_restore_monotonic_behavioral_test.dart (23 tests) —
  group A carries the PRE-FIX merge expression inline as a negative control and asserts it
  demotes on the identical input the fixed helper holds, plus the kill-switch, the
  longest_gap_days exclusion, the malformed-value cases and the ABSENT-local reinstall pin;
  group B pins the merge→Hive→read chain; group C pins that a refusal is observable (the silent
  half of the bug); group D pins that the declined-advance condition is REPORTED with both
  phases and that reporting never throws back at the caller — a bug this test found, the first
  version used unawaited() and so put the failure outside its own try; group E pins WHY the
  condition is reported rather than repaired: needsHeal cannot see it, and the merge's
  local-wins swap guard that a repair would have to override is pinned so the refuted mechanism
  cannot quietly return.
  test/contracts/restore_progress_uses_shared_merge_test.dart (8 executed) — routing pin;
  source-grep, presence-only, comments stripped first. Includes the B-pass F1 pair: the login
  restore's plan regen must NOT read the raw cloud current_phase, and MUST read the post-merge
  Hive value (both halves, so deleting the block cannot pass).
  Total 31 executed, all green; 87 green across the 7 affected suites. NOTE the routing file
  declares 5 `test(` but EXECUTES 8 — three sit inside a `for (final path in writers)` loop over
  2 writers. Count by running, not by grepping: `grep -c` and the runner's trailing `+N` (which
  includes tearDownAll) disagree, and that is how three earlier drafts of this doc published 22,
  26 and 29.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze 0 warnings/errors from this diff; 6 files under lib/ + 1 Edge Function twin list; 85 tests green across the 7 affected suites" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "group B writes a locally-advanced progress map, merges a lower cloud row, puts, and reads back through UserRepository.getProgress() — current_phase 5 survives a cloud 2" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "backups/live_schema_columns.json user_progress carries all 3 monotonic columns as int4; no schema change in this batch" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "client-side merge only — no rows are rewritten by this fix" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this batch" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: verified, evidence: "log-client-error/index.ts HIGH_PRIORITY_OP_TYPES gains the 2 new restore events, keeping the client/server twin in sync (test/contracts/high_priority_op_types_parity_test.dart green). CODE ONLY — NOT DEPLOYED: an Edge Function deploy needs its own explicit founder authorization per CLAUDE.md 4.3, so the live function still classifies these 2 events as LOW priority until that go is given. The client-side bypass is live regardless; only the server-side rate-limit class lags." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron path touched" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change; the restore read is unchanged" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no Storage object touched" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret referenced" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no third-party integration touched" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "the cloud read is byte-identical (bare .select() on user_progress); only the client-side merge of that payload changed, so no request/response shape moved" }
impact_analysis: |
  WHO IS AFFECTED. Any user with more than one install/device, or any user whose local state ran
  ahead of the last successful push — a network blip between an advance and its sync is enough.
  A genuine reinstall is NOT affected: local is empty, so max(local, cloud) is the cloud value
  and the merge is byte-identical to the pre-fix behaviour.

  BLAST RADIUS. **platform**, measured on the full staged set — and the plan predicted `account`,
  wrongly. Per-file attribution: `lib/core/services/sync/sync_profile.dart` is the platform-tier
  path; `auth_session_bootstrapper.dart`, `plan_integrity_reconciler.dart`,
  `user_repository.dart`, `pro_phase_advance.dart` and `graduation_screen.dart` are each
  `account`. Consequences that follow from the tier, not from taste: `bpass: accepted` is
  REQUIRED (not advisory), and `docs/blast_radius.yaml:25` requires a `feature_flag` — which is
  why the kill-switch below exists. Hermes is NOT required (catastrophic-only). No migration.
  The only Edge Function touched is `log-client-error`'s twin op-type list, and it is NOT
  deployed — that needs its own explicit go.

  WHAT WAS DELIBERATELY NOT DONE, and why. The approved plan said the restore writers would
  take the shared phase-advance lock. Reading the primitive first showed that is WRONG:
  `withPhaseAdvanceLock` is a TRY-lock — it returns `ifBusy` immediately rather than queueing —
  so a restore arriving mid-generation would have been turned away entirely and the user's
  cloud progress would never have landed. That trades a phase demotion for a DROPPED RESTORE,
  which is strictly worse, and the lock's own doc comment records that a prior review round
  already found one starvation bug of exactly that shape. The restore therefore stays lock-free
  and monotonic, and the loser of the race repairs its own rows instead.

  KILL-SWITCH `disable_progress_restore_monotonic_merge`, default OFF (guard active). The first
  draft argued NO switch was needed — "a switch whose only effect is to re-enable a silent
  demotion is not a safety valve", the reasoning `phaseAdvanceTarget`'s own doc uses. Round-1
  review refuted it on two grounds and both hold: (1) the measured tier is `platform`, and
  `docs/blast_radius.yaml:25` makes `feature_flag` a REQUIREMENT there, not a judgement call;
  (2) more importantly, `phaseAdvanceTarget` is a total order over ONE field while this is a
  per-field JUDGEMENT LIST — and round 1 proved the list can be wrong by catching
  `longest_gap_days` pointing the guard backwards. A wrong entry in a hand-written list needs a
  runtime escape hatch; a proven-correct total order does not. This is NOT ship-dark (§4.12.4):
  the flag is default-OFF-meaning-ACTIVE, so the new behaviour is live and the full ×2 + B-pass
  applies.

  RECURRENCE. Fifth instance of feedback_monotonic_field_recompute_demotion. Siblings: 3a7b9f
  (rank demoted by a recompute-from-current-state overwrite), c8f3d1 (the phase-advance half of
  this same field), and the two GREATEST guards migration 115 needed on total_workouts_done and
  deployments_complete server-side. The pattern is now four-for-four: every writer of a
  lifetime/earned field that recomputes rather than increments needs an explicit guard, and the
  RESTORE direction is the one that keeps getting missed because the guard gets attached to the
  domain operation instead of to the field.
---

# Restore merges demote monotonic progress fields (OI-83)

## The seven writers, and which two were actually vectors

The board filed two writers and said two more "want the same audit". This is that audit —
`grep -rn "put('progress'" lib/`, unpiped, all seven read:

| writer | shape | vector? |
|---|---|---|
| `sync/sync_profile.dart:628` `_restoreUserProgress` | wholesale cloud-non-null-wins | **YES** |
| `auth_session_bootstrapper.dart:331` | wholesale cloud-non-null-wins | **YES** |
| `sync/sync_restore_completeness.dart:242` | read-modify-write, freeze keys only | no |
| `sync/sync_restore_completeness.dart:411` | read-modify-write, freeze keys + version | no |
| `sync_service.dart:2158` `_stampProgressVersion` | version only, already monotonic (Hermes C6) | no |
| `streak_freeze_clamp_migrator.dart:98` | freeze keys only | no |
| `user_repository.dart` `saveProgress` | already max-guards `deployments_complete` | no |

The five non-vectors all re-read the map from Hive immediately before writing and mutate a
narrow, non-monotonic key set. They preserve whatever `current_phase` is there. Recorded so the
next audit does not re-derive it.

## The comment that justified the bug

`sync_profile.dart:592-609` explained the wholesale merge as safe because *"a fresh restore read
is always at least as new as whatever's local."* That is true of `streak_progress_version` — the
server-owned counter the sentence was actually written about — and false of a client-advanced
field: a device that advanced locally and has not pushed holds state strictly newer than the row
the read returns. The comment is corrected in the same commit; leaving it would have re-justified
the bug for the next reader.

## Founder decision

Locked 2026-08-03: **local-max-wins** on the monotonic fields, with telemetry. The alternative
considered was version-arbitration on `updated_at` / `streak_progress_version`, which would be
needed only if a deliberate BACKWARD move had to propagate across devices. It does not today:
the only two writes that lower the phase are onboarding's first write on a fresh account
(nothing to demote) and the dev-panel `resetJourney` (`simulation_service.dart:108`, debug-only).
If a user-facing "restart my journey" ever ships, that is the moment to revisit — written down
here rather than left as an unstated assumption.

## Why exactly three fields — and why the fourth was removed

`current_phase`, `deployments_complete`, `total_workouts_done`. Excluded, each for a stated
reason in the helper's doc comment: the streak counters (a streak legitimately resets to 0 —
max-wins would make a broken streak un-resettable), the freeze family (already merged by
`StreakProgressService.mergeFreezeProgress`; two merge rules over one field is how drift starts),
and `streak_progress_version` (server-owned optimistic-lock counter — adopting a higher local
value would make the next RPC fail its version check).

**`longest_gap_days` was in the list, and round-1 review was right to take it out.** It reads as
monotonic ("longest ever") but it is INVERTED: higher is WORSE, and it gates a rank —
`rank_service.dart:506` fails the rung when `longestGapDays > gate.maxGapDays`, and a failed rung
blocks every rung above it (`:472-481`). `grep -rn longest_gap_days lib/` finds one reader
(`rank_service.dart:448`) and two cloud pushes (`sync_profile.dart:115,320`) — **no Hive writer
at all** — and migration 115 already GREATESTs it server-side. So local-max-wins there could only
ever REFUSE a server correction: one bad value reaching Hive would pin the rank ladder shut
permanently, and every refusal would be logged as a successfully-defended demotion. Max-wins on a
field whose maximum is the bad outcome is a guard pointed the wrong way. Recorded at length
because "it sounds like a lifetime counter" is exactly how it got onto the list.

## Round-1 review — 7 findings, and one P0 the fixes introduced

Round 1 (context-blind, Opus) returned 1 P1, 4 P2, 2 P3. All seven were verified against the
cited file:line before any was acted on, and all seven were real.

**The P1 is the one worth remembering: the repair was inert.** `force: true` got past
`needsHeal`, but `PlanIntegrityReconciler.mergeScheduleEntry:77-80` then applied *the same
predicate per row* — "local already has its exercises → keep local" — and the superseded rows
this repair exists to replace all have their exercises. Every workout day came back unchanged;
only rest days healed. The fix needed `preferSnapshot:` as well, and the tests that now prove the
flag load-bearing use the default mode as their negative control. **A bypass on the outer gate is
not a bypass on the inner one** — the same shape as Unit 6's "a green check is only as wide as
its input set".

The other confirmed findings: the success telemetry fired unconditionally while `reconcile`
returned `void` and swallowed every exception through six early-exit paths, so the event would
have reported 100% repair success at a 0% repair rate and the `catch` was unreachable (fixed by
`PlanReconcileOutcome`); the two new events were absent from `highPriorityOpTypes`, so a degraded
backend — exactly when mass demotions would occur — would have dropped the evidence
(`feedback_backend_collapse_blinds_telemetry`, c4f8d2); the platform tier requires a
`feature_flag`; the new block had been inserted between `saveProgress`'s doc comment and
`saveProgress`, orphaning the F18 rationale onto a `const List`.

**Then the P3 fix introduced a P0, caught by this unit's own reinstall test.** Making a
non-numeric value keep the local side treated an ABSENT local value (`null is! num`) as
malformed and skipped the key — so a reinstalling user would have restored with **no
`current_phase` at all**. Absent is not malformed; it is the single most common path through this
function. Fixed, and pinned by a named regression test. This is the §4.12.1 signature again: the
correction, not the original work, is where the next defect comes from.

## A defect the tests caught in the fix itself

The first draft read both sides with `(v as num?)?.toInt()`, mirroring the cloud-payload idiom at
`sync_profile.dart:100`. That cast **throws** on a non-numeric value rather than yielding null, so
the "a malformed row must not break the whole restore" intent was a lie — the first bad row would
have thrown out of the merge and aborted the restore for every field. The malformed-row test
failed on the first run and the read became an `is num` test. Worth recording because the idiom it
copied is correct in its own context: there, the value is known-numeric by schema.
