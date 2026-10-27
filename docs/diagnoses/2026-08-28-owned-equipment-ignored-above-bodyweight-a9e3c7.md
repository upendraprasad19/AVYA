---
bug_id: a9e3c7
date: 2026-08-28
batch: oi89-bodyweight-floor
status: fixed
blast_radius: platform
symptom: >-
  A home_dumbbells user is offered thirteen "I also have" chips in Profile —
  pull-up bar, kettlebell, bench, barbell and more — ticks one, is asked
  "Reschedule Workouts?", accepts, and receives a byte-identical plan. The app
  collects an answer, promises to act on it, and ignores it.
concept: equipment_capability_floor
sot_registry_entry: equipment_capability_floor
writers:
  - file: lib/features/profile/screens/edit_profile_screen.dart
    method: _save (equipment_owned into userBox profile)
    line: 1689
  - file: lib/core/services/sync/sync_profile.dart
    method: conditional-entry write to user_profile.equipment_owned
    line: 202
readers:
  - file: lib/shared/repositories/plan_engine/training_history_analyzer.dart
    method_or_widget: resolveCapability (returned null above the bodyweight tier)
    line: 267
  - file: lib/shared/repositories/exercise_repository.dart
    method_or_widget: queryV4 tier block (dropped rows regardless of capability)
    line: 334
hive_key_prefix: profile
hive_key_formula: "HiveService.instance.userBox.get('profile')['equipment_owned']"
sync_methods: [_syncUserProfile]
restore_methods: [_restoreUserProfile]
cloud_table: user_profile
cloud_columns: [equipment_owned]
contract_test_path: test/contracts/equipment_owned_widens_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [training_history_analyzer_capability_profile]
cross_account_guard: true
forbidden_patterns_checked:
  - pattern: "if \\(tier != 'bodyweight'\\) return null;"
    absent: true
proposed_fix: >-
  Remove the bodyweight gate from resolveCapability so it answers at every tier,
  and make capability SUBSUME queryV4's tier block rather than run alongside it.
  Both are required; either alone changes nothing.
regression_test_planned:
  - test/contracts/equipment_owned_widens_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "resolveCapability answers at every tier with an unrecognised tier resolving to bodyweight; queryV4's tier block becomes `capability == null && tierLower != null`. 8 new tests in equipment_owned_widens_test.dart, mutation-proven on BOTH legs (reverting the consumer reddens 1, reverting the producer reddens 3); 50 green across four capability suites; full suite 5054 passed 0 failed." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "No new Hive write. equipment_owned was already written by edit_profile_screen and read by resolveCapability; this changes only whether the read is acted on. Gate 19 already carries the key." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "No DDL. user_profile.equipment_owned already exists (migration 124, applied and verified 2026-08-28)." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No backfill; the fix changes interpretation, not stored values." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this commit." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: verified, evidence: "grep of supabase/functions for equipment_tier returns ZERO — it is not a cloud column and no Edge Function reads it, so nothing server-side depends on the field this fix stops treating as authoritative." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron generates plans." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "The AI snapshot's equipment_effective now uses the same unknown-tier policy as the capability producer; a test pins that the two producers agree. The snapshot's shape is unchanged." }
impact_analysis: >-
  Reach is every user of the three gym tiers who touches the new Profile picker,
  which is the majority of the user base — the bodyweight tier is the minority
  this batch was built for. Severity is not safety: nobody was prescribed
  anything unusable, and the four HARD scorecard invariants held throughout. It
  is a trust failure of the specific kind this repo has already paid for once,
  when equipment_exclusions collected a preference the engine ignored: the app
  asks a question, says it will regenerate, and does nothing. The
  home_dumbbells vertical_pull residual makes it concrete — 100% of those slots
  fall to attempt-3 because every compound vertical pull needs a bar, a cable, a
  bench or a machine, and "tell us you own a bar" was the designed remedy that
  did not work.
---

# The picker collected equipment the generator refused to read

## What was wrong

OI-89 built two halves and connected only one of them.

