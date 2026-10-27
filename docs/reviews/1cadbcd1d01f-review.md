---
reviewed_at: 2026-09-16T22:15:00+05:30
staged_against: 1cadbcd1d01fb676a8fb3a661c75197dfd6f2a33
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, modelled_on_is_a_checkable_claim, self_attesting_artifact]
findings_count: 3
verdict: accepted
---

# Code Review — 1cadbcd1d01f (oi53-batch1-flip)

## Finding 1 — P2 — modelled_on_is_a_checkable_claim
- **file:line:** `docs/plan-reviews/oi53-batch1-flip.md:30-31` (the claim); `docs/ship_dark_pending_review.yaml:188-214` (the untouched entries)
- **claim:** The plan-review record states that leaving `docs/ship_dark_pending_review.yaml`'s three entries (`enable_exercise_id_history`, `enable_injury_substitute_pref`, `enable_cross_phase_variety`) entirely under `pending:` (unedited — `flip_reviewed: false`, `flip_commit: null`, no `flip_review_record:`, no `resolved:` move) is "deliberately left for a follow-up records commit, per this repo's established split-commit convention for that file." This "established convention" framing does not survive reading the cited commits' own content. Of the 5 prior OI-53-family flip commits: only the 2 most recent show a clean, tight, same-branch follow-up (phase-arc: `55035cd7` flips, `2fca4c12` fills the sha 2 minutes later, same branch; deload-reason-line: `c22e12c2` flips, `336a72da` fixes the ledger ~2h later, same branch). The other 3 did NOT do this cleanly: `e6a8a8ae` (2026-08-06) and `a7c2d194` (2026-08-28) each added their entry to the **`pending:`** list (not `resolved:`) with `flip_reviewed: true` and a literal placeholder string `flip_commit: pending`; `9e4c5681` (2026-09-01) didn't touch the ledger at all. All three sat wrong/untouched until `dabe2013` (2026-09-02) fixed them retroactively — 27, 5, and 1 days later respectively — and `dabe2013`'s own commit message frames this as a bug being fixed ("resolved was empty while five flags were live"), not evidence of a designed workflow. This diff carries no tracked commitment that the follow-up records commit will land before this branch merges.
- **verification:** `git show --stat 9e4c5681 -- docs/ship_dark_pending_review.yaml` (empty — untouched); `git show a7c2d194 -- docs/ship_dark_pending_review.yaml` (inserted into `pending:` with `flip_commit: pending`); `git show -s --format="%h %ci %s" dabe2013 55035cd7 2fca4c12 c22e12c2 336a72da e6a8a8ae a7c2d194 9e4c5681`
- **suggested-fix:** Add the `resolved:` entries for these 3 flags in a follow-up commit on this same branch before merge (matching the phase-arc/deload-reason-line pattern), citing this flip commit's real SHA.
- **status:** accepted — fixed via a follow-up records commit on this same branch, landed before merge, citing the flip commit's SHA (matches the 2 most recent clean precedents this finding itself identified).

## Finding 2 — P3 — self_attesting_artifact
- **file:line:** `docs/plan-reviews/oi53-batch1-flip.md:111-112`
- **claim:** The record's "Ground truth verified" section states `git status --porcelain` "shows exactly the 7 originally-staged files and nothing else stray." The diff is now staged at 10 files (round 2's remediation added `docs/audit/open_issues.md` + `docs/audit/OPEN_INDEX.md`, and the record itself can't describe its own staging). The bullet carries no scope/time qualifier and could mislead a reader skimming only that line.
- **verification:** `git status --porcelain=v1 --untracked-files=all | wc -l` → 10 at review time, matching the dispatch brief's own "10" file list, not the record's "7".
- **status:** accepted — fixed by adding an explicit time-scope qualifier to the bullet in this same batch.

## Finding 3 — P3 — modelled_on_is_a_checkable_claim
- **file:line:** `lib/features/dev/dev_panel_screen.dart` (absence); `lib/shared/repositories/plan_engine/plan_engine_flags.dart:346-434` (the 3 flipped getters)
- **claim:** None of the 3 newly-flipped flags got a toggle added to the `kDebugMode`-gated dev panel, unlike 4 of the 4 true "shipped-dark-then-later-flipped" OI-53 precedents (`9e4c5681` +58, `55035cd7` +37, `c22e12c2` +26, `e6a8a8ae` +38 lines each adding an explicit `configBox.put('disable_X', true)`/`.delete` toggle). `equipmentCapabilityFloorEnabled` (`a7c2d194`) is not part of the reference class — it was built and flipped in the same batch, never sitting dark, so it never needed one. Severity capped at P3: **OI-95** already tracks this exact gap as an accepted, architectural risk across all 13 OI-53/OI-60 flags, and the dev panel is compiled out of `--flavor prod --release` regardless, so no production capability is lost.
- **verification:** `grep -n "exercise_id_history\|injury_substitute_pref\|cross_phase_variety" lib/features/dev/dev_panel_screen.dart` → 0 hits; `git show --stat 9e4c5681 55035cd7 c22e12c2 e6a8a8ae -- lib/features/dev/dev_panel_screen.dart` → 58/37/26/38 insertions; `git show --stat a7c2d194 -- lib/features/dev/dev_panel_screen.dart` → empty.
- **suggested-fix:** Optional — add the 3 toggles to the dev panel's Flags card on a future batch that touches that screen. Not worth a dedicated commit: OI-95 already owns the underlying risk architecturally, and a real fix there (an `/admin`-gated option) would obsolete per-flag dev-panel toggles anyway.
- **status:** accepted, no fix in this batch — substance already tracked by OI-95 (architectural, all-13-flags scope); a per-flag dev-panel toggle for just these 3 would be inconsistent scope-narrowing of an already-filed, wider issue.

