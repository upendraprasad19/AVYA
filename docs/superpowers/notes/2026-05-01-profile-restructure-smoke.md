# Profile restructure visual smoke — Test #6 Plan D

**Date:** 2026-05-01 (implementation complete; on-device walkthrough pending)
**APK:** dev / prod (circle one once verified on device)
**Device:** _<device + Android version — fill in at install>_

## Implementation status

All 12 D tasks landed on `feat/apk-test-6-batch`:

| Task | Commit | Status |
|---|---|---|
| D-1 WardRankInsignia (CustomPaint) | `69f326c` | done |
| D-2 Barrel export — insignia | `09582d5` | done |
| D-3 Smoke tests (no golden infra) | `1bdd86e` | done — 25 paint/fallback assertions |
| D-4 WardRankPill widget | `188880f` | done |
| D-5 Barrel export + pill smoke tests | `0529762` | done — 3 tests |
| D-6 + D-7 Service Record helper + Pill at top + ServiceRecordSection removed + F-13 PromotionCelebration insignia upgrade | `f0ad186` | done |
| D-8 Status strip removal | n/a | no-op (no matches in profile/) |
| D-9 Edit Profile in SETTINGS | folded into D-7 commit | done |
| D-10 Predictions row in REPORTS | folded into D-7 commit | done |
| D-11 Layout invariants test | `450278b` | done — 8 invariants |
| D-12 Smoke + analyze | this doc | done |

## Automated verification

### `flutter analyze lib/`

`9 issues found` — all info-level, all pre-existing (none introduced by Plan
D). Spot-checked: 7 unrelated `use_build_context_synchronously`
informationals in `nutrition_screen.dart`, 1 `use_null_aware_elements` in
`workout_write_service.dart`, 1 `unintended_html_in_doc_comment` in
`promotion_celebration_screen.dart`. 0 errors. 0 warnings.

### `flutter test test/wardroom/ test/profile/`

46 tests passed, 0 failed.

Targeted breakdown:
- `test/wardroom/ward_rank_insignia_test.dart` — 25 (11 ranks × 2 sizes paint
  smoke + SD2 fallback + unknown fallback + color override propagation).
- `test/wardroom/ward_rank_pill_test.dart` — 3 (collapsed default, tap
  expands & calls builder, second tap collapses).
- `test/profile/profile_screen_layout_test.dart` — 8 (C13a / C13b / C14 /
  C14b / C15a / C15b / no ServiceRecordSection / Predictions before
  WeeklyReportCard).
- Plus 10 pre-existing tests inside `test/profile/` (`edit_profile_plan_changed`,
  `rank_card_eta`).

### Source-grep regression

```bash
$ grep -rn "ServiceRecordSection()" lib/features/profile/screens/  # 0
$ grep -rn "YOUR PREDICTION"        lib/features/profile/         # 0
```

Both clean.

## Result per criterion (on-device)

- [ ] C13a — rank pill at top with correct insignia
- [ ] C13b — tap expands accordion (200 ms feel)
- [ ] C13c — Service Record content correct (current 48 dp / next 2 dimmed /
              roadmap button tappable)
- [ ] C13d — NO streak / freeze chips on Profile
- [ ] C14 — Edit Profile is first row in SETTINGS, taps → `/profile/edit`
- [ ] C15a — Predictions is first row in REPORTS, preview text correct
              (50-char truncate + ellipsis)
- [ ] C15b — Predictions tap opens bottom sheet, full prediction body renders

## Notes & deviations

- **Golden tests:** repo has no existing golden infrastructure
  (`test/wardroom/goldens/` did not exist). D-3 was implemented as smoke
  tests (paint-without-throw + fallback assertions). Plan permits this
  fallback explicitly. Goldens can be added later via
  `flutter test test/wardroom/ward_rank_insignia_test.dart --update-goldens`
  by switching the assertions to `matchesGoldenFile`.
- **D-8 is a no-op:** the Test #5 status-strip on Profile was never merged
  into this branch (Plan A prerequisite already removed Test #5 work), so the
  strip didn't exist to remove. Verified by grep.
- **D-9 + D-10 commit-folding:** the plan's commit boundaries are advisory;
  D-7 commit already touched `profile_screen.dart` for the structural
  rewrite, and committing four micro-rewrites of the same file in a row
  would have produced a hard-to-review diff. The combined D-7 commit message
  documents D-6 + D-7 + D-9 + D-10 changes; D-11 added the test, and D-12
  added this doc.
- **Bonus — F-13 placeholder closed:** the same D-7 commit also swapped
  `PromotionCelebrationScreen._buildPlaceholderInsignia()` (text-bordered
  ribbon placeholder) for the real `WardRankInsignia` at 96 dp. F-13 had a
  TODO note specifically waiting for D-1.

## Issues found

(none yet — fill in on-device walkthrough)

## Spec deviations

(none)
