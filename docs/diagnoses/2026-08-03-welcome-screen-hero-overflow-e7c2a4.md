---
bug_id: e7c2a4
date: 2026-08-03
batch: restore-onboarding-signin-fix
status: fixed
symptom: |
  Founder screenshot of app.icanbefitter.com/#/onboarding (the pre-auth
  welcome/marketing screen) showed the "BEGIN ENLISTMENT →" button
  overlapping with "03 · Coach that holds you to your own standards" (a
  hero feature row) and "Already a member? SIGN IN" overlapping with the
  referral-code input field — text and interactive elements painting on
  top of each other instead of a clean vertical stack.
concept: welcome_screen_hero_layout
sot_registry_entry: n/a — pure UI layout, no writer/reader concept
writers:
  - { file: lib/features/onboarding/screens/welcome_screen.dart, method_or_widget: "_hero() — was a bare Center(child: Column(...)) with no scroll ancestor", line: 112 }
readers:
  - { file: lib/features/onboarding/screens/welcome_screen.dart, method_or_widget: "build() — Column[_brandRow(), Expanded(child: _hero()), _cta(context)]", line: 54 }
hive_key_prefix: "n/a — UI layout fix only"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: n/a
cloud_columns: []
contract_test_path: test/widgets/onboarding/welcome_screen_short_viewport_test.dart
ist_handling:
  - "Not applicable — pure layout fix, no date/time values involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a — this screen renders before any auth session exists; no user-scoped state involved."
forbidden_patterns_checked:
  - { pattern: "Center(child: Column(...)) directly inside Expanded with no SingleChildScrollView/ConstrainedBox fallback for _hero()", absent: true, after_fix: true }
related_bugs: []
recurrence: |
  No prior diagnose-doc exists for this screen's layout (checked
  docs/diagnoses/INDEX.md). Not a recurrence — first instance of this
  screen's overflow, though structurally the same general Flutter footgun
  (Column with no scroll ancestor inside a size-constrained Expanded) noted
  generically in lib/CLAUDE.md's common-pitfalls table for other screens.
proposed_fix: |
  Wrap _hero()'s existing Center(child: Column(...)) in the
  LayoutBuilder + SingleChildScrollView + ConstrainedBox(minHeight:) idiom
  already used elsewhere in this codebase
  (sign_in_screen.dart._buildEmailRoot). Because _hero() is called as
  Expanded(child: _hero()) from build(), LayoutBuilder receives a bounded
  height (the Expanded-allocated space); ConstrainedBox(minHeight:
  constraints.maxHeight) makes Center continue to vertically center the
  content exactly as before when it fits, and lets the content become
  internally scrollable instead of overflowing into _cta() when it
  doesn't. No changes to _brandRow(), _cta(), or the outer Column
  structure — brand row stays pinned top, CTA stays pinned bottom on
  every viewport where the content already fit.
regression_test_planned:
  - test/widgets/onboarding/welcome_screen_short_viewport_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "lib/features/onboarding/screens/welcome_screen.dart _hero() rewritten; flutter analyze clean; dart format applied." }
  - { tier: 2, layer: hive_local_state, status: not_applicable, evidence: "No Hive involvement — pure widget layout." }
  - { tier: 3, layer: postgres_schema, status: not_applicable, evidence: "No schema involvement." }
  - { tier: 4, layer: postgres_data, status: not_applicable, evidence: "No data involvement." }
  - { tier: 5, layer: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, layer: edge_function_deploy, status: not_applicable, evidence: "No Edge Function." }
  - { tier: 7, layer: cron_jobs, status: not_applicable, evidence: "No cron." }
  - { tier: 8, layer: rls_policies, status: not_applicable, evidence: "No RLS." }
  - { tier: 9, layer: storage_buckets, status: not_applicable, evidence: "No storage." }
  - { tier: 10, layer: secrets_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, layer: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, layer: client_server_contract, status: not_applicable, evidence: "Pre-auth static screen, no client-server contract touched by this fix." }
impact_analysis: |
  Blast-radius feature tier — a single widget file, no auth/sync/payment/
  migration surface touched, docs/blast_radius.yaml's default for a
  feature-scoped UI file under lib/features/. Change is purely additive
  (a scroll fallback wrapper) with zero behavior change on any viewport
  where the pre-fix layout already rendered correctly, confirmed by the
  "normal/tall viewport is unaffected" regression test case and by
  temporarily reverting the fix and re-running the test suite (both cases
  failed identically pre-fix — RenderFlex overflowed by 200 pixels — even
  at a 360x800 viewport, confirming the bug was not an extreme edge case).
blast_radius: feature
---

# Onboarding welcome-screen hero content overlaps the CTA section on short/normal viewports

## Symptom

Screenshot showed `app.icanbefitter.com/#/onboarding`'s "BEGIN ENLISTMENT →"
button overlapping a hero feature row, and "Already a member? SIGN IN"
overlapping the referral-code field.

## Root cause

`lib/features/onboarding/screens/welcome_screen.dart`'s `build()` lays out
`Column[_brandRow(), Expanded(child: _hero()), _cta(context)]`. `_hero()`
returned a bare `Center(child: Column(mainAxisSize: min, ...))` with no
scroll ancestor. Its intrinsic content — a "PROSPECTUS" eyebrow, a 44px
3-line headline, a body paragraph, and 3 numbered feature rows — is
roughly 450-500px tall. On any viewport where the `Expanded` region ends up
shorter than that (confirmed via test to include even an ordinary 360×800
phone size, not just extreme cases), the `Column` paints past its allotted
bounds instead of clipping — visually spilling into `_cta()` below it.

## Fix

Wrapped `_hero()`'s content in the same
`LayoutBuilder + SingleChildScrollView + ConstrainedBox(minHeight:)` idiom
already used by `sign_in_screen.dart`'s `_buildEmailRoot` — content still
centers exactly as before when it fits the `Expanded`-allocated space, and
scrolls internally instead of overflowing when it doesn't. No change to
`_brandRow()`, `_cta()`, or the outer layout.

## Verification

```
$ flutter test test/widgets/onboarding/welcome_screen_short_viewport_test.dart
```

2/2 green. Confirmed the test genuinely reproduces the bug: temporarily
reverted `_hero()` to the pre-fix bare `Center(child: Column(...))` and
re-ran — both test cases failed with `RenderFlex overflowed by 200 pixels
on the bottom`, including the "normal/tall viewport" case (360×800), then
restored the fix and re-confirmed both green. `flutter analyze` clean.

## Follow-ups (tracked, not deferred)

None outstanding for this specific fix.