The **collection** half shipped complete: `edit_profile_screen` offers
`tierOwnableItems(tier)` — thirteen chips for a `home_dumbbells` user — writes
`equipment_owned` to Hive, syncs it to `user_profile.equipment_owned` (migration
124, applied), and includes the field in `computePlanChanged` so saving raises the
**"Reschedule Workouts?"** prompt.

The **consumption** half stopped at the bodyweight tier, for two independent
reasons. Fixing either one alone would have changed nothing:

1. `resolveCapability` opened with `if (tier != 'bodyweight') return null;`
   (decision 1 of OI-89 — the hard floor was deliberately scoped). `null` means
   *do not enforce*, so `queryV4`'s capability filter never ran for a gym-tier
   user.
2. Even supplied with a capability set, `queryV4`'s **tier block** independently
   dropped any row whose `equipment_tier` lacked the tier string. Chin Up is
   `[basic_gym, full_gym]`. A `home_dumbbells` user would never see it *however*
   capability was computed.

So the user ticks "pull-up bar", is told their plan will be rescheduled, and gets
the same plan back.

## Why the review rounds did not catch it

Neither the ×2 plan review nor the B-pass found this, and the reason generalises:
**both read the bodyweight tier, which is exactly where the feature works.** A
feature scoped to one tier needs checking at the tiers it is *shown* at, not the
tier it was designed for. `tierOwnableItems` returns a non-empty list for three
tiers the capability model did not reach.

## Why the fix is safe now and would not have been three commits earlier

`equipment_tier` used to carry information `equipment_needed` did not — the SoT
registry documented it as ADD-only with *"over-tags tolerated"*, a curated and
deliberately imprecise hint. Letting capability override it would have discarded
that curation silently.

The same batch flipped the invariant to **equality**:
`equipment_tier == derive(equipment_needed)` for all 292 rows, asserted both ways.
The field is now a pure function of `equipment_needed`, so the tier filter and the
capability filter compute the same thing from the same data — capability is simply
the more precise of the two, because it also knows what the user owns.

**If that equality invariant is ever relaxed, this fix must be revisited.** The
code says so at the site.

## The two things the review rounds DID catch, before any code was written

**Round 1 — the harness could not observe the fix.** No persona in the
606-persona matrix carries `equipment_owned` at all, so with or without the change
every number is identical. Shipping on those numbers would have been the
*green in every world* class this batch had already hit once, in the mirror.

**Round 2 — round 1's obvious fix was wrong.** Adding owned personas changes the
matrix size, hence every aggregate, forcing a third re-baseline in one day. The
scorecard is a *no-regression* harness; it is the wrong instrument for proving a
new capability. Correction: leave the matrix alone — its unchanged numbers are the
evidence that the no-owned path is byte-identical — and prove the widening in a
dedicated contract test.

Round 2 corrected round 1's corrections rather than surfacing new classes, which
is the §4.12.1 convergence signal.

## A fail-open path that became reachable

`EquipmentVocab.effectiveItems` returns **every canonical token** for an
unrecognised tier, and `equipment_capability_test.dart:84` pins that deliberately.
It was unreachable from production *because* `resolveCapability` gated on
`tier == 'bodyweight'` — and removing that gate is precisely what makes it
reachable. A corrupt `equipment_access` would otherwise have yielded capability =
everything, the tier block skipped, and barbell work offered at attempt 1.

The policy lives in the **producer**, not the primitive: both
`resolveCapability` and `effectiveEquipmentForSnapshot` resolve an unknown tier to
`bodyweight`, mirroring `equipmentAccessOf`'s existing fail-safe default, and
`effectiveItems` keeps its contract for the AI-coach path.

## What the two producers mean now

OI-89 had them deliberately disagree, and a test pinned the disagreement to stop
anyone merging them. That rationale is gone: both now answer at every tier and
differ only in return shape. The test was **inverted rather than deleted** — it
now pins their *agreement*, which is strictly stronger, because it catches drift
in either direction.

## Recurrence

`enable_equipment_exclusions`, whose own flag comment calls this shape *"a live
broken promise, rather than an unshipped feature"* — it was flipped ON in
2026-08-05 for exactly this reason. Second instance of collect-but-ignore in the
same subsystem, four months apart, and both times the collection half shipped
first because it is the visible half.
