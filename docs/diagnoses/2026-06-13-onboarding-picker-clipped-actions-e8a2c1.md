---
bug_id: e8a2c1
date: 2026-06-13
batch: e2e-obs-fixes
status: fixed
blast_radius: account
symptom: >
  Obs#5 (live web E2E, potential onboarding BLOCKER): on the ~698px web mobile-
  frame the stock Material TIME picker (muster Q2 wake/train time) showed its
  OK/Cancel action row BELOW the visible frame (DIAL mode pushed the actions off
  the bottom; KEYBOARD mode showed only a clock-toggle + Cancel). The user could
  not confirm a time → muster Q2 (which requires both times) was unpassable on
  web → onboarding-completion blocker. The onboarding DOB date picker
  (identity_screen) was likewise cramped. The muster CONTINUE validation toast
  already worked — the defect was purely the unreachable confirm affordance.
concept: responsive_picker_host
sot_registry_entry: not_applicable
contract_test_path: test/contracts/responsive_picker_host_test.dart
writers: >
  lib/shared/widgets/responsive_picker_builder.dart (new shared builder — theme +
  centered SingleChildScrollView so a too-tall dialog can be scrolled to reveal
  its actions); lib/features/ai_coach/screens/muster_screen.dart (_pickTime) and
  lib/features/onboarding/screens/identity_screen.dart (DOB) now pass it as the
  showTimePicker / showDatePicker `builder`.
readers: >
  The Material time/date picker dialogs rendered during muster Q2 + onboarding DOB.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: "not_applicable"
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "showTimePicker / showDatePicker without a host that keeps the action row on-screen at short viewports. Both now pass responsivePickerBuilder (scroll-wrapped). Pinned by test/contracts/responsive_picker_host_test.dart."
proposed_fix: >
  Add a shared responsivePickerBuilder(context, child) that applies the Wardroom
  theme AND wraps the dialog in a centered SingleChildScrollView so a dialog
  taller than the viewport can be scrolled to reveal its OK/Cancel row. Use it as
  the `builder` for both pickers (the time picker had NO builder; the DOB picker
  had a theme-only builder with no height handling).
regression_test_planned: >
  test/contracts/responsive_picker_host_test.dart — (1) widget test: the builder
  scroll-wraps a 2000px child without overflow (SingleChildScrollView present);
  (2) source-grep: both pickers pass responsivePickerBuilder.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "shared builder + both pickers wired; flutter analyze clean; responsive_picker_host_test green (widget + source-grep)" }
impact_analysis: >
  Account blast radius. On WEB this was a hard onboarding blocker (a new user
  literally could not confirm a muster time → could not complete onboarding); on a
  real Android device the native pickers + wider viewport likely don't reproduce —
  DEVICE VERIFY is noted (if it repros on device it is a P0). The fix is the
  standard Flutter remedy (scroll-wrap the picker builder child) and is harmless
  at any viewport.
---

# Onboarding time/date picker action row clipped off-frame (e8a2c1)

## What happened
At ~698px web height the stock Material time picker (muster Q2) and date picker
(DOB) pushed their OK/Cancel row below the fold — the user could not confirm,
blocking muster Q2 → onboarding completion on web.

## Fix
Shared `responsivePickerBuilder` (theme + centered SingleChildScrollView) used as
the `builder` for both pickers, so a too-tall dialog scrolls to reveal its actions.

## Device verify
Android native pickers / wider viewport may not reproduce — confirm on device.

## See also
- lib/shared/widgets/responsive_picker_builder.dart
- lib/features/ai_coach/screens/muster_screen.dart (_pickTime)
- lib/features/onboarding/screens/identity_screen.dart (DOB)
- test/contracts/responsive_picker_host_test.dart
