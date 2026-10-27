---
bug_id: b9d4c2
date: 2026-08-25
batch: oi60-client-blockers
status: fixed
blast_radius: platform
id_collision_note: >
  Minted as d3b8f1 and RENAMED to b9d4c2 before merge. d3b8f1 already named an
  unrelated doc — docs/diagnoses/2026-08-15-cleanup-delete-boundary-keyed-on-uuid-d3b8f1.md,
  landed in acffbd43 — so the commit trailer `closes-diagnose: d3b8f1` was ambiguous
  between two different bugs. Caught by the B-pass. ⚠ NOTHING DETECTS THIS CLASS:
  scripts/validate_diagnose_doc.dart takes one path and never scans the corpus for
  duplicate ids, and there is no diagnose-id equivalent of
  scripts/check_oi_numbering_unique.dart — which exists precisely because the OI-number
  version of this bug shipped six times. Filed as OI-140.
symptom: >
  A free user who took a "Hold the Line" week has their phase completion rate diluted by the hold
  days. Measured on a seeded reproduction: 28 of 28 prescribed days COMPLETED, two holds taken,
  current_phase 2 with plan_start not moved — currentPhaseCompletionRate() returned 0.6667 instead
  of 1.0. A perfect record scores two-thirds. Once enable_adherence_gate flips on,
  shouldOfferAdvanceChoice reads that as low adherence and offers the "detrained / repeat the
  phase" path — to the user who chose to STAY rather than churn. Currently INERT in production:
  both readers &&-short-circuit on enable_adherence_gate, which is default OFF.
concept: >
  Hold rows leaking into a reckoning that is about PRESCRIBED work. getWeek() is purely
  date-driven off plan_start and knows nothing about is_hold, so any consumer that walks weeks by
  date inherits hold rows silently. The phase>=2 branch scans weeks 5-12 by date, which is exactly
  where holds live (plan_start+28 onward). The dilution is one-directional — it can only push the
  rate DOWN, and only for a user who held.
sot_registry_entry: >
  None added. currentPhaseCompletionRate() is a pure derivation over rows the existing
  workout_schedule SoT concepts already register (holdWeek() as writer of is_hold/hold_ordinal;
  the read service as reader). This fix adds no new field and no new writer — it corrects which
  rows an existing reader counts, so there is no new writer/reader pair to register.
writers:
  - { file: lib/core/services/workout_schedule_write_service.dart, method: "holdWeek() — stamps is_hold / hold_ordinal on each copied schedule row", line: 236 }
readers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "currentPhaseCompletionRate() — the phase>=2 scan and the days accumulator", line: 1129 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "_withoutHoldRows() — the new filter", line: 1170 }
  - { file: lib/features/train/screens/graduation_screen.dart, method: "shouldOfferAdvanceChoice(completionRate:) — gated behind adherenceGateEnabled", line: 377 }
  - { file: lib/shared/services/pro_phase_advance.dart, method: "repeatContent = adherenceGateEnabled && currentPhaseCompletionRate() < threshold", line: 168 }
hive_key_prefix: "schedule_ — the per-date workout schedule rows the hold writer stamps and this reader walks."
hive_key_formula: "schedule_${formatDateKey(date)}, resolved by getScheduleForDate; getWeek(w) walks 7 dates from plan_start + (w-1)*7."
sync_methods: not_applicable — this fix changes a local derivation only; no sync method reads or writes the completion rate.
restore_methods: not_applicable — the completion rate is derived on demand, never persisted, so nothing restores it.
cloud_table: none — currentPhaseCompletionRate() is computed entirely from Hive schedule rows.
cloud_columns: none — see cloud_table.
contract_test_path: test/contracts/phase_completion_excludes_holds_behavioral_test.dart
ist_handling: >
  not_applicable to the fix itself — no new date key is formed. The rows walked are keyed by
  formatDateKey, which is the existing IST-based helper, and this change does not alter that.
provider_invalidations: none — no provider caches the rate; both readers call it inline behind a flag.
telemetry_op_types: >
  None added. The rate is consumed synchronously by a gate decision, and the meaningful signal
  (whether a holder was wrongly offered the repeat path) does not exist yet because
  enable_adherence_gate is OFF. Adding an op_type now would emit a metric that can only ever be
  zero — the failure mode feedback_mistake_fixed_callsite_without_reading_callee names.
cross_account_guard: >
  not_applicable — reads flow through the existing user-scoped box helpers unchanged; no new box
  access is introduced.
forbidden_patterns_checked: >
  Checked and clean. No Container with color+decoration, no inline isPro, no client-side API key,
  no raw flutter build. The repo-specific pattern that DID apply is writer/reader drift: holdWeek()
  writes is_hold and this reader never read it. Named per §4.1 before the fix was written.
