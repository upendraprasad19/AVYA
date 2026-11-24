---
reviewed_at: 2026-11-24T23:55:00+05:30
staged_against: b48f07cf
blast_radius: account
reviewer: claude-sonnet-seat-c
lens_set: [L1, L8, L10, L15, L16, writer_reader_drift, guard_without_its_mirror, mutation_survival, test_green_for_wrong_reason]
findings_count: 4
verdict: accepted
---

```yaml
diagnose_stanza:
  symptom: The two Diet Plan listener guards and the day-swap guards added after 7f4fc263 leave one guard with no pinning test (the supplements listener), one guard whose placement is unpinned, a screen-state edge that is swallowed when the post-window value equals the anonymous empty value, and one consumer (SwapConfirmSheet.build) that still reads raw boxes while signed out
  concept: auth_hive_owner_agreement
  writers:
    - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method: _onSupplementsActive (guard, then _checkedSaved/_regenerations/_generatePlan), line: 150 }
    - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method: _healSupplementsState (sets _healedFor before the guarded call), line: 180 }
    - { file: lib/features/train/providers/day_swap_provider.dart, method: daySwapAllowanceProvider guard (empty DayAllowance, limit freeLimit), line: 128 }
  readers:
    - { file: lib/features/train/widgets/swap_confirm_sheet.dart, method_or_widget: _SwapConfirmSheetState.build (ref.read(daySwapControllerProvider).preview -> DaySwapAllowance.current -> raw userBox), line: 65 }
    - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method_or_widget: initState listenManual(macroTargetsProvider.select(dietStrategyOfTargets)) -> _onEffectiveStrategy, line: 137 }
  hive_key_prefix: null
  hive_key_formula: null
  sync_methods: []
  restore_methods: []
  cloud_table: null
  cloud_columns: [null]
  contract_test_path: test/nutrition/diet_plan_strategy_screen_test.dart (must add: a supplements-listener signed-out case in the same file)
  ist_handling:
    - { file: lib/features/train/providers/day_swap_provider.dart, line: 137, fn: daySwapAllowanceProvider (unchanged, weekStart is an IST Monday passed in) }
  provider_invalidations: [daySwapWeekProvider, daySwapAllowanceProvider, authUserIdTokenProvider]
  telemetry_op_types:
    success: [diet_supplements_plan_healed]
    failure: [none]
  cross_account_guard: true
  forbidden_patterns_checked:
    - { pattern: "recordSwap|DaySwapAllowance.instance.current fed from daySwapAllowanceProvider", absent: true }
    - { pattern: "firstWhere\\([^)]*\\)\\s*;? without orElse on daySwapWeekProvider", absent: true }
  proposed_fix: F1 add a supplements-listener signed-out case (PRO + supplements on, token anon and back) to the screen test; F2 assert state not mutated in the window; F3 do not record _healedFor / do not log the heal event while the token is anon, and re-run the plan check when the token returns to a real uid whose value equals the empty value; F4 make SwapConfirmSheet.build return an empty box while the token is anon
  regression_test_planned: [test/nutrition/diet_plan_strategy_screen_test.dart]
```

# Seat C review of 7f4fc263..b48f07cf (the delta only)

Tree: `git rev-parse HEAD` = b48f07cf96b4a5a66159ed0dc3c71a24bc24c626. Baselines run first: `TZ=Asia/Kolkata flutter test test/contracts/signed_out_provider_rebuild_behavioral_test.dart` -> `+203: All tests passed!`; `test/nutrition/diet_plan_strategy_screen_test.dart` -> `+29: All tests passed!`.

## Findings

