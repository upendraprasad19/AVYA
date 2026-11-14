---
bug_id: d3a8f5
date: 2026-08-28
batch: oi89-bodyweight-floor
status: fixed
blast_radius: platform
symptom: >-
  A user whose stored profile carries no `equipment_access` is treated as a
  DIFFERENT tier depending on which of 14 code paths reads it — `basic_gym` by
  six, `full_gym` by three, `home_dumbbells` by one, `bodyweight` by three, and
  the empty string by the AI snapshot. Most of them therefore generate a full-gym
  plan for a user we know nothing about, and because the capability floor is
  scoped to the bodyweight tier, a wrong default does not merely pick wrong
  exercises — it turns the floor OFF.
concept: equipment_capability_floor
sot_registry_entry: equipment_capability_floor
writers:
  - file: lib/features/profile/screens/edit_profile_screen.dart
    method: _save (equipment_access into userBox profile)
    line: 1686
  - file: lib/core/constants/equipment_defaults.dart
    method: equipmentAccessOf (the single fallback this fix introduces)
    line: 27
readers:
  - file: lib/core/services/auth_session_bootstrapper.dart
    method_or_widget: profile bootstrap
    line: 571
  - file: lib/core/services/template_service.dart
    method_or_widget: buildFromTemplate
    line: 149
  - file: lib/features/ai_coach/services/ai_snapshot_builder.dart
    method_or_widget: buildAiContext (was the bare empty-string fallback)
    line: 90
  - file: lib/shared/services/pro_phase_advance.dart
    method_or_widget: advance (two sites, :149 bodyweight and :553 basic_gym)
    line: 553
hive_key_prefix: profile
hive_key_formula: "HiveService.instance.userBox.get('profile')['equipment_access']"
sync_methods: []
restore_methods: []
cloud_table: user_profile
cloud_columns: [equipment_access]
contract_test_path: test/contracts/equipment_access_default_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [training_history_analyzer_capability_snapshot]
cross_account_guard: true
forbidden_patterns_checked:
  - pattern: "equipment_access.\\]\\s*\\?\\?\\s*."
    absent: true
proposed_fix: >-
  One constant and one accessor in lib/core/constants/equipment_defaults.dart.
  kDefaultEquipmentAccess is bodyweight — the fail-safe direction, because a
  bodyweight plan is performable by a gym user and a gym plan is not performable
  by a bodyweight user. equipmentAccessOf also treats an empty or whitespace-only
  string as absent, which the fourteenth site needed. The AI snapshot additionally
  gains equipment_effective, the set itself rather than the tier label.
regression_test_planned:
  - test/contracts/equipment_access_default_test.dart
  - test/contracts/ui_seam_capability_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "13 sites in 12 files migrated to equipmentAccessOf; the 14th (ai_snapshot_builder) additionally emits equipment_effective. 6 behavioural + 1 source-grep test in equipment_access_default_test.dart, 6 more in ui_seam_capability_test.dart; 32 green across four capability suites, 15 in the seam suite. flutter analyze clean on all touched files." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "No Hive write added. equipmentAccessOf is a pure read over a profile map already in hand; effectiveEquipmentForSnapshot takes the map as a parameter rather than re-reading userBox, so it cannot straddle a concurrent profile write." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL. user_profile.equipment_access already exists; equipment_owned is Task 10's migration 124." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No backfill — the fix changes how an ABSENT value is interpreted, not any stored value." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this commit." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: verified, evidence: "No Edge Function reads snapshot.profile.* — docs/snapshot_contract.yaml lists readers as empty for the profile key with prompt_passthrough true. The new equipment_effective key therefore reaches Gemini only, and check_snapshot_contract.dart passes." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads equipment_access." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "The AI snapshot is the contract this touches. equipment_access can no longer be the empty string (a claim of no tier at all), and equipment_effective is added under the capability flag — omitted entirely when OFF, so the snapshot is byte-identical to its pre-batch shape until Task 9 flips it. docs/snapshot_contract.yaml updated for both, and rule 18's 10K server-side limit is unthreatened by a sorted list of at most 24 short tokens." }
