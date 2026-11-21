---
reviewed_at: 2026-11-14T20:40:00+05:30
staged_against: 9ab96794 (committed three-dot diff origin/main...9ab96794, CI green on the head; PR #274)
blast_radius: platform
reviewer: claude-sonnet-via-skill (three fresh agents, no conversation context, one lens group each)
lens_set: [writer_reader_drift, missing_input, blast_radius_mismatch, guard_without_its_mirror, unawaited_no_error_sink, function_exception_swallow, asserted_fixture_value, secrets_in_tree]
findings_count: 14
verdict: accepted
verdict_note: no P0 or P1; 13 findings fixed in the follow-up commit on this branch, 1 (seat A finding 1) recorded as a stated limit because it is a pre-existing split that 3a keeps and does not widen
---

# Code Review (B-pass) — diet plan Unit 3a, diet strategy targets and selector, shipped dark (`diet-strategy`, PR #274) at 9ab96794

Three seats, each context-blind, each with its own lenses:
- seat A: writer/reader drift, missing input, blast radius (flag-off identity line by line against `origin/main`);
- seat B: guards and their mirrors, error sinks, exception swallowing;
- seat C: tests that pass for the wrong reason, fixtures, UI and copy.

No P0 or P1. Fourteen findings (5 P2, 9 P3). The coordinator re-checked every finding against the code before fixing it.

## Seat A — writer/reader, missing input, blast radius

### A1 — P2 — writer_reader_drift (reader parity, flag on)
- **file:line:** `lib/features/home/providers/home_provider.dart` `NutritionSummaryNotifier.build`, `lib/features/ai_coach/services/ai_snapshot_builder.dart` `_dietStrategyTargets`, `lib/features/nutrition/providers/nutrition_provider.dart` `_resolveNutritionTargets`
- **claim:** Home and the snapshot apply the strategy only to a complete stored four-pack; Nutrition also applies it to its recompute fallback. A profile with recompute inputs but no stored pack shows keto on Nutrition and Balanced (or defaults) on Home and in the coach.
- **disposition:** stated limit, not a code change. The split is pre-existing: on `origin/main` that profile already shows Home's 250/65 defaults, the snapshot's zeros and Nutrition's recompute. 3a keeps each reader's base and adds the strategy on top, so it adds no new disagreement. Onboarding writes all four keys, so the profile is not seen in practice. Recorded in `docs/sot_registry.yaml` (`diet_strategy_targets`, "Stated limit") and plan §3.3.

### A2 — P3 — blast_radius_mismatch (flag-off provider read)
- **file:line:** `lib/features/profile/screens/edit_profile_screen.dart` (`_dietStrategy` seed)
- **claim:** the seed read `macroTargetsProvider` unconditionally, so a flag-off Edit Profile built a provider that it did not build before 3a.
- **fix:** the seed is `DietStrategyFlags.enabled ? dietStrategyOfTargets(ref.read(macroTargetsProvider)) : kDefaultDietStrategy`. Pinned by a regex in `test/nutrition/diet_strategy_selector_test.dart` (PRESENCE).

### A3 — P3 — registry anchor
- **file:line:** `docs/sot_registry.yaml`, `setFoodType` range in `profile_provider.dart`
- **claim:** the range started mid doc comment (109; the comment starts at 93).
- **fix:** range `93-148`.

### A4 — P3 — missing_input (NaN / Infinity)
- **file:line:** `lib/core/constants/diet_strategies.dart` `dietStrategyOfTargets`
- **claim:** `raw is num` admits NaN and Infinity, and `toInt()` throws on them.
- **fix:** `if (raw is! num || !raw.isFinite) return kDefaultDietStrategy;`, with NaN and Infinity cases in `test/core/diet_strategy_targets_test.dart`.

## Seat B — guards, mirrors, error sinks

### B1 — P3 — function_exception_swallow (a throwing write)
- **file:line:** `lib/features/nutrition/services/diet_strategy_actions.dart` `handleDietStrategyTap`
- **claim:** a thrown `setDietStrategy` (a failed Hive write) escaped as an unhandled error, with no snackbar.
- **fix:** try/catch around the call; `ErrorTelemetry.recordNonFatal(reason: 'diet_strategy_change_failed')`; the same "Couldn't change the diet strategy. Try again." snackbar as a refused write. Test: "a write that throws says so and stores nothing" (the seam's `currentUserId` throws on the queued link's read).

### B2 — P3 — guard_without_its_mirror (a silent drop at Save)
- **file:line:** `edit_profile_screen.dart` `_save`, `confirmEditProfileDietStrategy`
- **claim:** when PRO lapses between the chip tap and Save, the rest of the profile saves and the strategy is silently dropped.
- **fix:** `_save` records `strategyNotSaved`, and the snackbar comes from `editProfileSavedMessage(rescheduled:, strategyNotSaved:)`: "Profile saved. Keto needs PRO, so your diet strategy did not change." Tested: the pure helper, behaviourally; the wiring, by PRESENCE (registry note).

### B3 — P3 — guard_without_its_mirror (a no-preview tap says "updated")
- **file:line:** `diet_strategy_actions.dart` (snackbar after the write)
- **claim:** with no preview (only the hard-coded defaults are shown, so the strategy never applies) the snackbar said "Targets updated for Keto", but no number moves.
- **fix:** `dietStrategyResultMessage`: "Diet strategy set to Keto." when there is no preview. Tested in the widget flow ("no targets") and the pure copy test.

### B4 — P3 — unawaited_no_error_sink (`onFree` context)
- **file:line:** `diet_strategy_actions.dart`, `edit_profile_screen.dart` (`onFree` closures)
- **claim:** `showPaywallSheet(context)` had no `mounted` check. It is safe today because the feature is not server-verified and the callback is synchronous, but it would break if the feature moved to server verification.
- **fix:** `context.mounted` / `mounted` checks inside both closures. No test: the async path does not exist today.

## Seat C — tests, fixtures, UI and copy

### C1 — P2 — negative-fat clamp never exercised
- **file:line:** `test/core/diet_strategy_targets_test.dart`
- **claim:** no row drove `macroSplit`'s fat below 0, so deleting the clamp reddened nothing.
- **fix:** row 1200 kcal / 300 P / 300 C: low carb gives carbs 75 and fat 0, keto gives carbs 20 and fat 0, both asserted as literals.

### C2 — P2 — flag-off snapshot identity checked only two keys
- **file:line:** `test/contracts/diet_strategy_targets_writer_to_reader_test.dart`
- **claim:** the "byte-identical" claim was tested by two absent keys.
- **fix:** with the flag off and PRO, the JSON of the WHOLE `buildAiContext()` is equal with and without a stored `keto`, and the `profile` and `daily_targets` key sets are hard-coded.

### C3 — P2 — behaviours covered only by presence tests or not at all
- **claim:** the PDF strategy header, the Nutrition tag wiring and the Edit Profile chip and Save flow had no behavioural test.
- **fix:**
  - PDF: `dietPlanPdfSubheader` is extracted and tested (null, Keto), and `buildDietPlanPdf` / the header call are pinned.
  - Nutrition tag: `food_type_tag_test.dart` requires `strategy: nutrition.strategy,` at the call site, plus a widget test of the strategy tag.
  - Edit Profile: PRESENCE ONLY, with the reason recorded in the registry (the writer entry's `notes`). The decision helpers it calls are behavioural.

### C4 — P3 — raw-reader regex evasions
- **file:line:** `test/contracts/diet_strategy_raw_target_reader_pin_test.dart`
- **claim:** the regex saw only single-quoted index reads.
- **fix:** it also matches double quotes and `.get('…')`, with four new positive controls and a negative control (a bare string literal). The whole-file allow-list stays (each entry carries its reason). A key built from a variable is still unseen, and the file header says so.

### C5 — P3 — copy: "already low in carbs" / "updated" when nothing moved
- **fix:** `dietStrategyResultMessage`:
  - same shown targets, Balanced: "Balanced is set. Your targets stay the same."
  - same shown targets, another strategy: "Low carb is set. Your targets stay the same: your carbs are already this low."
  - no preview: "Diet strategy set to Keto."
  - otherwise: "Targets updated for Keto".

### C6 — P3 — fixture not energy-consistent
- **file:line:** both test files' stored pack
- **claim:** 2400 / 150 / 280 / 80 sums to 2440 kcal.
- **fix:** carbs 270 (4×150 + 4×270 + 9×80 = 2400); the hard-coded-defaults assertion (280) is unchanged because it pins the defaults, not the fixture.

## Mutations (each applied, confirmed with a count, run, restored)

| Mutant | Target | Result |
|---|---|---|
| M19 | `isFinite` check removed | red (1) |
| M20 | negative-fat clamp removed | red (1) |
| M21 | try/catch around `setDietStrategy` removed | red (1) |
| M22 | no-preview snackbar says "Targets updated" | red (2) |
| M23 | dropped-strategy suffix removed from the saved message | red (1) |
| M24 | a raw `diet_strategy_raw` key added to the snapshot with the flag off | red (1; only the new whole-snapshot test sees it) |
| M25 | PDF strategy suffix removed | red (1) |
| M26 | raw-reader regex back to single quotes | red (1) |

Two first drafts of M22 and M23 failed to COMPILE (a removed null check; a type-promotion loss) and were not counted. They were rewritten as the regression a real edit would make. The 18 pre-review mutants (M1 to M18) were re-run after the fixture change: see the follow-up commit message.

## Lenses completed by the coordinator
- **secrets_in_tree:** `git diff origin/main...HEAD | grep -nE '^\+.*(sk-[A-Za-z0-9]{10}|rzp_live_|rzp_test_[A-Za-z0-9]{6}|AKIA[0-9A-Z]{12}|-----BEGIN|eyJhbGciOi|service_role_key\s*[:=])'` → no line.
- **blast_radius_mismatch:** `blast_radius_from_diff.dart` over the changed paths → `platform`, matching the record. Rollback: the flag is off by default; the migration has an inline rollback.

## Founder triage notes
Platform tier: every finding was fixed or recorded before the merge go was used. The founder approved the migration 179 apply and the PR #274 merge in chat (2026-11-14), conditional on this review passing.

## Tuning entry
- **2026-11-14** - blast-radius platform - 14 findings; 0 false_alarm; tuning: none to the lens set. Observed: seat C (tests) found the most (3 of the 5 P2s), all "a test that cannot see the break"; giving test-observability its own seat paid off again. Two of the coordinator's own fix mutants first failed to compile (null-promotion); a compile error is not red, and the runner's `compile_err` flag caught it.
