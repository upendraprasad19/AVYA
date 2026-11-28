---
bug_id: d214ed
date: 2026-11-25
batch: oi447-roadmap-deployment (OI-447)
status: fixed
tier: s_fix
blast_radius: feature
related_bugs: [b7f1c8]
recurrence: "Recurrence of b7f1c8 (the Train screen's eyebrow was a hardcoded 'DEPLOYMENT 01'; fixed there, then the eyebrow was removed 2026-11-01). The same literal survived on the Roadmap screen because the fix named one reader, not every surface that prints the deployment number."
symptom: |
  A PRO user past week 12 (phase 5 = Deployment 02) opened the Roadmap and read `DEPLOYMENT 01 · <phase name>` over the right `WK n / 12`, with nothing saying Deployment 01 was finished, and the long-term rank ladder (YEAR 1 to YEARS 3-5) had no "you are here" row.
concept: roadmap_deployment_position
sot_registry_entry: not_applicable
writers:
  - { file: lib/shared/services/pro_phase_advance.dart, method_or_widget: "commitPhaseAdvance writes user_progress.current_phase (unchanged by this batch; the phase is the only input)", line: 1 }
readers:
  - { file: lib/features/train/screens/phase_roadmap_screen.dart, method_or_widget: "_DeploymentHeader: the literal 'DEPLOYMENT 01' (was line 224); now takes deploymentNumber from roadmapDeploymentNumber(phase)", line: 348 }
  - { file: lib/features/train/screens/phase_roadmap_screen.dart, method_or_widget: "RoadmapBody: completed-deployment rows and the ladder marker (roadmapLadderMarkerIndex)", line: 235 }
hive_key_prefix: none
hive_key_formula: "not applicable: display only, no new key"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: [current_phase]
contract_test_path: test/features/train/phase_roadmap_deployment_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable: pure display of values the screen already read (current_phase, week in phase, hold ordinal)."
forbidden_patterns_checked:
  - { pattern: "a literal 'DEPLOYMENT 01' in lib/features/train/screens/phase_roadmap_screen.dart", absent: true }
proposed_fix: |
  Founder chose both halves in the OI. (a) The deployment number is derived from the phase, `(phase - 1) ~/ 3 + 1`; each earlier deployment is a `DEPLOYMENT NN · COMPLETE` row above the unchanged 12-week layout; the hold-week header behaviour is kept. (b) A `YOU ARE HERE · PROGRAM WEEK n` row on the rank ladder at the ABSOLUTE program week `(phase - 1) * 4 + week in phase`, placed before the first ladder row with a later week. It shows only past week 12: inside the first deployment the active phase block already marks the position. While holding it reads `HOLDING AFTER WEEK n`, never a new week.
  The screen body moved into `RoadmapBody`, which takes plain values, so it can be pumped without Hive or a provider scope. The ladder rows are now one list (`_ladder`) instead of nine hand-written markers.
  Decision for review: the marker uses PROGRAM weeks (as the OI says), while the ladder labels are weeks of SERVICE (calendar, `minWeeksSinceSignup`). A user who held or let a phase lapse can be a few weeks behind on the ladder's own clock; the caption says PROGRAM WEEK so it never claims a rank.
regression_test_planned: |
  test/features/train/phase_roadmap_deployment_test.dart (10 tests): pure helpers; RoadmapBody for phases 1, 4, 5, 12 and the hold arm.
mutation_proof: |
  Rule 21, mutate / run / restore, on the real file, each applied (grep -c = 1): header literal back to 'DEPLOYMENT 01' (3 red), completed-deployment loop `<` to `<=` (2 red), marker threshold `<= 12` to `< 12` (1 red). File restored byte-identical (diff against the saved copy).
impact_analysis: |
  Display only, one screen. A phase-1 user sees the same header and no extra rows. The existing source-grep tests that cite the file (purchase_literal_inventory, purchase_surfaces_mode_none, phase_relative_week_label, rank_widget_migration, hold_week_identity_behavioral) still pass. Not changed on purpose: plan_header.dart prints 'DEPLOYMENT 01' while a free user holds; holds exist only in phase 1, so it is true there.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "phase_roadmap_screen.dart; flutter analyze clean; 131 tests green across the new file and the contract tests that cite the screen." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Reads only user_progress.current_phase and the week-in-phase through the same services as before; nothing written." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client to server contract", status: not_applicable, evidence: "Display only; no request." }
---

# Roadmap stuck in Deployment 01 (OI-447)

Writer: `commitPhaseAdvance` moves `current_phase` forward. Reader: the Roadmap screen, which folded the phase into 1-12 with `programWeekFor` for the counter and printed a literal for the deployment. Not device-checked: the founder's check on a phase-4+ account (a hold-free phase 5 is the case in the OI) is the remaining step.
