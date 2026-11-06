# Plan F smoke test — Onboarding/Calendar + Starting Stats

**Branch:** `feat/apk-test-6-batch` (HEAD post-Plan F).
**Tasks completed:** F-1 through F-16.

## On-device verification (success criteria from spec §12.2)

### C17 — Plan screen days_per_week (closes #4)

1. Onboard fresh, select **6 days/week** in Details step.
2. On Plan screen: phase descriptions show "6 days/week" (not hardcoded "4 days/week").

### C18 — Onboarding weight on home graph (closes #5)

1. Onboard with current weight 76.9 kg.
2. On Home tab: weight sparkline displays the onboarding weight as the first data point.

### C19 — Streak freeze chip rendered once (closes #9)

1. On Home / Train / Nutrition / Coach tabs, verify each tab status strip shows exactly **ONE** 🔥 streak chip + **ONE** ❄ freeze chip — not duplicated.

### C20 — Promotion-day celebration (closes #6 — starting stats system)

1. Synthetic trigger (debug build): force complete 7 consecutive workouts after 1 week elapsed → SD2 → SD1 promotion.
2. Verify overlay appears:
   - "PROMOTION DAY" header in mono caps gold
   - Insignia placeholder (text-ringed ribbon — Plan D will replace with proper Indian Navy CustomPaint)
   - Ceremonial line: "By order of the Captain — you are promoted to Seaman 1st Class."
   - Side-by-side stats: weight then/now if both snapshots have data
   - "Share this moment" button
   - "Tap anywhere to dismiss" hint
3. Tap **Share this moment** → native share sheet opens with text "I just ranked up to Seaman 1st Class on AVYA! 🎖️"
4. Tap background → overlay dismisses → user returns to previous screen.
5. Verify cloud `user_stat_snapshots` table has new rows:
   - `source='onboarding'` (from F-9 wire-in)
   - `source='promotion'` for SD1 (from F-10 wire-in)

### C21 — Phase mid-week join handling (closes #7)

1. Sign up fresh on a Wednesday (or simulate via clock).
2. Verify calendar week renders Mon-Sun.
3. Mon + Tue (pre-onboarding) days have status='rest' with reason='pre_onboarding' — visually rendered as "Joined later" light grey chips, NOT red "missed".
4. Pending workouts count = 4 (Wed/Thu/Fri/Sat) for 6/week plan — Sun is normal rest.
5. `user_progress.phase_started_at` = onboarding date IST (NOT backdated to Monday).
6. Promotion gate math counts from `phase_started_at`, not from week start.

## Test results (CI / local)

| Suite | Pass | Skip | Fail |
|---|---|---|---|
| `test/utils/ist_date_test.dart` | 11 | 0 | 0 |
| `test/services/stat_snapshot_service_test.dart` | 6 | 0 | 0 |
| `test/promotion_celebration/overlay_renders_test.dart` | 3 | 0 | 0 |
| Total Plan F new tests | **20** | 0 | 0 |

## Plan F completion summary

| Task | Status |
|---|---|
| F-1 Plan screen days_per_week fix | ✅ |
| F-2 Onboarding weight seed | ✅ |
| F-3 Streak freeze duplicate dedup | ✅ |
| F-4 IST date helpers | ✅ (11 tests) |
| F-5 Phase mid-week join handling | ✅ |
| F-6 Calendar pre-onboarding rendering | ✅ |
| F-7 Migration 044 user_stat_snapshots | ✅ (applied to prod `dedsavbjuwgarrhphgnl`) |
| F-8 StatSnapshotService | ✅ (6 tests) |
| F-9 Wire snapshotOnboarding | ✅ |
| F-10 Wire snapshotOnPromotion | ✅ |
| F-11 ProgressComparisonScreen | ✅ |
| F-12 REPORTS section row | ✅ (final ordering pending Plan D D-10) |
| F-13 PromotionCelebrationScreen | ✅ (placeholder insignia; Plan D D-1 swap) |
| F-14 Share image generation | ⚠ MVP text-only share (image gen deferred to Test #7) |
| F-15 Promotion overlay tests | ✅ (3 tests) |
| F-16 This smoke doc | ✅ |

## Out-of-scope deferrals (Test #7)

- F-14 image generation: currently text-only share via `share_plus`. Test #7 enhancement: capture overlay as PNG via RepaintBoundary or `screenshot` package; share image with QR code + branding.
- F-13 placeholder insignia: replaced when Plan D D-1's WardRankInsignia CustomPaint lands in this same batch.
- StatSnapshotService `_avg7d` returns null: Test #7 enhancement to compute 7-day rolling averages from nutrition_logs + health_logs.
- Manual snapshot UI: measurements text fields and photo upload exist as parameters but no input sheet shipped this batch.

## Files added / modified

**Created:**
- `lib/core/utils/ist_date.dart`
- `lib/core/services/stat_snapshot_service.dart`
- `lib/features/profile/screens/progress_comparison_screen.dart`
- `lib/features/profile/screens/promotion_celebration_screen.dart`
- `supabase/migrations/044_user_stat_snapshots.sql`
- `test/utils/ist_date_test.dart`
- `test/services/stat_snapshot_service_test.dart`
- `test/promotion_celebration/overlay_renders_test.dart`

**Modified:**
- `lib/features/onboarding/screens/plan_screen.dart` (F-1)
- `lib/features/onboarding/providers/onboarding_provider.dart` (F-2 + F-9)
- `lib/shared/widgets/wardroom/ward_status_strip.dart` (F-3)
- `lib/core/services/workout_schedule_service.dart` (F-5)
- `lib/features/home/widgets/weekly_calendar.dart` (F-6)
- `lib/core/services/rank_service.dart` (F-10)
- `lib/features/profile/screens/profile_screen.dart` (F-12)
- `lib/core/router/app_router.dart` (F-11 route)

Plan F architecturally complete. Ready for Plan B → Plan D → Plan E next, then APK build.
