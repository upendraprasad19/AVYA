---
bug_id: 2e8b8f
date: 2026-10-21
batch: train-coach-log-refresh (OI-371)
status: fixed_in_code
tier: m_fix
blast_radius: account
symptom: >-
  Founder's A12 web walk 2026-10-21 at phone width: exercise names in Train's expanded day row were cut to about four
  characters ("Benc…", "Barb…"), because the name and the long detail ("3 sets · 8 reps · 60.0 kg") shared one line and
  the name gave way. Counts also read "1 sets".
concept: exercise_logs_read_path — the expanded day's logged-exercise row (ExpandedExerciseLogRow).
sot_registry_entry: exercise_logs_read_path
writers:
  - { file: lib/features/train/screens/train/expanded_exercises.dart, method_or_widget: "_buildExpandedExercises: the detail string (setCountLabel / repCountLabel, NBSP-joined)", line: 92 }
  - { file: lib/features/train/utils/set_count_label.dart, method_or_widget: "setCountLabel / repCountLabel", line: 9 }
readers:
  - { file: lib/features/train/screens/train/expanded_exercises.dart, method_or_widget: "ExpandedExerciseLogRow: name on its own line, no line limit; detail under it", line: 158 }
  - { file: lib/features/train/screens/train/exercise_preview_sheet.dart, method_or_widget: "logged-history fallback lines use the same helpers", line: 178 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/features/train/expanded_exercise_log_row_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: ["none"]
  failure: ["none"]
cross_account_guard: "n/a: render only"
forbidden_patterns_checked:
  - "maxLines: 2 with ellipsis — REJECTED (plan R2A-6): ellipsis without maxLines still clips to one line, and coach-made names have no length cap; the row sits in a scroll view, so height costs nothing."
  - "adopting WardSetChips here — not proposed: a design change. wardroom/CLAUDE.md:121 wrongly said Train used it; corrected."
  - "a breaking space between a number and its unit — REJECTED: at 2.0 text a line could start with 'reps'; U+00A0 joins them and each separator is U+00A0 + '·' + a space, so a wrap falls only after a dot."
proposed_fix: >-
  `ExpandedExerciseLogRow` (public, in the part file): icon (sized by the text scaler, labelled 'Personal record' on a
  PR) beside a Column of the name (no maxLines, no overflow) and the detail (monoXs, wraps). The whole row is one
  MergeSemantics node. `setCountLabel` / `repCountLabel` give `1 set` / `N sets`, `1 rep` / `N reps` with U+00A0. Row gap
  6 → 8.
regression_test_planned:
  - "test/features/train/expanded_exercise_log_row_test.dart: at 320 dp × 1.0 / 1.3 / 2.0 for three real long names: not clipped, complete, detail on its own line (plus a short name with a short detail, which side by side would fit one line), icon top within 4 px and centre within 3 px of the first line; the detail wraps at 2.0 and never splits '12 reps'; the merged label 'Personal record\\nBench Press\\n3 sets · 8 reps · 60.0 kg'; through the real TrainScreen, '1 set'/'3 sets' and '1 rep'/'8 reps' on the weight and reps-only branches."
  - "test/features/train/set_count_label_test.dart"
mutation_proof: >-
  Scripted (scratchpad mut/run.py, exact-one-match replace, restore + byte compare): `maxLines: 2` on the name, red at
  2.0; `overflow: ellipsis` on the name, red; the detail beside the name (Wrap instead of Column) first came back GREEN (every long name wrapped the detail anyway), so the short-name case was added and it is red; the PR
  `semanticLabel` removed, red; the plural helper reverted, helper + C red; a breaking separator in the detail, red.
  After the B-pass (fb5048e68fae): a breaking space in the cardio and the timed detail, red. Counts in
  docs/audit/train-coach-log-refresh.closure.yaml. Self-attested.
impact_analysis: "Train's expanded rows get taller when a name wraps; no data change. The preview sheet's fallback lines gain the NBSP form (invisible)."
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/ clean; the widget tests above green" }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "render only" }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "render only" }
recurrence: "Recurrence of the single-line clipping class: b2e9d4 (tab headings clipped to an ellipsis, 2026-06-02, concept ui_header_no_clip). The known-good fix, let the text wrap instead of clipping, is applied. Searched INDEX for ellipsis/clip/truncat/cut."
related_bugs:
  - b2e9d4
---

# Names in Train's expanded day row were cut to a few characters

## What was wrong

The row was `Row(Icon, Expanded(Text(name, overflow: ellipsis)), Text(detail))` (`expanded_exercises.dart:107-111` on
origin/main). At phone width the detail took its full width and the name's `Expanded` got what was left, often a few
characters.

## Fix

The name gets its own line with no limit and the detail wraps under it; counts are plural-correct and never split from
their unit. The remaining "1 sets" renderers (prescriptions, receipt, preview screen, tool card) are OI-381; the
distance-type "0 reps" detail is OI-380.
