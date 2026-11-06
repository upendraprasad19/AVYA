---
reviewed_at: 2026-10-21T15:14:00+05:30
staged_against: cc4640904a13
renamed_to_final_hash: d15cd2688bbc
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
---

# Code Review — d15cd2688bbc (reviewed at cc4640904a13)

Branch `l2-no-custom-autoadd` (Batch 0a, diagnose d4b8e1): plan-generator lever L2
(auto-append of custom exercises) removed, L6 kept. One fresh read-only Sonnet reviewer,
exhaustive command list (read-only git, file reads, the one new test file, `flutter analyze` of
plan_engine/), no file mutation allowed (a full suite was running on the same tree).
Result: 0 P0, 0 P1, 1 P2, 4 P3. Renamed to the final staged hash after the fixes below.

## Finding 1 — P2 — blast_radius_mismatch
- **file:line:** docs/diagnoses/2026-10-21-l2-custom-autoappend-d4b8e1.md frontmatter; plan §4.6 waiver
- **claim:** diagnose said `account`; `lib/shared/repositories/plan_engine/**` and `docs/architecture/plan-engine-detail.md` are `platform` (docs/blast_radius.yaml:105, :120). Platform `requires` includes `feature_flag`; the §4.6 waiver is the author's — the founder's decision ("never auto-add customs") is the product call, not an acceptance of the waiver.
- **verification:** `grep -n "plan_engine/\*\*\|plan-engine-detail" docs/blast_radius.yaml`
- **suggested-fix:** frontmatter → platform; founder explicitly accepts the waiver; land the plan-review record before merge.
- **status:** accepted — frontmatter now `blast_radius: platform`; waiver acceptance asked of the founder in chat 2026-10-21 (recorded in the plan-review record); record lands in its own commit (hash-cycle rule, SKILL.md §3).

## Finding 2 — P3 — writer_reader_drift (claimed reader that does not exist)
- **file:line:** lib/features/train/widgets/create_custom_exercise_sheet.dart:494-497
- **claim:** new comment said the chip tokens are read by the swap/add pickers' muscle matching; no picker matches customs by muscle. Real readers: `_buildCustomExercise` (repeat pins), `TrainingHistoryAnalyzer._muscleTaxonomy` (training_history_analyzer.dart:432), picker subtitle (exercise_picker_sheet.dart:260).
- **verification:** `git grep -n "primary_muscles" -- lib/features/train/widgets/exercise_swap_sheet.dart lib/features/train/screens/active_workout/exercise_picker_sheet.dart`
- **suggested-fix:** name the real readers; check custom_muscle_vocabulary_test.dart:6-9.
- **status:** accepted — comment names the three real readers (verified by reading :425-437 and :260); the vocabulary test header reworded.

## Finding 3 — P3 — writer_reader_drift (stale L2 prose)
- **file:line:** custom_exercises_mutations_behavioral_test.dart:333; repeat_phase_pinned_selection_behavioral_test.dart:32; plan_generator.dart:133; docs/audit/open_issues.md:3839 (OI-211 step 3); diagnose `forbidden_patterns_checked`
- **claim:** stale L2 wording left behind; no assertion keys on it.
- **verification:** `git grep -n -E "\bL2\b|_eligibleCustomExercises|custom-append" -- lib test scripts`
- **suggested-fix:** reword the test comments; annotate OI-211; record plan_generator.dart:133 as a conscious carry-over.
- **status:** accepted — both test texts reworded; OI-211 annotated (step 3 now applies to buildPinnedDays.resolve(), which I verified re-applies exclusion + injury only, NOT the OI-89 capability check — my first draft of that note wrongly said it did, corrected before staging); plan_generator.dart:133 left (root rule 14) and recorded in the diagnose "Known limits"; forbidden pattern reworded to "as a CODE symbol".

## Finding 4 — P3 — guard_without_its_mirror (repeat-pin channel)
- **file:line:** exercise_selector.dart:754-761 (`buildPinnedDays.resolve` custom fallback); registry + nested CLAUDE.md wording
- **claim:** a REPEAT advance re-pins a custom L2 put into the finished phase; registry/CLAUDE.md text read as if every held custom was chosen. Unconverged 0b plan staged alongside.
- **verification:** `sed -n 735,775p lib/shared/repositories/plan_engine/exercise_selector.dart`
- **suggested-fix:** "until Batch 0b" qualifier, or accept the sequencing.
- **status:** accepted — qualifier added in sot_registry.yaml and plan_engine/CLAUDE.md; the r3 repair plan UNSTAGED from this branch (kept in the session scratchpad with its round-3 delta; it lands on the Batch 0b branch after a further review round).

## Finding 5 — P3 — asserted_fixture_value (mutation covers L2, not L6)
- **file:line:** diagnose `mutation_proven`; l2_no_custom_autoadd_behavioral_test.dart test (4)
- **claim:** no recorded mutation proves test (4) detects a broken L6.
- **verification:** mutate `result[i] = replacement;` and run the file
- **suggested-fix:** run one L6 mutation and record it.
- **status:** accepted — ran it: L6 replacement line commented out (grep -c 1 → 0, restored byte-identical by cmp) → test (4) RED on its L6 assertion, other 3 green. Recorded in the diagnose doc.

## Lens results (clean lenses)
- function_exception_swallow, secrets_in_tree, unawaited_no_error_sink, missing_input: clean (reviewer's commands: grep of added lines for invoke/catch/credential shapes/`unawaited(`; existence + shape of every helper and asset the test reads; the new test file 4/4 green; analyze of plan_engine/ clean).
- guard_without_its_mirror (beyond Finding 4): the gate change only removes the customs-only case; users without customs byte-identical; no other path appends customs (hotel/regenerate/preview go through pickV4; no server-side generation).
- asserted_fixture_value: the fixture customs' muscles substring-match real slot strings in split_resolver.dart under the old L2 logic, so test (1) is not vacuous; generation is deterministic (no Random/shuffle in plan_engine).

## Also fixed in this batch (author, from the full local suite)
Three Windows-only path-separator failures in unrelated contract tests
(body_measurement_sites_derivation, clean_orphan_media_pro_recheck,
lapse_gap_policy_writer_to_reader) — each compared a `listSync` path with a `/` literal;
now normalised with `replaceAll(r'\', '/')`. Linux CI was unaffected.

## Founder triage notes
Verdict set `accepted` by the author: platform tier, every finding resolved in this batch.
The §4.6 feature-flag waiver itself is the founder's call (asked in chat 2026-10-21).
