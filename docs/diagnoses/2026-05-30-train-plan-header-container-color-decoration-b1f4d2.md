---
bug_id: b1f4d2
date: 2026-05-30
batch: web-e2e-2026-05-30
status: fixed
symptom: >
  Live web (amar@gmail.com): the Train tab renders "Failed to load workouts /
  Tap to retry" even though Home's Today card shows the same plan correctly
  (PHASE 1 / UPPER / 70 MIN · 7 EX). RETRY does not recover. The
  train_screen_build_failed telemetry carries: "Assertion failed:
  container.dart:277 — color == null || decoration == null — Cannot provide
  both a color and a decoration."
concept: train_plan_header_render
sot_registry_entry: n/a
blast_radius: feature
writers:
  - { file: lib/features/train/screens/train/plan_header.dart, method: _buildPlanHeader, line: 26 }
readers:
  - { file: lib/features/train/screens/train/screen.dart, method: _buildContent, line: 128 }
hive_key_prefix: "n/a (pure widget render)"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: n/a
cloud_columns: []
contract_test_path: scripts/check_container_color_decoration.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [train_screen_build_failed]
cross_account_guard: >
  Unchanged. Pure widget render; no box access.
forbidden_patterns_checked:
  - { pattern: "Container with both top-level color: and decoration: in lib/", absent: true }
proposed_fix: >
  plan_header.dart:26 built a Container with BOTH a top-level color:
  AppColors.bgDeep AND a decoration: const BoxDecoration(color: AppColors.bgDeep,
  border: ...). Flutter's Container constructor asserts
  `color == null || decoration == null` (container.dart:277). In DEBUG the
  assert throws during build; TrainScreen._buildContent wraps the subtree in a
  try/catch that logs train_screen_build_failed and renders the ErrorState
  ("Failed to load workouts") — so the whole Train tab is dead in any debug /
  web build. In RELEASE the assert is compiled out (the decoration wins, the
  top-level color is dead), so it renders and no release test caught it. The
  decoration already paints bgDeep, so the fix is to delete the redundant
  top-level `color:` line. The plan header (the FIRST child built by
  _buildContent) renders identically afterward.
regression_test_planned:
  - scripts/check_container_color_decoration.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "plan_header.dart top-level color removed; flutter analyze clean; check_container_color_decoration.dart scans 606 Container sites, 0 violations" }
  - { tier: 12, layer: end_to_end_contract, status: verified, evidence: "live train_screen_build_failed telemetry pinned container.dart:277 assert; new gate proven fail-on-regression (probe Container(color+decoration) -> FAIL; clean -> PASS)" }
impact_analysis: >
  Feature-tier. Debug/web ONLY for the catastrophic symptom (Train tab fully
  unusable — the build throws and degrades to the error card). In release the
  assert is stripped so the screen renders correctly (decoration takes effect),
  meaning shipped APKs were NOT broken — but every web/debug QA session of the
  Train tab was blocked, which is why live web testing kept hitting a dead
  Train tab. Durable prevention: scripts/check_container_color_decoration.dart
  (depth-1 argument parser; pre-commit gate) — no Container can ship with both
  color and decoration again. This is the class of bug that is invisible to
  release tests AND to the analyzer (no lint exists for it), so a static gate is
  the right guard.
---

# b1f4d2 — Train plan header Container set both color and decoration

## What happened
`_buildPlanHeader` (the first child rendered by `TrainScreen._buildContent`)
built a `Container(color: AppColors.bgDeep, ..., decoration: const
BoxDecoration(color: AppColors.bgDeep, border: ...))`. Container asserts that
color and decoration are mutually exclusive (`container.dart:277`). In debug the
assert throws → `_buildContent`'s try/catch logs `train_screen_build_failed`
and shows "Failed to load workouts." The Train tab was unusable in every
debug/web build; Home was unaffected because it doesn't render the plan header.

## Why it was invisible
- Release strips the assert (decoration wins; the redundant color is dead), so
  no release/APK test failed and the shipped app rendered fine.
- No analyzer lint flags color+decoration on Container — it is a runtime assert.
- The screen's own defensive try/catch converted a hard crash into a soft
  "Failed to load workouts," hiding the stack from anyone not reading the
  client_errors telemetry.

## Fix
Delete the redundant top-level `color: AppColors.bgDeep`; the decoration already
paints it. One-line removal; render is identical.

## Durable prevention
`scripts/check_container_color_decoration.dart` parses each `Container(` call's
depth-1 arguments and fails if both `color:` and `decoration:` are present.
Wired into the pre-commit `check_*.dart` gate loop. Scans 606 Container sites
today; 0 violations after the fix; proven to fail on a reintroduced probe.

## Verification
Live `train_screen_build_failed` telemetry pinned the exact assert
(container.dart:277). Gate fail-on-regression proven (probe → FAIL at file:line;
clean → PASS). `flutter analyze` clean.