### F1 - P2 - lens: mutation_survival / guard_without_its_mirror - the `_onSupplementsActive` guard has no pinning test
- file: lib/features/nutrition/screens/diet_plan_screen.dart:152 (test: test/nutrition/diet_plan_strategy_screen_test.dart:602-632)
- claim: the diagnose-doc (proposed_fix item 4) says both listeners are guarded and "Test: ... 'a2d9f4: the signed-out window ...'". That test seeds only `diet_strategy: keto` (line 603) and drives the strategy listener. Nothing makes `dietSupplementsActiveProvider` differ between the signed-in and the anonymous value, so the second guard (line 152) can be deleted and every test passes. The doc's M7 line ("the Diet Plan screen listener guard off: 1 applied -> 1 red") covers the strategy guard only.
- verification: mutant M8 (below): `sed`/python replaced line 152 `if (ref.read(authUserIdTokenProvider) == '<anon>') return;` with `... == '<anon>' && false) return;`; `grep -c "'<anon>' && false) return;"` = 1 (applied); `flutter test test/nutrition/diet_plan_strategy_screen_test.dart` -> `+29: All tests passed!` (0 red). `grep -rn "_onSupplementsActive\|a2d9f4" test/nutrition` finds no other pin; `grep -n anon test/nutrition/diet_plan_supplements_screen_test.dart` = no hit (that file was not run: outside the allowed set).
- suggested-fix: add a case with PRO + `diet_supplements` on (so the signed-in `dietSupplementsActiveProvider` is true and the anonymous one false), flip the token source to `'<anon>'` and back, and assert `debugDietPlanGenerations` stays 1; confirm it reddens with M8.
- status: fixed: new screen test 'the supplements listener and the heal ignore the signed-out window' (guard-off mutant red, 2 red)

### F2 - P3 - lens: mutation_survival - guard placement (before vs after the first state mutation) is not pinned
- file: lib/features/nutrition/screens/diet_plan_screen.dart:140-146, test line 602
- claim: the new screen test only counts generations. If the guard sits AFTER `_checkedSaved = false; _regenerations = 0;` the count is still 1, but the window silently resets the user's Regenerate counter (the seed) and re-arms the saved-plan reload, so the next generation can replace an unsaved plan with the saved one.
- verification: mutant M7: removed the guard line and inserted `if (ref.read(authUserIdTokenProvider) == '<anon>') return;` between `_regenerations = 0;` (line 143) and `_generatePlan();` (line 144, shown by `grep -n "_regenerations = 0;" -A1`); the anon edge does reach it (anon value Balanced != requested Keto). `flutter test test/nutrition/diet_plan_strategy_screen_test.dart` -> `+29: All tests passed!` (0 red).
- suggested-fix: in the same test tap Regenerate before the window and assert the next Regenerate after the window continues the seed sequence (a plan different from the first), or read `_regenerations` through a `@visibleForTesting` seam.
- status: fixed: source-order pin test (guard before `_checkedSaved = false` in both listeners); guard-removal mutant red

### F3 - P3 - lens: writer_reader_drift - the early return swallows the only edge when the real value equals the anonymous empty value, and `_healedFor` is poisoned
- file: lib/features/nutrition/screens/diet_plan_screen.dart:139-140, 150-152, 172-186
- claim: `listenManual(macroTargetsProvider.select(dietStrategyOfTargets))` (lines 122-123) and `dietSupplementsActiveProvider` only fire on a CHANGE of the selected value. In the window the value becomes the empty one (Balanced / false) and the listener now ignores it. When the token returns to a user whose value is ALSO Balanced / false, the select sees Balanced -> Balanced and never fires, so: (a) a screen that built a Keto (or supplements) plan for user A stays on A's plan for user B (or for the same user after a PRO lapse inside the window) until the user taps Regenerate; (b) `_healSupplementsState` sets `_healedFor = active` (line 180) and logs `diet_supplements_plan_healed` (line 183) BEFORE the guarded `_onSupplementsActive` (line 185) no-ops, so `_healedFor == active` (line 179) blocks every later heal for that value and the event is a false positive each window. Same-user, same-value returns are fine (the new test covers them). Reachability needs `DietPlanScreen` (a sub-route, app_router.dart:481-489) to stay mounted across the window and the post-window value to equal the empty one; I judge it rare. Not executed (needs a new test); established by reading the select/dedupe contract and lines above. Before the delta the listener would have regenerated on user-less reads, which is the bug the guard removes, so this is not a regression of working behaviour.
- verification: `grep -n "_healedFor" lib/features/nutrition/screens/diet_plan_screen.dart` -> 164, 176, 179, 180; lines 182-185 show logEvent before `_onSupplementsActive`.
- suggested-fix: do not set `_healedFor` nor log the event while the token is anonymous; remember the token the plan was built under (`_planToken`) and, on the first non-anonymous listener or build, regenerate when it differs from the current one.
- status: fixed: the screen re-decides post-frame when the token returns (new test: Keto plan, the account turns Balanced in the window, one regeneration on return; token-listener-off mutant red); `_healSupplementsState` returns before logging or setting `_healedFor` while anonymous (heal-guard-off mutant red)

