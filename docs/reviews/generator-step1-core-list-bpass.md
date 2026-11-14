---
reviewed_at: 2026-11-08T22:30:00+05:30
staged_against: generator-step1-core-list (commit 93550461) vs merge base 0633a121
blast_radius: platform
reviewer: fresh-context-blind-sonnet-agent (adversarial B-pass)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, off_identity]
findings_count: 2
verdict: accepted
---

# Code Review (B-pass) — generator step 1A, core-list pool fixes (`generator-step1-core-list`)

A fresh, context-blind Sonnet agent reviewed `git diff 0633a121 93550461` (23 files) with the eight lenses of
the skill plus an OFF-identity check, read-only, allowed to run four named test files. origin/main was 4 commits
ahead (a version bump and Edge Function backup JSONs); none of the branch's files is among them (checked with
`git diff --name-status $(git merge-base HEAD origin/main) origin/main`), so the review base is not stale for
this diff; `land_pr.sh` syncs before the push.

**Verdict: no P0, P1 or P2.** Two P3 findings, both triaged below with no code change.

## Finding 1 — P3 — guard_without_its_mirror (R3 (a) single-row reduced pool)
- **file:line:** lib/shared/repositories/plan_engine/core_list_selector.dart:337-361; test/contracts/core_list_like_for_like_data_test.dart:34-65
- **claim:** The like-for-like reduction can leave a one-row pool (for example `home_dumbbells|beginner|Calves|knee_dominant|` = [E258]); Calves isolation slots appear in both A and B variants, and B's soft-avoid only re-sorts, so B repeats A's row where before 1A a bodyweight calf raise (G1373) could be B's pick. The guard checks `ll.isNotEmpty`, not the size.
- **verification:** `python3 -I` over assets/data/exercise_library.json listing calves knee_dominant rows with core_levels (E051, E052, E066, E193, E258, G1373, G0409).
- **suggested-fix:** accept and document, or pin the repeat as intended.
- **status:** accepted_as_designed. The trade (an implement row repeated over an improvised alternative) is the plan's named consequence: diagnose c756b4 `impact_analysis` ("a one-row reduced pool makes variant B and phase 2 repeat that row (reported per cell)") and plan section 7 "B repeats A", which lists the 17 one-row cells of the 31 and the measured audit effect (week-1 vs week-2 same-day repeats 52,953 to 53,196, +0.5 percent). The remedy is more loaded rows per movement, ledger entry 1B-8 (OI-148 equipment variants, founder-signed list). No code change.

## Finding 2 — P3 — inconsistency (tier casing)
- **file:line:** lib/shared/repositories/plan_engine/core_list_selector.dart:142 vs :367
- **claim:** `needsImplementPreference` looks up `EquipmentVocab.tierItems[equipmentTier]` with the raw string; the new fit kit uses the lower-cased tier. Matters only for a capability-null mixed-case tier.
- **verification:** `git show 93550461:lib/shared/repositories/plan_engine/core_list_selector.dart | grep -n "tierItems\["`
- **suggested-fix:** use one form.
- **status:** false_alarm. Unreachable: the tier reaches the selector from `PlanGenerator.generateV4`'s `equipment` argument (plan_generator.dart:196, :211), the same string the generator itself keys into `EquipmentVocab.tierItems` raw (`_getEquipmentList`, plan_generator.dart:426-427). The tier keys are the lowercase onboarding values, and a mixed-case tier would already fall back for the whole plan before reaching this line. Changing the B1 function would edit a line outside 1A's scope with no reachable effect.

## Clean lenses (reviewer's evidence, abridged)
- **OFF identity:** `plan_generator.dart` not in the diff. `rankedPool` is reached only from `_pickCoreList` (flag ON and `hasCoreFields`, exercise_selector.dart:592-594). The cascade exit passes `coreListOnly: false`; the ladder then runs once with the old order. At buildPinnedDays (:1161) the flag sits on the left of `&&`, so `getAll()` is not called with the flag OFF, and the flag getter returns false on error.
- **writer_reader_drift:** the three new trace fields are set in all three `rankedPool` returns and read at exercise_selector.dart:867-869. The registry entries carry no line ranges. The seam allowlist went from 17 to 18 for the new `getAll()`.
- **function_exception_swallow / unawaited:** none in the diff.
- **secrets:** none seen in the diff.
- **guard mirrors:**
  - A jump-only pool is kept and a mixed pool is partitioned. `jumpOnlyPool` is computed after the empty-pool return.
  - Contraindicated rows leave the pool in `passes()` before the partition.
  - A bodyweight user who owns dumbbells gets the implement preference via the capability set.
  - The like-for-like reduction never empties a pool.
  - The fit key is constant for a pure bodyweight kit.
  - Pass 2 resets the memo.
  - `isCoreAtOrEasier` treats an unknown level and `core_levels: []` (653 of 862 rows) as not core.
- **missing_input:**
  - All 862 rows carry `core_levels` and `high_impact`.
  - `primary_muscles` and `exercise_type` are lists in every row.
  - 19 rows have `high_impact: true` and 14 are `plyometric`.
  - The calf heads are literally "Calves (Gastrocnemius)" and "Calves (Soleus)".
- **asserted_fixture_value:**
  - E011, E010, E047, E021, E051, E052 and G0980 match the library.
  - `_expected` has 31 entries, each checked by the restated rule.
  - The absence assertions would fail if the reduction did nothing.
- **Tests run by the reviewer:** core_list_like_for_like_data_test.dart and thin_day_topup_behavioral_test.dart passed (46 tests).

## Founder triage notes
Triaged by the coordinating session: F1 accepted as designed (documented trade, OI-148 remedy in 1B), F2 false alarm (unreachable). No code change, so the gate loop and the 2,304-plan audit of 93550461 stand.

## Tuning entry
- **2026-11-08** - blast-radius platform - 2 findings; 1 false_alarm; tuning: none (F1 was the plan's own named consequence; a reviewer brief for a ship-dark ranking change should hand over the plan's "named consequences" list so a documented trade is not re-reported as a finding).
