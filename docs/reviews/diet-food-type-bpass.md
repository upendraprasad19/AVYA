---
reviewed_at: 2026-11-14T15:49:29+05:30
staged_against: 74085219 (committed three-dot diff origin/main...74085219, base 2a255fb0, review CI green on the head)
blast_radius: platform
reviewer: claude-sonnet-via-skill (one fresh agent, no conversation context; lens 6 with a read-and-mutate protocol)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
verdict_note: all five findings fixed in the follow-up commit on this branch; each new guard was mutated and reddens a test (diagnose 6f5aaa, rows F1 to F5c)
---

# Code Review (B-pass) — diet plan Unit 2a, one food-type vocabulary on the client (`diet-food-type`, PR #270) at 74085219

No P0, P1 or P2. Five P3 findings, all fixed in the same branch. The reviewer ran the nine listed test files (117 tests, `TZ=Asia/Kolkata`), all green.

## Finding 1 — P3 — guard_without_its_mirror
- **file:line:** `lib/core/constants/food_types.dart` `foodTypeOf` (`if (raw is! String) return kDefaultFoodType;`); `test/core/food_types_test.dart`
- **claim:** an unknown non-empty string reads as Veg so a deliberate unknown choice never gets meat, but a corrupt non-String value (a list, a number, a bool) took the opposite path and read as Non-veg, which serves everything. Reachable only through a corrupted Hive value (the cloud column is text). The shared fixture and the Unit 2b server mirror must agree.
- **verification:** `grep -n "raw is!" lib/core/constants/food_types.dart`
- **suggested-fix:** default only for `null`; any other non-String reads as `FoodType.veg`; fixture rows so 2b mirrors it.
- **status:** fixed. `null` → Non-veg; other non-Strings → Veg. Fixture rows `42`, `true`, `["non_veg"]` (expected `veg`, known `null`). Mirrored in Unit 2b (`normalizeFoodType`, commit b76694b1, fixture byte-identical). Mutation F1 reddens 4 tests.

## Finding 2 — P3 — guard_without_its_mirror
- **file:line:** `lib/features/nutrition/screens/diet_plan_screen.dart` `_changeFoodType`; `lib/features/profile/providers/profile_provider.dart` `_applyFoodType`
- **claim:** `_applyFoodType` returned without writing when the account changed while the call was queued, and `setFoodType` returned normally, so the screen announced "Plan rebuilt for <new type>" over a plan rebuilt for the old one.
- **verification:** read both methods; the snackbar used `next`, not the re-read type.
- **suggested-fix:** return a bool from `setFoodType` and show the failure path when nothing was written.
- **status:** fixed. `setFoodType` returns `Future<bool>` (false only for the account-change drop; an unchanged value is true). The screen shows "Couldn't change the food type" on false through `_showFoodTypeChangeFailed` (also the catch path). Tests: an account change returns false (writer/reader test), and the screen shows the failure and no "Plan rebuilt" (`diet_plan_screen_no_modal_test`). Mutations F2a and F2b each redden 1.

## Finding 3 — P3 — guard_without_its_mirror
- **file:line:** `lib/features/nutrition/providers/diet_plan_provider.dart` `savedPlanMatchesFoodType` (`if (saved == null) return true`) with `diet_plan_screen.dart` `_savePlan`
- **claim:** a plan saved before Unit 2a has no `food_type` and loaded for any type; a re-save stamped it with the current type, so a chicken plan became a "Veg" plan that matched for ever.
- **verification:** read `_savePlan`: it stamps `_foodType.storageKey` whatever the plan's origin.
- **suggested-fix:** judge a legacy plan by its items with `passesDiet`, or treat it as non-matching for any type but Non-veg.
- **status:** fixed. A legacy plan matches Non-veg; for any other type every item's `food_id` must have a food-box row that passes `DietPlanGenerator.passesDiet(row, type, family: dietCatalogFamily(id))` (new catalog lookup, so an eggetarian keeps an egg dish and a pescatarian a fish dish). A missing row or id does not match. The screen's notice for such a plan reads "Your saved plan has foods outside <type>". Mutations F3a (items not judged), F3b (family dropped; survived the first test set, a family test was added) and F3c (missing row passes) each redden.

