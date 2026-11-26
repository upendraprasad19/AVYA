---
bug_id: f4c8a2
date: 2026-09-15
batch: Internal-testing observation batch, session 2 (Obs 4)
status: fixed
blast_radius: feature
symptom: |
  Founder-reported screenshot from internal testing: the active-workout weight
  input pre-fills with a garbage-precision value like "27.9000000000000..."
  instead of a clean decimal. Founder asked "why only max 2 decimal places
  everywhere?" implying the fix should be applied consistently, not just
  patched for one exercise.
concept: active_workout_weight_prefill
sot_registry_entry: |
  Not applicable — this is a pure display-formatting fix on an existing
  prefill path, not a writer/reader contract change. The underlying
  lastPerformanceProvider / setInputValues values are unchanged; only their
  string rendering is fixed.
writers:
  - { file: lib/features/train/screens/active_workout/exercise_card.dart, method_or_widget: "_ExerciseCardState._initControllers (last-logged-weight prefill)", line: 104 }
  - { file: lib/features/train/screens/active_workout/exercise_card.dart, method_or_widget: "_ExerciseCardState._initControllers (restored setInputValues prefill)", line: 122 }
readers:
  - { file: lib/features/train/screens/active_workout/exercise_card.dart, method_or_widget: "_weightControllers TextEditingController.text (rendered in the KG TextField)", line: 111 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/train/exercise_card_weight_display_format_test.dart
ist_handling:
  - "Not applicable — no date keys or counters involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — pure UI formatting, no data access."
forbidden_patterns_checked:
  - { pattern: "w == w.roundToDouble() ? w.toInt().toString() : w.toString() (no toStringAsFixed guard) as a weight-display formatter", absent: true }
proposed_fix: |
  Extract the two identical inline formatting expressions into one shared
  formatWeightDisplayValue(double) helper that rounds via
  double.parse(w.toStringAsFixed(2)) BEFORE the whole-number check, so a
  float-multiplication artifact like 31.0 * 0.9 == 27.900000000000002 renders
  as "27.9" instead of dumping every trailing digit via the bare w.toString()
  fallback.
regression_test_planned:
  - test/train/exercise_card_weight_display_format_test.dart
impact_analysis: |
  Display-only fix. Both prefill call sites in exercise_card.dart routed
  through the same buggy one-liner (grepped: it is the only file in lib/
  using this `w == w.roundToDouble() ? ... : w.toString()` idiom for weight
  display — lib/features/train/widgets/exercise_sparkline.dart already had
  its own safe `toStringAsFixed(1)` fallback and was not affected). No writer
  changed; no Hive/cloud field changed. The helper was made a public
  top-level function (not `_`-prefixed) specifically so it is directly
  unit-testable from test/train/ without needing a full widget pump through
  private classes in the `part of 'screen.dart'` file.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "formatWeightDisplayValue added + both call sites routed through it; flutter analyze clean." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive field changed — setInputValues stores the raw double; only its TextEditingController.text rendering changed." }
---

## Summary

Founder screenshot (internal-testing batch, session 2, 2026-09-15) showed the
active-workout weight (KG) input pre-filling with a long garbage-precision
decimal (e.g. "27.9000000000000...") instead of a clean number. Founder asked
why the app doesn't cap decimals to 2 places consistently.

## Root Cause

Two sites in `lib/features/train/screens/active_workout/exercise_card.dart`
(`_ExerciseCardState._initControllers`, lines 104 and 122 pre-fix) pre-fill the
weight `TextEditingController` from a `double`:

1. `lastPerf.lastWeight! * widget.data.effectiveLoadFactor(exercise)` — the
   last-logged weight scaled by the readiness/session-detraining load factor.
2. `captured.weight!` — a weight value restored from `setInputValues` after a
   widget rebuild.

Both used the same inline formatter:
```dart
w == w.roundToDouble() ? w.toInt().toString() : w.toString();
```
This only special-cases an EXACT whole number. Any other value falls through
to the bare `w.toString()`, and float multiplication rarely lands on an exact
decimal — e.g. `31.0 * 0.9 == 27.900000000000002` in IEEE 754 double
arithmetic — so Dart's `double.toString()` printed every trailing digit
straight into the input field.

A source-grep (`grep -rn "roundToDouble() ? .*toInt().*toString() : .*toString()" lib/`)
confirmed this exact idiom appears only at these two sites in `lib/`.
`lib/features/train/widgets/exercise_sparkline.dart` has a superficially
similar helper but its else-branch already calls `toStringAsFixed(1)` rather
than a bare `toString()`, so it was never exposed to this bug — not a
recurrence of a named class, first instance of this specific idiom.

## Fix

Extracted both sites into one shared `formatWeightDisplayValue(double w)`
(top of `exercise_card.dart`, public — not `_`-prefixed — so it is directly
testable from `test/train/` without pumping the private widget classes in
this `part of 'screen.dart'` file):

```dart
String formatWeightDisplayValue(double w) {
  final rounded = double.parse(w.toStringAsFixed(2));
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}
```

Rounding to 2 decimal places FIRST (via `toStringAsFixed(2)` + re-parse) before
the whole-number check means `31.0 * 0.9` renders as `"27.9"`, and any residual
float noise is clipped at 2 decimals rather than printed verbatim.

## Verification

`test/train/exercise_card_weight_display_format_test.dart` — 4 behavioral
tests directly calling the pure `formatWeightDisplayValue` function (imported
via the library's main file, `screen.dart`, since Dart privacy is per-library
and this helper is deliberately public):
- `31.0 * 0.9` (real float noise, the reported shape) → `"27.9"`.
- `28.0` → `"28"` (clean whole-number strip still works).
- `27.5` → `"27.5"` (a genuine 1-decimal value survives unchanged).
- Any formatted result has at most 2 digits after the decimal point.

**Mutated and run** (rule 21): reverted `formatWeightDisplayValue` to the
pre-fix one-liner (`w == w.roundToDouble() ? w.toInt().toString() : w.toString()`).
2 of 4 tests reddened: the float-noise case (`Actual: '27.900000000000002'`)
and the never-more-than-2-decimals case (`"25.333333327" has more than 2
decimals`). Restored the fix — all 4 tests passed again.

## Related

None — first instance of this specific idiom; not a recurrence of a named bug
class (checked `docs/diagnoses/INDEX.md` for "decimal"/"precision"/"float" —
the one hit, `5456c4`, is an unrelated static-weight-CHART bug, not an input
prefill formatting bug).