### F4 - P3 - lens: guard_without_its_mirror - `SwapConfirmSheet.build` still reads raw boxes in the window
- file: lib/features/train/widgets/swap_confirm_sheet.dart:65-66 (via lib/core/services/swap_service.dart:233-234, 238, hive_service.dart:278)
- claim: the sheet watches `daySwapAllowanceProvider` (line 59), so the token flip rebuilds it. The provider now returns the empty allowance, and the build continues to `ref.read(daySwapControllerProvider).preview(...)`, which calls `DaySwapAllowance.current` (userBox raw getter) and `_row` (workoutBox raw getter): `rawBox` throws on the empty stub. The guard therefore moves the throw from the provider to the widget; the Crashlytics class (a build() that throws while signed out) is not closed for this consumer. A modal sheet outlives the router redirect, so it can be on screen. Other consumers are safe: `DaySwapAllowanceLine` (reads only the provider), `day_swap_row_trailing.dart:38-45` and `swap_picker_sheet.dart:61-70` use `firstWhere` WITH `orElse`, `day_swap_drag_wrapper.dart:78-80` uses a map lookup, `tool_confirm_card.dart:339-347` uses `ref.read` + `orElse` (not rebuilt by the token), `week_rows.dart` does not use the provider.
- verification: `sed -n 60,70p lib/features/train/widgets/swap_confirm_sheet.dart`; `sed -n 227,240p lib/core/services/swap_service.dart`; `grep -n "Box get userBox" lib/core/services/hive_service.dart` -> 278 (`userBoxGuarded.rawBox`).
- suggested-fix: `if (ref.watch(authUserIdTokenProvider) == '<anon>') return const SizedBox.shrink();` before the `preview` read, with a case in `swap_confirm_sheet_test.dart`.
- status: fixed: `SwapConfirmSheet.build` returns an empty box on the anonymous token before `preview`; new widget test, guard-off mutant red

## Mutation table (one mutant at a time; each confirmed applied by `grep -c`; restored by `cp` and `sha256sum` equal to the original)

| # | File | Mutant | Applied | Test file | Result |
|---|---|---|---|---|---|
| M1 | day_swap_provider.dart | week guard `&& false` | 1 | behavioral | 3 red (daySwapWeekProvider A, B, C) |
| M2 | day_swap_provider.dart | allowance empty limit `DaySwapAllowance.proLimit` | 1 | behavioral | 3 red (allowance A, B, C: `limit == 1`) |
| M3 | day_swap_provider.dart | allowance guard `&& false` | 1 | behavioral | 3 red |
| M4 | day_swap_provider.dart | week guard moved BELOW the `weekStates` read | 1 | behavioral | 3 red |
| M5 | diet_plan_provider.dart:128 | dietPlan guard `&& false` (configBox holds a different legacy plan) | 1 | behavioral | 3 red |
| M6 | diet_plan_screen.dart:140 | strategy listener guard `&& false` | 1 | screen | 1 red (generations 2 vs 1): token override is honoured, test is not green for the wrong reason |
| M7 | diet_plan_screen.dart | strategy guard moved below `_checkedSaved/_regenerations` writes | 1 | screen | 0 red (SURVIVES, F2) |
| M8 | diet_plan_screen.dart:152 | supplements listener guard `&& false` | 1 | screen | 0 red (SURVIVES, F1) |
| M9 | day_swap_provider.dart | both guards inverted (`!=` / `!= '<anon>'`) | 2 | behavioral | 6 red |

"isEmpty weakened" could not be run (editing test/ is forbidden); M2 covers the `limit` clause of the allowance oracle and M5 the dietPlan seed.