## Finding 4 — P3 — writer_reader_drift
- **file:line:** `docs/sot_registry.yaml`: `user_full_name` writer `_save` (`1665-2032`) and the injuries reader `_buildInjuriesChips` (`1203-1283`)
- **claim:** both ranges were shifted by hand and not recomputed from the symbols (`_save` then began at 1743, `_buildInjuriesChips` at 1291); stale before the diff too; the parity gate checks bounds only.
- **verification:** `grep -n "Future<void> _save\|Widget _buildInjuriesChips" lib/features/profile/screens/edit_profile_screen.dart`
- **suggested-fix:** re-anchor both to the real spans.
- **status:** fixed. Every Edit Profile range re-anchored by hand on the final tree (`_save` 1743-2145 in both entries, `_buildInjuriesChips` 1291-1356, the coach lock 1861-1890); the other shifted files remapped from the symbols by script; `check_sot_registry_parity` PASS.

## Finding 5 — P3 — guard_without_its_mirror
- **file:line:** `profile_provider.dart` `_applyFoodType`; `edit_profile_screen.dart` `_save` (same order)
- **claim:** `pushSnapshot()` fired before `lockFields(...)`, so the daily-snapshot extraction could run before the lock landed. Not worse than Edit Profile, but against the doc comment.
- **verification:** read the two call orders.
- **suggested-fix:** fire the lock first, or wait for it before the push.
- **status:** fixed at BOTH doors. The provider chains `lockFields(...).catchError(...).whenComplete(pushSnapshot)`; Edit Profile builds `lockDone` before the sync block and pushes in `lockDone.whenComplete(pushSnapshot)`. Neither door awaits the network. Tests: the push waits for a held lock, a failed lock still pushes (writer/reader test, a `Completer`-gated fake), and an ordering pin in `coach_extraction_locked_fields_writer_to_reader_test`. Mutations F5a, F5b and F5c each redden.

## Clean lenses (reviewer)
- **writer_reader_drift:** every `diet_preference` writer writes `FoodType.storageKey` (`setFoodType`, Edit Profile `_save`, onboarding, plan screen); readers `foodTypeOfProfile`, the sync pass-through and the snapshot builder; the saved plan's `food_type` survives the whole-`plan_json` upsert and restore.
- **function_exception_swallow:** no added `functions.invoke(`.
- **blast_radius_mismatch:** platform, from the `_shared/testdata` fixture; no Edge Function code in 2a.
- **secrets_in_tree:** none.
- **unawaited_no_error_sink:** `pushSnapshot` catches inside; `lockCoachExtractionFields` retries and records telemetry; the PDF builder move kept the snackbar and share path on the screen.
- **missing_input:** the fixture exists and both readers load it.
- **asserted_fixture_value:** the archetype floors pass over 50 seeds (not recomputed by the reviewer); the independent `allowedFor` oracle does not call `passesDiet`; egg/fish positive controls present.

## Founder triage notes
Platform tier: the B-pass is required by the merge seam. Every finding was fixed in the branch before the merge go is asked. Merge order: after Unit 2b (PR #271) and its four Edge Function deploys.

## Tuning entry
- **2026-11-14** - blast-radius platform - 5 findings; 0 false_alarm; tuning: none to the lens set. Observed: the reviewer's lens-6 reading found three mirror cases the build's own 29 mutations never touched (corrupt non-String, a dropped write announced as done, a legacy plan re-stamped); the fix's first mutation set then let one new guard survive (the catalog family dropped from the legacy check) until a family test was added. A fix to a mirror case is itself a guard with a mirror: mutate each fix's inputs, not only its branch.
