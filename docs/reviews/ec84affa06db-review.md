---
reviewed_at: 2026-11-26T00:40:00+05:30
staged_against: ec84affa06dbf51120b40ae5b1386e9cee6785c3
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 8
verdict: accepted
verdict_note: one fresh context-blind seat on the CI-green head (three-dot diff origin/main...ec84affa); 0 P0/P1, 2 P2, 6 P3; all eight fixed or answered in the same branch, 0 false alarms
---

# Code Review — ec84affa (nutrition-history, Landing A)

## Finding 1 — P2 — unawaited_no_error_sink
- **file:line:** lib/core/services/target_history_service.dart (the un-awaited `box.put` in `reconcile`)
- **claim:** a failing put escaped the method's try/catch and its telemetry.
- **verification:** `grep -n "target_history_put" lib/core/services/target_history_service.dart`
- **status:** accepted. The put carries `.catchError` recording `target_history_put`; `reconcile` stays synchronous (recorded decision). No behavioural test: nothing in the harness makes a Hive put fail after the call returns; presence only.

## Finding 2 — P2 — guard_without_its_mirror
- **file:line:** target_history_service.dart `reconciled`
- **claim:** an entry dated after today (clock ahead, then corrected) blocked every later recording until the real date passed it.
- **verification:** `TZ=Asia/Kolkata flutter test test/contracts/nutrition_target_history_writer_to_reader_test.dart --plain-name "dated after today"`
- **status:** accepted. Future-dated entries are dropped before reconciling. Tests: pure (three shapes) and on real Hive; mutant N1 reddened 2.

## Finding 3 — P3 — guard_without_its_mirror
- **file:line:** nutrition_history.dart `parseDayKey` / `countedRow`
- **claim:** the lenient parse accepted `2026-13-45`, `2026/11/25` and a time-suffixed date, so the weekly cards could count a row Today never counts.
- **verification:** test "a day key is strict"
- **status:** accepted. A day key is exactly ten characters, `-` separated, and round-trips; `countedRow` requires one. Mutants N2, N3, N8 each reddened 1.

## Finding 4 — P3 — guard_without_its_mirror
- **file:line:** nutrition_history_provider.dart `buildNutritionHistoryData`
- **claim:** one garbled old row made the series unbounded.
- **status:** accepted. `kHistoryMaxDays` (ten years) floors the first day. Mutant N4 reddened 1.

## Finding 5 — P3 — writer_reader_drift (stale registry cites)
- **file:line:** docs/sot_registry.yaml, `nutrition_repository.dart` cites
- **claim:** ranges for `getDailyMacros`, `getCaloriesForDate`, `dailyMacros` did not start at the method.
- **status:** accepted. Seven cites of that file re-derived by hand from the doc comment to the closing brace (they were already off on main; the diff-based remap preserved the offset). Parity gate green.

## Finding 6 — P3 — guard_without_its_mirror (PRO not yet known)
- **claim:** a profile write before PRO is known records a Keto user's Balanced carbs / fat until the next trigger that day.
- **status:** accepted as a stated limit, written into the service header: calories and protein never depend on the strategy, so no status or hit-rate is affected, and the same-day replace heals it at the next trigger. The subscription service exposes no "unknown" state to skip on.

## Finding 7 — P3 — guard_without_its_mirror (zero target)
- **claim:** a stored calorie target of 0 was recorded and judged every day "over".
- **status:** accepted. `reconcile` records nothing for calories <= 0 and the provider treats such an entry as no target. Mutants N5, N6 each reddened 1.

## Finding 8 — P3 — rule compliance (accessibility, copy)
- **claim:** the painted heatmap had no text alternative; "Under" was shown for a day with calories in band and protein short.
- **status:** accepted. `heatmapSummary` is the heatmap's semantics label; a new status `lowProtein` ("Low protein", its own legend colour) replaces "Under" for that case. Mutant N7 reddened 1.

## Founder triage notes
Run autonomously on the founder's "go. run autonomously" (2026-11-25); no finding needed a founder decision.

## Tuning entry
- **2026-11-26** - blast-radius account - 8 findings; 0 false_alarm; tuning: none. Note for lens 1's inserted-lines sub-check: a diff-based old-line to new-line remap keeps a cite that was ALREADY off on main exactly as off; after the remap, check that each cite of a file whose length changed still starts at the method's doc comment.
