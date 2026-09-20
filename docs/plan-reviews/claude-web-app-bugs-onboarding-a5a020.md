---
branch: claude/web-app-bugs-onboarding-a5a020
review_rounds: 2
mechanical_only: false
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/8a61d526f062-review.md
tier: standard
date: 2026-09-20
---

# Plan review — web-app-bugs-onboarding-a5a020

**Diagnoses:**
`docs/diagnoses/2026-09-19-onboarding-picker-textwrap-and-unresponsive-e2b8a4.md`
(DOB/time picker text-wrap + unresponsive OK dismiss on MobileFrame web) and
`docs/diagnoses/2026-09-19-muster-induction-drift-and-reorder-d6f1b8.md`
(muster/induction writer-drift + post-commitment reorder).

**Blast radius:** platform. The diff's own feature content (onboarding +
ai_coach screens) is account-tier; the batch reached platform because this
review's own B-pass fix (Finding 4) added `lib/app.dart` to
`docs/blast_radius.yaml`, which is itself pinned `platform` (it is the
classifier's own configuration). Confirmed live via
`git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -`
→ `platform`, and by isolating which staged file drives it
(`docs/blast_radius.yaml` alone → `platform`).

## Round 1 (context-blind, on the original fix) — 4 findings, all fixed

- **Finding 1** — Edit Profile's own DOB picker (`edit_profile_screen.dart`
  `_pickDateOfBirth()`) had no `builder:` at all — the onboarding fix never
  got re-grepped to every `showDatePicker` call site. Fixed by wiring the
  same `responsivePickerBuilder`.
- **Finding 2** — neither real DOB call site set `initialEntryMode`, so both
  could render the keyboard-toggle icon and its differently-sized layout,
  never verified safe at MobileFrame's narrow web content width. Fixed with
  `DatePickerEntryMode.calendarOnly` on both.