## Verified clean (reviewer's own record, independently spot-checked by the orchestrating session before this file was written)

- **Straggler old-key readers.** Repo-wide grep (tracked + untracked, `*.dart|*.yaml|*.yml|*.md|*.json`) for `enable_exercise_id_history` / `enable_injury_substitute_pref` / `enable_cross_phase_variety`: zero hits in `lib/`, zero in any debug/admin/settings screen, zero in any other test file. Only hits are historical docs predating this branch and the 3 `pending:` ledger entries (Finding 1).
- **Mutation-testing the 3 flipped getters.** Each getter's polarity inverted, mutation confirmed textually applied, corresponding test file run and confirmed to redden with a real assertion failure (never a compile error), reverted and confirmed clean. `injurySubstitutePreferenceEnabled` and `crossPhaseVarietyEnabled` mutations reddened exactly the tests the plan-review record itself claims, with matching `Expected`/`Actual` values. `plateau_rotation_behavioral_test.dart` + `plateau_escalation_behavioral_test.dart` stayed fully green while `crossPhaseVarietyEnabled` was mutated, confirming their claimed independence. Baseline and final full re-run of the 5 named files: 51/51 both times.
- **OI-53 board arithmetic.** Independently re-derived (`grep -n ".get('enable_" plan_engine_flags.dart` → 7 distinct flags; excluding `enable_hold_weeks`, which is OI-60 not OI-53, leaves 6) before reading the remediation section's reasoning — same answer, independently re-confirmed a third time by the orchestrating session after this report was returned.
- **Plan-review record frontmatter gate-parseability.** Read `scripts/check_plan_review_record_exists.dart` + `scripts/plan_review_record_lib.dart` directly; confirmed LF-only, bare `---` delimiters, every field the gate's parser reads is present and bare. `bpass: pending` was the one expected pre-B-pass gap (now resolved by this file).
- **Blast-radius `requires:` list.** `platform` tier's `requires: [regression_test, behavioral_test_path, code_review_b_pass, feature_flag]` checked individually against the diff, not just the tier label — all four independently confirmed satisfied (kill-switches verified live in source at all 3 call-site guards).
- **Guard mirror on the getters' consumers.** All production call sites of the 3 getters traced (`progression_resolver.dart:63`, `plan_generator.dart:196`/`211`, `workout_schedule_read_service.dart:824`); no caller special-cases either polarity. Other `applyInjurySubstitutePreference` default-parameter sites confirmed to be pre-existing, documented, frozen test/mirror tooling unrelated to this diff.
- **function_exception_swallow / unawaited_no_error_sink / secrets_in_tree / writer_reader_drift / missing_input** — all not applicable or clean; diff touches no EF call, no fire-and-forget async, no credential-shaped literal, no cloud-Hive field contract, no new external path/package.
- **Full local gate loop** (`sh scripts/pre-commit.sh`) — exit 0, all gates pass, `OPEN_INDEX.md` regenerates byte-identical to the staged copy.
- **`flutter analyze lib/`** — 45 pre-existing infos, 0 warnings/errors, none in any file this branch touches.
- **`check_sot_registry_parity.dart`** — PASS, 0 errors.
- **Staging hash** — confirmed exact: `1cadbcd1d01fb676a8fb3a661c75197dfd6f2a33`.

## Founder triage notes

Ran under this session's standing "Batch 1" execution authorization (commit/merge/push through to done for this specific 3-flag batch; autonomous mode covers B-pass triage since none of the 3 findings are a live apply, an APK build, a product fork, or a hard blocker). All 3 findings independently re-verified by the orchestrating session against real git/file state before triage (not accepted on the reviewer's prose alone) — see each finding's `verification:` command, all reproduced. Finding 1 is the only one with real (if modest) risk: an unenforced "someone will do this later" note in a doc this exact ledger has drifted wrong on 3 separate prior occasions (27/5/1 days). Resolved by doing the follow-up commit now rather than leaving another intention.
