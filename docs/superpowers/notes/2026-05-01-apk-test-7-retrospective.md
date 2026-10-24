# APK Test #7 Retrospective

**Date:** 2026-05-01  
**Branch:** feat/apk-test-7-batch → merged to main `9c815ba`  
**Commits:** 8 commits on branch  
**Tests:** 882 pass / 4 pre-existing fails (rank_service_test LS/PO/SubLt gate mirrors + sync_gap DeleteNutritionLogNotifier)  
**No migrations. No Edge Function deploys.**

---

## What shipped

7 fixes from on-device APK Test #6 observations (the +6 APK install session on 2026-05-01).

| Fix | Root cause | File(s) |
|-----|-----------|---------|
| Fix 7 — Home header double name | `home_screen.dart` title was `'$greeting, $firstName.'` — greeting already embedded the name (e.g. "Good afternoon, Upendra"), so `$firstName` appended "UPENDRA" again | `home_screen.dart` |
| Fix 6 — Streak freeze shown twice | `WardStatusStrip` passed hardcoded `freezesAvailable: 0` to `StreakBadge` AND rendered a separate `WardFreezeBadge(count: freezesAvailable)` — two freeze displays. Fix: pass real value to `StreakBadge`, remove `WardFreezeBadge` entirely | `ward_status_strip.dart` |
| Fix 5 — Induction pledge copy wrong rank | `_buildMsg2` said "Lieutenant Commander rank — 200 workouts" — wrong rank + wrong count. Should be "Sub Lieutenant rank — 104 workouts" (first officer commission, matches rank ladder from Test #6) | `induction_screen.dart` |
| Fix 1 — Mission Brief never shown on signup | `welcome_screen.dart` BEGIN ENLISTMENT tapped `context.go('/onboarding/identity')` — jumped directly past RestoringScreen and past the Mission Brief step. Fix: route to `/onboarding/mission-brief` which is already the correct RestoringScreen dispatch target for new users | `welcome_screen.dart` |
| Fix 8a — MissionBriefScreen readOnly mode | Screen had no way to be shown post-onboarding (from Profile) because it always showed CONTINUE and never showed a back arrow. Added `readOnly` param: `readOnly=true` → AppBar with back arrow, no CONTINUE | `mission_brief_screen.dart` |
| Fix 8b — /avya/promise route | Added GoRoute at `/avya/promise` rendering `MissionBriefScreen(readOnly: true)` with fade transition | `app_router.dart` |
| Fix 8c — AVYA section in Profile | Added SectionHeader('AVYA') + single `_buildCard` with 3 rows: AVYA's Promise → `/avya/promise`, icanbefitter.com → browser, @icanbefitter → Instagram native + web fallback | `profile_screen.dart` |
| Fix 4 — REPORTS section fragmented | Three separate `_buildCard` calls (one per row) created triple-gap layout. Consolidated: WeeklyReportCard on top, then one `_buildCard([Predictions, Progress Comparison, Progress Photos])` | `profile_screen.dart` |

## Tests written

8 new test files (one per commit, source-scanning pattern):
- `test/home/home_header_title_test.dart`
- `test/widgets/ward_status_strip_test.dart`
- `test/ai_coach/induction_pledge_test.dart`
- `test/router/mission_brief_routing_test.dart`
- `test/onboarding/mission_brief_readonly_test.dart`
- `test/router/avya_promise_route_test.dart`
- `test/profile/reports_section_consolidated_test.dart`
- Updated `test/profile/profile_screen_layout_test.dart` (ordering assertion inverted)

## Design decisions

- **AVYA section placement:** between SETTINGS and SUBSCRIPTION. These are brand-identity rows (Promise, website, Instagram) — they belong near the bottom as a "closing statement," not at the top with functional settings.
- **AVYA's Promise uses `context.push` not `context.go`:** push preserves the back stack so the user returns to Profile after reading the brief.
- **REPORTS ordering change:** WeeklyReportCard moved to top of REPORTS. Previously: Predictions → WeeklyReportCard → Progress Comparison → Progress Photos (3 separate cards). Now: WeeklyReportCard (full card at top) → single 3-row card. Rationale: the weekly report is the most recurring + high-value item; Predictions is a list-row tap target, not a card.
- **Windows CRLF gotcha:** Test assertion for `readOnly` conditional AppBar initially used `src.contains('readOnly\n')` which failed on Windows (`\r\n`). Fixed to `src.contains('appBar: readOnly')` — platform-independent and semantically correct.

## Pre-existing failures (not caused by this batch)

1. `rank_service_test.dart: LS needs streak 16 + 4 weeks` — gate mirror out of sync
2. `rank_service_test.dart: PO needs streak 60 + 12 weeks + deployment 1` — gate mirror out of sync
3. `rank_service_test.dart: SubLt needs 100 total workouts AND 104 weeks` — gate mirror out of sync
4. `sync_gap_test.dart: DeleteNutritionLogNotifier.delete fires syncNutritionData + pushSnapshot` — regex check stale

All 4 were present before this batch and are deferred to Test #8.