impact_analysis: >-
  The profile is written at onboarding, so a missing equipment_access is not the
  common case — it is the RESTORE case, the partial-write case, and the
  corrupt-map case, which are exactly the moments a user is least able to explain
  what went wrong. Severity is higher than the frequency suggests because of the
  interaction with decision 1: the hard floor only engages at the bodyweight tier,
  so eleven of the fourteen sites defaulting upward meant the floor silently did
  not apply to precisely the users it was built for. The AI snapshot site is the
  worst of the fourteen — it did not even name a tier, it sent the empty string,
  and Gemini has no way to distinguish "no tier" from "no equipment".
---

# Fourteen readers, four answers, and a floor that switched itself off

## What was wrong

`equipment_access` is a single string on the profile. Nothing guarantees it is
present — a restore that lands a partial map, an onboarding abandoned mid-flow, a
corrupt value — and fourteen production sites each invented their own answer for
when it is not:

| default | sites |
|---|---|
| `basic_gym` | `auth_session_bootstrapper:571`, `details_screen:117`, `plan_screen:481`, `train_provider:641`, `phase2_preview_card:73`, `pro_phase_advance:553` |
| `full_gym` | `template_service:149`, `edit_profile_screen:164`, `preview_plan_provider:60` |
| `home_dumbbells` | `regenerate_plan_planner:156` |
| `bodyweight` | `onboarding_provider:381`, `pro_phase_advance:149`, `training_history_analyzer:201` |
| *(empty string)* | `ai_snapshot_builder:82` |

`pro_phase_advance.dart` disagrees with **itself** — `bodyweight` at `:149` and
`basic_gym` at `:553`.

## Why this is a floor bug, not a cosmetic one

Decision 1 scopes the hard capability floor to the bodyweight tier:
`resolveCapability` returns `null` — meaning *do not enforce* — for every other
tier, because the three gym tiers keep `queryV4`'s softer tier curation. So a site
defaulting to `basic_gym` does not merely choose gym exercises for an unknown
user. It reports a tier at which the floor does not run at all.

Eleven of the fourteen defaulted upward. The floor this batch exists to build
would have been off for every user who reached it through one of them.

## The direction of the default

`bodyweight`. Not because it is likely, but because it is the only one that
cannot hurt: a bodyweight plan is performable by a gym user, and a gym plan is
not performable by a bodyweight user. When we do not know, the honest default is
the harmless one.

## The fourteenth site

`ai_snapshot_builder:82` sent the empty string to Gemini. That is worse than any
wrong tier, because an empty string is not a tier at all — the model receives a
field that exists and says nothing, and fills the gap however it likes.

It is also the site **decision 7** was justified by. The coach was being handed
the tier *label* and left to guess what the label contained, which is how it can
recommend a barbell row to a bodyweight user and be perfectly self-consistent
doing it. It now receives `equipment_effective` — the set itself.

That producer is deliberately **not** `resolveCapabilityFromProfile`: that one is
null above the bodyweight tier by design, and the coach needs the truth at every
tier. A `home_dumbbells` user's coach should know they have dumbbells and no
barbell. `effectiveEquipmentForSnapshot` is the second producer, and
`ui_seam_capability_test.dart` asserts the two disagree at a gym tier, so a later
"simplification" that merges them reddens rather than silently reintroducing the
bug for three tiers.

The key is omitted entirely when the flag is off, rather than emitted empty. An
empty list would read to Gemini as "this user owns nothing at all" — a stronger
and more wrong claim than the pre-batch silence.

## Why a source-grep test is not enough here, and what carries the weight

The absent-pattern grep proves no site has re-grown its own fallback. It cannot
prove the shared one is *correct*, and it is blind to a site that reads the field
without a `??` at all. So the behavioural half asserts what `equipmentAccessOf`
returns for absent, null, empty, whitespace and non-String input, and six more
tests pin the snapshot producer.

The grep also had to exclude `lib/features/dev/` — the simulator drives explicit
personas, so a hard-coded tier there is the point. Without that exclusion the
regex matches 16 sites and the test stays red forever after the fix.

## Recurrence

Same class as `feedback_writer_reader_field_drift_recurring.md`: one writer, many
readers, and the readers disagreeing about what the absence of the value means.
The novelty is that the disagreement was about a DEFAULT rather than a field
name, which no field-name drift gate can see.
