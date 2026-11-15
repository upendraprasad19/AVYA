---
reviewed_at: 2026-11-14T14:25:00+05:30
staged_against: 3da92d26 (committed three-dot diff origin/main...3da92d26, base 94a021a0, CI green on the head)
blast_radius: account
reviewer: claude-sonnet-via-skill (one fresh agent, no conversation context; lens 6 with a mutate-and-restore protocol)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 4
verdict: accepted
verdict_note: all four findings fixed in the follow-up commit on this branch; lenses 3 and 4 were completed by the coordinator (below)
---

# Code Review (B-pass) — diet plan Unit 1, curated catalog generator (`diet-food-quality`, PR #269) at 3da92d26

No P0 or P1. Four findings, all fixed in the same branch.

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** `lib/features/nutrition/services/curated_diet_plan_generator.dart` `_sizeSlot` (`slotKcal`)
- **claim:** `slotKcal = inputs.calorieTarget * t.share` is a divisor in the portion score. A stored `daily_calories` of 0 reaches the generator as 0 (`nutrition_provider.dart:65-77` passes it through; the screen's `?? 2400` covers only a missing key), every score is NaN, `bestMults` stays null and `bestMults!` throws out of `generate()`; the legacy fallback covers only `best == null`.
- **verification:** `grep -n "slotKcal" lib/features/nutrition/services/curated_diet_plan_generator.dart`
- **suggested-fix:** `max(1.0, …)` on the divisor; a zero-target test.
- **status:** accepted, fixed (`max(1.0, inputs.calorieTarget * t.share)`; test `a zero or negative calorie target never throws` in `test/nutrition/curated_diet_plan_test.dart` T6; mutant "guard removed" reddened it, 1 test).

## Finding 2 — P2 — asserted_fixture_value / guard_without_its_mirror
- **file:line:** `lib/features/nutrition/screens/diet_plan_screen.dart` Regenerate `onPressed`; `test/contracts/diet_plan_curated_switch_test.dart`
- **claim:** nothing pins that Regenerate increments `_regenerations` BEFORE `_generateFreshPlan()`; swapping the two lines brings back the "first Regenerate shows the same plan" bug with every test green.
- **verification:** `grep -rn "_regenerations" test/` (no hit before the fix)
- **suggested-fix:** a source pin on the order, or a widget test.
- **status:** accepted, fixed as a PRESENCE pin (stated as such): `_regenerations++;` immediately followed by `_generateFreshPlan();` in the `onPressed`, exactly one increment site, and the seed built from `_regenerations`. Mutant "lines swapped" reddened it (1 test). `dietPlanSeed` itself stays behavioural in T6.

## Finding 3 — P3 — asserted_fixture_value
- **file:line:** `lib/core/services/seed_service.dart` (v4 comment)
- **claim:** the comment's "66 processed rows" did not match the 69 `is_ultra_processed` changes.
- **verification:** python diff of the two assets: `(False, True): 66, (True, False): 3`.
- **suggested-fix:** state both directions.
- **status:** accepted; the count was right (66 false -> true) and the comment now also names the 3 true -> false rows (F0708, F0709, F0710; 69 in all).

## Finding 4 — P3 — missing_input / writer_reader_drift
- **file:line:** `test/contracts/exercise_plate_library_data_test.dart:4, :168`
- **claim:** comments cite `seed_service.dart:227-228` and `:314`; this diff shifted those lines by 7.
- **verification:** `sed -n 225,240p lib/core/services/seed_service.dart`
- **suggested-fix:** cite by symbol.
- **status:** accepted, fixed (now `seedIfNeeded` / `needExerciseUpgrade` and `_seedExercises`). `grep -rn "seed_service.dart:[0-9]" test lib scripts docs/sot_registry.yaml` returns nothing.

## Lenses that returned clean (reviewer)
- **writer_reader_drift:** the asset diff, the saved-plan key set (`role` is never persisted; `slotKey` re-derived on load), `syncSavedDietPlan` payload, registry line ranges for `diet_plan_screen.dart` (254-306, 54-76) and the seed upgrade (putAll by id, version key written after success, custom/community ids cannot collide, a v3 box still generates).
- **function_exception_swallow:** no `functions.invoke(` in the diff.
- **unawaited_no_error_sink:** no new `unawaited(`.
- **guard_without_its_mirror:** legacy fallback, `curatedEnabled` fail-open to the new path, `resolveSwapRole` null, swap exclusions, plural rule (observation: a future 0.5 portion on an egg descriptor would print "(1 eggs)"; no catalog entry has one today).
- **missing_input:** all 151 ids exist with every field the generator reads; no catalog row is UPF or zero-kcal; every parenthetical descriptor parses.
- **asserted_fixture_value:** F0522, F0001, F0007, the 151 count, F1442-F1448 verified from the data; 75 tests across 9 files green.
- Mutations: swap retire check removed (T9 red); coherence + family cap removed (T9(d) red). Files restored, sha256 equal; `git status --porcelain` empty.

## Lenses completed by the coordinator
- **blast_radius_mismatch:** `dart run scripts/blast_radius_from_diff.dart <every changed path>` → `account`, matching the record. Rollback for the account-tier change: the local kill switch (`DietPlanFlags`), honestly limited, and OI-508 for the legacy path.
- **secrets_in_tree:** `git diff origin/main...HEAD | grep -nE '^\+.*(sk-[A-Za-z0-9]{10}|rzp_live_|rzp_test_[A-Za-z0-9]{6}|AKIA[0-9A-Z]{12}|-----BEGIN|eyJhbGciOi|service_role_key\s*[:=])'` over the WHOLE diff (tests, script, asset, docs included) → no line.

## Founder triage notes
Account tier: the verdict is advisory (skill §4); every finding was fixed in the branch before the merge go is asked.

## Tuning entry
- **2026-11-14** - blast-radius account - 4 findings; 0 false_alarm; tuning: none to the lens set. Observed: the reviewer left lenses 3 and 4 partly covered on a 23-file diff with a 4.6k-line asset; the coordinator closed them with one command each. Next time give the asset-heavy diff its own seat or name the two commands in the brief. The reviewer also set `reviewed_at` to a wrong clock time; the coordinator set it from `TZ=Asia/Kolkata date`.