proposed_fix: >
  Filter is_hold rows out of the days accumulator via a new _withoutHoldRows() helper. Deliberately
  UNGATED on enable_hold_weeks, matching the established precedent at completedWeekNumbers
  (:1032), which excludes is_hold with no flag check either — the two are the non-hold day-sources
  for closely-related ratios and must not drift. Gating would leave the rate wrong for the one
  population that can hold rows while the flag reads OFF (held once, flag later turned off). Rows
  only carry is_hold if holdWeek() ever ran, so for every user who never held the filter is a
  no-op and behaviour is byte-identical. The `scanned` loop deliberately walks the RAW week — see
  the round-2 note below.
regression_test_planned: >
  7 cases, mutation-proven. Restoring the two unfiltered getWeek(w) calls (the real regression)
  reddens 4; the 3 that stay green are deliberate no-op controls (no holds taken, phase 1, and the
  hold-only-week case). A SECOND mutation covers a bug review round 2 constructed in the first fix
  attempt: filtering the `scanned` loop as well made a fully-hold week 5 read empty, break the
  scan, and silently drop real phase-2 weeks 7+ from BOTH numerator and denominator — inflating
  the rate. Re-applying that reddens the dedicated round-2 regression test. The scan now walks the
  raw week (holds EXTEND the schedule even though they must not COUNT); only the accumulator
  filters.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "workout_schedule_read_service.dart currentPhaseCompletionRate + new _withoutHoldRows; flutter analyze clean; 7/7 behavioral tests green." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "Reproduction seeds real schedule_ rows through WorkoutWriteService.upsertScheduled and materializes holds through the real holdWeek() writer, so the field names are exercised end to end rather than asserted." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL; the rate is a local derivation." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No table read or written by this path." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration; backups/applied_migrations.json untouched." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function reads the completion rate." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron consumes it." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy involved." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None involved." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "Purely local; the rate never crosses the wire." }
impact_analysis: >
  Severity: P2 today, P1 the moment enable_adherence_gate flips. Zero live impact right now
  because both readers short-circuit on that flag (verified by reading each call site). The
  affected population is exactly the free users the hold mechanic exists to retain, and the harm
  is one-directional: it can only under-report adherence, never over-report, so it can only ever
  wrongly offer the repeat path — never wrongly withhold it. This is a flip-on blocker for OI-60
  (FOB-7a) and had to land before enable_hold_weeks or enable_adherence_gate goes live.
---

# Hold days dilute the phase completion rate (FOB-7(a) / OI-60)

## How reachability was settled

Three rounds on the OI board and round 1 of this batch's own plan review each reasoned about
whether the `phase >= 2` branch can see hold rows, and produced **four different answers**. Round 1
recommended settling it by execution instead. Seeding the state directly answered it in one run:

```
getWeek(5)=7  getWeek(6)=7  getWeek(7)=0
w5 first row is_hold=true
currentPhaseCompletionRate() = 0.6666666666666666
```

The precondition — `current_phase >= 2` while `plan_start` has not moved past the holds — is not
hypothetical. `docs/diagnoses/2026-08-09-past-phase-display-and-expired-copy-c9e4b7.md` records a
real production account in exactly that state (2026-08-05: `current_phase=2`, `plan_start` unmoved,
77 rows spanning ~13 weeks) and states the writer responsible is unconfirmed and NOT FIXED.

**The mechanism the plan originally named was wrong.** Round 1 established that
`generateAndScheduleFromDate` never writes `current_phase` at all, so it cannot reach the branch in
question. The real writers that raise `current_phase` without moving `plan_start` in the same call
are `phase_progress_reconciler.dart:138` and the restore path `sync/sync_profile.dart:628`.

## What is deliberately NOT changed

`train_provider.dart:767-777` — the Train card's own `totalWeeks` scan — keeps counting hold weeks.
What the Train screen renders during a hold is **FOB-6**, split out by founder as **OI-125**, a
feature that explicitly does not gate the `enable_hold_weeks` flip. Filtering the card here would
ship half of OI-125 by accident. The "mirrors the card exactly" comment on
`currentPhaseCompletionRate` is updated to record that the mirror is now deliberately imperfect,
and why.

## Related

- Plan-review record: `docs/plan-reviews/oi60-client-blockers.md` (2 rounds, converged).
- Sibling fix in the same batch: `2026-08-25-reconciler-never-heals-hold-weeks-e7c4a2.md` (FOB-7b).
- Board: OI-60. This closes FOB-7(a) only; FOB-3, FOB-4 and OI-127 remain open with their own
  terminal states in `docs/audit/oi60-client-blockers.closure.yaml`.
