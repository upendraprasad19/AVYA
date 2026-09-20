---
bug_id: b2e9d4
date: 2026-06-02
batch: apk-obs-2026-06-02
status: fixed
blast_radius: feature
symptom: >
  Tab-screen headings clipped to an ellipsis: the Train screen showed
  "Intensificati…" (phase name "Intensification") and the Nutrition screen showed
  "Fueling the pl…". Both used a single-line Text (maxLines:1 + overflow.ellipsis)
  at a large font inside an Expanded that competed with a right-side control
  (streak pill / diet-plan button), so on narrower phones the title truncated.
concept: ui_header_no_clip
sot_registry_entry: not_applicable (pure presentation; no data SoT)
writers: not_applicable (no data writer — display only)
readers: >
  lib/features/train/screens/train/plan_header.dart (phase title Text);
  lib/features/nutrition/screens/nutrition_screen.dart ("Fueling the plan" title);
  swept for the same pattern: lib/features/home/screens/home_screen.dart (greeting)
  + lib/features/ai_coach/screens/ai_coach/compact_header.dart ("Aye Captain").
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/contracts/tab_header_no_clip_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable (display only)
forbidden_patterns_checked:
  - "A dynamic tab-header title using maxLines:1 + TextOverflow.ellipsis inside an Expanded competing with a trailing control — replaced with FittedBox(scaleDown) so the full text always fits; pinned by test/contracts/tab_header_no_clip_test.dart."
proposed_fix: >
  Wrap each header title in FittedBox(fit: BoxFit.scaleDown, alignment:
  centerLeft) with the Text at maxLines:1 + softWrap:false (no ellipsis). The text
  shrinks to fit the available width instead of truncating, so the full phase name
  / title is always visible regardless of device width. Applied to Train + Nutrition
  (the reported clips) and swept to Home greeting + Coach header for a uniform
  clip-proof treatment.
regression_test_planned: >
  test/contracts/tab_header_no_clip_test.dart (comment-stripped source-grep): the
  four header titles (plan_header phase name, nutrition_screen "Fueling the plan",
  home greeting, compact_header "Aye Captain") are wrapped in FittedBox(scaleDown)
  and do NOT use overflow: TextOverflow.ellipsis on the title.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "FittedBox(scaleDown) added to plan_header.dart, nutrition_screen.dart, home_screen.dart greeting, compact_header.dart; flutter analyze clean on the changed files" }
impact_analysis: >
  Feature blast radius — pure presentation, no data path. Affects any user whose
  phase name (e.g. "Intensification", "Deployment 13") or the static Nutrition/Coach
  titles exceed the available width on a narrow device. FittedBox(scaleDown) is the
  established no-clip primitive (shrinks rather than truncates) and can only make a
  previously-clipped title fully visible — no regression risk to short titles
  (no scaling applied when it already fits). Found via the founder's APK
  observation (images 1 + 2).
---

# Clipped tab headings — single-line ellipsis on dynamic titles

## What happened
Train ("Intensificati…") and Nutrition ("Fueling the pl…") headings truncated.

## Root cause
`maxLines:1 + TextOverflow.ellipsis` on a large-font title inside an `Expanded`
competing with a right-side control → ellipsis on narrower phones.

## Fix
`FittedBox(fit: BoxFit.scaleDown, alignment: centerLeft)` wrapping the title
(maxLines:1, softWrap:false, no ellipsis) — shrinks to fit, never clips. Applied
to Train + Nutrition and swept to Home greeting + Coach header.

## Verification
`flutter analyze` clean; `tab_header_no_clip_test.dart` source-grep pins the four
titles use FittedBox and not ellipsis.

## See also
- `lib/features/train/screens/train/plan_header.dart`, `lib/features/nutrition/screens/nutrition_screen.dart`
- Prior overflow work: task #35 profile RenderFlex pass (Train/Nutrition were not covered then)