- **Finding 3** — a reviewer-suggested "redundancy" removal
  (`responsivePickerBuilder`'s `textTheme: stockTextTheme` reset) was tried,
  then DISPROVEN by actually running the test suite rather than re-reasoning
  about the claim: 2/6 tests failed, reintroducing the original DM-Sans wrap
  bug. Root cause: a `TextStyle` field with `fontFamily: null` merges onto
  the ambient `DefaultTextStyle` rather than falling back to a platform
  default. Reverted; the reviewer's other, independently-correct observation
  (calendar header styles also need an explicit override) was kept.
  **Durable lesson recorded in-doc:** a review finding's suggested FIX is
  itself a hypothesis requiring the same live verification as the finding.
- **Finding 4** — `MobileFrame`'s `MediaQuery` content-size formula didn't
  account for its own `Border.all` decoration-padding (~1.5% discrepancy,
  negligible in practice). Fixed with a single `frameBorderWidth` constant
  shared by the border decoration and the size formula.

## Round 2 (context-blind, on the hardened state) — 2 findings, both fixed

- Five architecture/CLAUDE.md docs (`lib/features/onboarding/CLAUDE.md`,
  `lib/features/auth/CLAUDE.md`, `docs/architecture/sync.md`,
  `docs/architecture/database.md`, `docs/architecture/functionality-flow.md`)
  still described the pre-batch muster bridge (6 keys bridged/mirrored) after
  `d6f1b8` narrowed it to 1 key with the other 5 rejected outright. All five
  rewritten to match current reality, each verified against the actual
  current code before editing (not against the stale prose).
  `check_hive_map_field_drift.dart` and `check_sot_registry_parity.dart`
  pre-commit gate failures encountered while re-staging (a heuristic
  false-positive on `wake_up_time`/`preferred_workout_time`, and a stale
  `_getCurrentPlanSummary` line-range citation) were root-caused and fixed
  following established repo conventions.
- A pre-existing stale SoT prose citation
  (`induction_service.dart:209` for the muster bridge, superseded by the
  method's real current location) was corrected to
  `induction_service.dart:102-110`.

## B-pass (fresh adversarial reviewer) — 5 findings; 4 fixed, 1 accepted as noted

Full findings + verification + fix detail: `docs/reviews/8a61d526f062-review.md`.

- **Finding 1 (P1, guard_without_its_mirror)** — `MusterScreen._onSubmit()`
  latched `_submitting = true` with no try/catch around the only `await`;
  a genuine `GuardedBox` `StateError` (documented auth/Hive
  owner-disagreement race window) left CONTINUE permanently disabled with no
  error shown. Fixed with try/catch + reset + SnackBar. The finding also
  named `InductionScreen._onCommit()`'s identical, unmirrored, and WORSE
  shape (a throw there left `_stage` stuck at 7, unconditionally rendering a
  FALSE "Contract sealed." success message) — independently re-verified
  still present (not yet touched by any prior round) and fixed the same way.
  Both fixes additionally wired `ErrorTelemetry.logEvent` (caught by
  `check_generic_error_telemetry.dart` on the first gate-loop run after these
  fixes — a real, valid finding that generic apology copy with no telemetry
  leaves ops blind to how often the race actually fires in production).
- **Finding 2 (P1, writer_reader_drift)** — `docs/sot_registry.yaml`'s
  `muster_to_profile_bridge` concept block still described the pre-batch
  6-key bridge; the diagnose-doc's own `sot_registry_entry: not_applicable`
  self-attestation was also false. Both corrected; concept block rewritten
  in full including the `writers:`/reader citations.
- **Finding 3 (P2, asserted_fixture_value)** — the diagnose-doc's own claim
  that `ward_phase_block_test.dart` was "mutation-proven against both [title
  and weeksLabel]" was independently re-verified and found FALSE for
  weeksLabel: removing its `maxLines`/`overflow` left the pre-existing test
  green (a `Flexible` wrapper alone already suppresses the `RenderFlex`
  overflow the test's only assertion checked for). Fixed by adding direct
  `maxLines`/`overflow` assertions, mutation-proven to now correctly redden
  on the exact gap.
- **Finding 4 (P3, blast_radius_mismatch)** — `lib/app.dart`'s `MobileFrame`
  (the single `MaterialApp.router` `builder:` wrapper for the entire web
  app, owning the `MediaQuery` every screen/dialog sees) had no entry in
  `docs/blast_radius.yaml` and fell through to `feature` tier — a diff
  touching only it would have cleared zero review gate. Fixed with a
  single-file `account`-tier promotion, following the exact precedent
  pattern already used for `pro_phase_advance.dart`/`hive_tab_scaffold.dart`.
  This fix is what raised this batch's own blast radius to `platform`.
- **Finding 5 (P4, asserted_fixture_value)** — `mobile_frame_mediaquery_test.dart`
  re-derives its expected value from the same formula the production code
  uses, so a future formula regression could pass undetected. Accepted as a
  documented, low-priority residual: the reviewer independently confirmed
  the current formula is correct via a separate derivation, the test's own
  comment already discloses the tradeoff honestly, and the reviewer's own
  suggested-fix is explicitly framed as optional.

## Mutation evidence

- `muster_screen.dart` `_onSubmit()` try/catch: reverted to the no-catch
  shape (`// MUTATION` marker), confirmed all 3
  `muster_screen_submit_error_reset_test.dart` assertions redden on the
  correct failure points, restored via Edit, reconfirmed green, confirmed
  zero residual diff against the staged pre-mutation file.
- `induction_screen.dart` `_onCommit()` try/catch: identical cycle against
  the new `induction_screen_commit_error_reset_test.dart` (3/3 reddened on
  the missing `try {`, missing catch block, and missing
  ScaffoldMessenger/SnackBar respectively; restored; reconfirmed green;
  confirmed `git diff` shows only the intended addition).
- `ward_phase_block.dart` weeksLabel `Text`: removed `maxLines`/`overflow`
  (`// MUTATION` marker), confirmed the STRENGTHENED
  `ward_phase_block_test.dart` now reddens exactly at the new weeksLabel
  assertion (line 68, correct custom reason message) — this is the finding
  itself reproduced live before being fixed, not merely accepted from the
  report. Restored; reconfirmed all assertions green; confirmed zero
  residual diff against the staged version.
- `docs/blast_radius.yaml` `lib/app.dart` rule: classified a synthetic
  `lib/app.dart`-only diff before the fix (`feature`, the gap) and after
  (`account`, closing it) via the real classifier script, not by inspection.

## Verification state at record time

- Full pre-commit gate loop: OK (98 gates, no collisions; Gate 15
  `check_generic_error_telemetry` failed once on the two new catch blocks'
  generic copy with no telemetry call, fixed by wiring
  `ErrorTelemetry.logEvent`, re-ran clean).
- `flutter analyze lib/` (whole-tree, not per-file — both touched screens
  are ordinary standalone files but the whole-tree form is the only one this
  repo trusts per its own documented `part`-file analyze gap): 45 pre-existing
  `info`-level issues, 0 `warning`/`error`, none in either file this batch
  touched.
- Targeted tests green: `muster_screen_submit_error_reset_test.dart` (3),
  `induction_screen_commit_error_reset_test.dart` (3),
  `ward_phase_block_test.dart` (1, 5 assertions), plus the full pre-existing
  onboarding/muster/induction contract suite re-run clean after every doc and
  registry correction.
- `scripts/validate_diagnose_doc.dart` passed on both diagnose-docs after all
  frontmatter corrections (Round 2's `sot_registry_entry` fix on d6f1b8;
  the accumulated Round 1 + B-pass additions on e2b8a4).
