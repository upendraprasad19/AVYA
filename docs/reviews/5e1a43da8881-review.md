---
reviewed_at: 2026-09-17T12:30:00+05:30
staged_against: 5e1a43da8881
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
---

# Code Review — custom-picker-fix (B-pass)

Fresh context-blind agent over the staged diff (20 files, +1322/−216).
Recomputed blast-radius: **platform** (matches pre-commit's classifier).
All 5 mutation-proof claims from the diagnose-doc independently re-derived
by the reviewer — all 5 applied + reddened exactly as claimed, all
semantic reds.

## Finding 1 — P1 — guard_without_its_mirror (plan-review anti-fabrication)
- **file:line:** docs/plan-reviews/custom-picker-fix.md:10 (`bpass: accepted` without `bpass_review:`)
- **claim:** the record vouched for a B-pass before one had run; the
  anti-fabrication check requires a `bpass_review:` field naming a real
  `docs/reviews/` artifact with `verdict: accepted`.
- **verification:** `git diff --cached -- docs/plan-reviews/custom-picker-fix.md | Select-String bpass_review` → empty
- **suggested-fix:** run the B-pass (this document), then add
  `bpass_review: <this file>`.
- **status:** accepted — this pass IS that B-pass; the record now carries
  `bpass_review: docs/reviews/5e1a43da8881-review.md`.

## Finding 2 — P2 — writer_reader_drift (default_duration_secs vs default_duration_seconds)
- **file:line:** writer sheet (`buildEditPayload`/prefill) vs restore
  (`sync_community.dart` stores the raw cloud row, column
  `default_duration_secs`) vs readers split: `train_provider.dart:317`
  (`default_duration_secs` only) vs `exercise_selector.dart:1002`
  (`default_duration_seconds` only).
- **claim:** an edit of a restored timed custom would fork the row across
  BOTH keys; the two readers then disagree. Separately (main-thread
  extension of the same finding): `_parseTimedDurationSecs` never read the
  Hive-canonical key, so UI-created timed customs always fell to the
  reps-text heuristic/30s floor.
- **verification:** `git grep -n "default_duration_secs" lib/`
- **suggested-fix (both applied):** `buildEditPayload` removes
  `default_duration_secs` (edit converges the row); prefill reads both;
  parser extracted as public `parseTimedDurationSecs` and reads both keys.
  Pinned by `test/contracts/custom_duration_key_convergence_test.dart` (8
  assertions).
- **status:** accepted — fixed in-batch.

## Finding 3 — P2 — blast_radius_mismatch (tier self-declaration)
- **file:line:** diagnose-doc `blast_radius: account`; record `tier: ship_dark_build`
- **claim:** classifier returns platform; and ship_dark_build tiering is
  not earned (no kill-switch / not default-OFF / not byte-identical-when-off).
- **verification:** `git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -` → platform
- **suggested-fix:** correct both fields.
- **status:** accepted — fixed (`blast_radius: platform`; tier line removed;
  the record paid review_rounds: 2 regardless, so no review weight was skipped).

## Finding 4 — P2 — guard_without_its_mirror (sibling seam 9)
- **file:line:** `lib/core/services/swap_service.dart:256` (OI-89 seam 9)
- **claim:** the AI-driven swap-execution path still refused a user-authored
  custom with `[]` equipment — the UI swap sheet now OFFERS what the
  executor refuses, and the refusal message is misleading for a
  no-equipment exercise.
- **verification:** `git grep -n "canPerform(" lib/`
- **suggested-fix:** apply the same exemption (provenance knowable at the
  customBox scan) — done: `targetIsCustom` tracked at resolution, check
  switched to `canOfferInPicker(isCustom: targetIsCustom)`.
- **status:** accepted — fixed in-batch.

## Finding 5 — P3 — silent no-op save
- **file:line:** `create_custom_exercise_sheet.dart` edit-mode `_key` early return
- **claim:** a malformed future entry point yields a dead SAVE button with
  zero feedback.
- **verification:** `git grep -n "CreateCustomExerciseSheet(existing" lib/` → 1 site
- **suggested-fix:** snackbar on the early return.
- **status:** accepted — fixed (same snackbar as the failure path).

## Finding 6 — P3 — asserted_fixture_value (staging-note count)
- **claim:** the dispatch brief's "44 in the 6-file run" figure.
- **verification:** 5-file run → 28 exactly; adjacent widget suite → 8.
- **status:** false_alarm — the 44 was the 6-file run that also included
  `ui_seam_capability_test.dart` (28+16=44); the figure appeared only in
  the staging brief, never in any committed document.

## Mutation re-derivation (reviewer-independent)

| Mutation | Applied | Reddened | Claim | Match |
|---|---|---|---|---|
| M1 exemption polarity | ✓ | 2 | 2 | ✓ |
| M2 isCustom-guard drop | ✓ | 1 | 1 | ✓ |
| M3 `_key`-strip removal | ✓ | 1 | 1 | ✓ |
| M4 writer hardcode | ✓ | 2 | 2 | ✓ |
| M5 token drift | ✓ | 3 | 3 | ✓ |

## Founder triage notes
Auto-accepted at B-pass time (all findings fixed in-batch or annotated);
no founder action pending.