## Q1 - day-swap providers' empty values and every consumer
Consumers (`grep -rn "daySwapAllowanceProvider\|daySwapWeekProvider" lib`): `tool_dispatcher.dart:41,207-208` (invalidate only); `day_swap_provider.dart:69-70` `_refresh` (invalidate only); `day_swap_allowance_line.dart:29` (display `allowanceLine`); `swap_picker_sheet.dart:61-62,186`; `swap_confirm_sheet.dart:59`; `tool_confirm_card.dart:339`; `day_swap_row_trailing.dart:38`; `day_swap_drag_wrapper.dart:78`. No consumer writes or counts a swap from the provider value: `recordSwap` has one caller (`swap_service.dart:389-391`) which re-reads `DaySwapAllowance.instance.current` itself (lines 325, 395); the provider is read-only. Allowance empty = used 0 / limit 1: `spent` is false (`day_swap_result.dart:71` `used >= limit`), so no upsell/refusal in the window for free or PRO; a free user who really is spent briefly sees the picker instead of `DaySwapSpentSheet` and a "1 swap left" line, and a PRO user "1 swap left" instead of 3, transient and cosmetic. Empty week `[]`: `swap_picker_sheet.dart:63` (`firstWhere` with `orElse`), `day_swap_row_trailing.dart:40` (with `orElse`), `tool_confirm_card.dart:341` (with `orElse`), `day_swap_drag_wrapper.dart:79-80` (map, null-safe) all tolerate it. One unguarded spot: `swap_picker_sheet.dart` `_onSwap` uses `before.values.first` as a fallback, which would throw only if a swap returns `DaySwapDone` while the week was empty; not realistically reachable (swapDays reads the same boxes). F4 is the residual throw.

## Q2 - diet_plan_screen listener guard
(a) Same user: the guard returns before any state write (`_planEpoch`, `_requestedStrategy`, `_checkedSaved`, `_regenerations`, `_droppedFrom` untouched); on return the value changes Balanced -> Keto, the listener fires with a real token, `dietPlanNeedsRegeneration` is false (requested == Keto), nothing regenerates: correct, and covered by the new test. (b) Different user with a different strategy from the empty value: the select fires with the new value and regenerates: correct. (b') A different user whose value equals the empty value: no fire, stale plan: F3. (c) `ref.read(authUserIdTokenProvider)` inside the listener: `macroTargetsProvider` and the supplements inputs both watch the token, so the listener runs only after the token provider has the new value; the read is the same value. A real user change cannot coincide with `'<anon>'` through the UI; a PRO lapse inside the window is the swallowed case in F3. `_healSupplementsState` post-frame path: see F3 (event logged and `_healedFor` set before the guard).

## Q3 - test honesty
(a) The new screen test reddens without the strategy guard (M6, 1 red, generations 2 vs 1) and the token override is live (the macroTargets value changes only because the overridden token flips). It does not cover the supplements guard (F1) or guard placement (F2). (b) Re-ran the dietPlan guard-off mutant (M5): 3 red, `Expected: true Actual: <false>` on the empty-value check (the configBox legacy plan is served). (c) Tripwire: re-derived counts with a python scan of lib/ (non-import, non-`//` lines, `\bauthUserIdTokenProvider\b`) and an independent `grep -rn ... | grep -vE ":[0-9]+:\s*(import |//)" | awk` count: 30 files, identical to `_kTokenWatchSites` (diff empty both ways; files in scratch `counts_actual.txt`, `g.s`). No count is hand-edited wrong. Pin weakness: files that mix `ref.watch` and `ref.read` mentions (`referral_summary_provider.dart` 6, `body_measurements_provider.dart` 3) pin a total, so a read swapped for a watch passes; the test text states the residue. (d) 9 mutants run (table).

## Q4 - signed-in behaviour
`daySwapWeekProvider`: the only change on the real path is one extra `ref.watch(authUserIdTokenProvider)` placed BEFORE `ref.watch(currentPlanProvider)`; the watch order moved, no dependency lost, the return expression is byte-identical (`git diff 7f4fc263 b48f07cf -- lib/features/train/providers/day_swap_provider.dart`). `Provider` does not notify on an equal value, so a token refresh with the same uid does not rebuild it. `daySwapAllowanceProvider`: the existing bare watch became `final token = ...` (same call), the rest unchanged. Listeners: one extra `ref.read(authUserIdTokenProvider)`; a signed-in user sees `'<anon>'` only in the pre-open window or with the `disable_live_auth_token_read` switch plus a null owner, where a user strategy change cannot happen. No signed-in change found.

## Founder triage notes

Triaged by the session coordinator: all four findings fixed in the commit after `b48f07cf` (no P0/P1). The re-decide listener first read the providers inside the token's own listener and regenerated twice (3 generations instead of 1, caught by the new test at once); it now runs post-frame.

## Tuning entry

- **2026-11-24** - blast-radius account - 4 findings; 0 false_alarm; tuning: when a guard is added to a LISTENER (not a build), ask for a pin per guard and per placement (survive-the-move mutant), and ask what the listener's select does when the post-window value equals the empty one (dedupe swallows the edge).
