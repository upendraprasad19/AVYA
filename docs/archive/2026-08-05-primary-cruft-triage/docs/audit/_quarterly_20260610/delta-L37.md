# Quarterly audit 2026-06-10 — Lens L37 (null/empty-shape readers + silent defaults) — DELTA scope

**Lens:** L37 (LENS_REGISTRY.md:94) — "Empty-state / null-shape readers": every consumer of a
writer's output must handle `empty | malformed | missing-key | wrong-type`. Applied operationally
as: a reader that silently coerces a missing/null field to a default that LOOKS valid
(0 / empty / false), masking a real data gap.

**Scope:** `git diff --name-only 969c117..HEAD` ∪ `git show --name-only a767725`. Focused readers:
reports_screen.dart (c2e8b4), profile_provider/profile_content (b1f3a7), train/screen.dart (b6e1c3),
workout_schedule_read_service.dart (a1d4f9), week_selector, additive-restore skip paths.

---

## Findings

### F-L37-1 — INFO / FALSE_ALARM — reports "This Week" count reads 0 when no workout_log rows exist
- **file:line:** `lib/features/profile/screens/reports_screen.dart:376-377` reading
  `WorkoutRepository.getWeeklyWorkoutCounts()` (`workout_repository.dart:755-781`).
- **verbatim:** `final weekCounts = WorkoutRepository.instance.getWeeklyWorkoutCounts();`
  `final thisWeekWorkouts = weekCounts.isNotEmpty ? weekCounts.first : 0;`
- **claim:** The L37 worry would be that `weekCounts.first == 0` masks a real data gap (e.g. cloud
  had workouts but local is empty). It does NOT: the writer is per-completion `workout_log` rows
  (`type == 'workout_log'`), counted within `daysAgo < 7`. A 0 here is the *truthful* value
  ("no workouts logged this week"), not a coerced default over absent data. This is precisely the
  c2e8b4 fix — it replaced the *lifetime* `total_workouts_done` (which DID overstate) with this
  per-week count. The empty-list guard returns 0 only when the box has zero workout_log rows.
- **verification:** Read `workout_repository.dart:755-781` (writer), `reports_screen.dart:330-377`
  (reader + `hasAnyData` empty-state gate at :330). Restore of cloud workout_log is additive
  (`sync_workout.dart:605`), so cloud data is materialised locally before this reader runs.
- **verdict:** FALSE_ALARM. (Minor non-L37 note: `getWeeklyWorkoutCounts` buckets via
  `DateTime.now()` device-local, not IST — a date-key lens concern, out of L37 scope.)

### F-L37-2 — INFO / FALSE_ALARM — isPhaseExpired no longer reads stale plan_end as "expired"
- **file:line:** `lib/core/services/workout_schedule_read_service.dart:601-628`.
- **verbatim:** `if (!todayD.isAfter(endD)) return false;` ... then
  `isPhaseExpiredFrom(today, stored, _scheduledWorkoutDays())`.
- **claim:** This is the FIX for the L37-shaped bug a1d4f9: previously a stale/null-lagging
  `plan_end_date` (restored from a cloud `plan_json` snapshot that lagged the live
  `scheduled_workouts` table) was read as "expired" — a plausible-but-wrong state masking that
  future workout days existed. Post-fix the reader cross-checks the materialised schedule
  (`_scheduledWorkoutDays()`) and returns expired only when BOTH the window says so AND no day is
  today-or-later. `getPlanEndDate()` null → `return false` (not-expired), which is the safe default.
- **verification:** Read :601-646. Pure decision `isPhaseExpiredFrom` (:617) covers null storedEnd,
  empty schedule iterable. Behavioral test `test/contracts/plan_expiry_respects_schedule_test.dart`
  present in scope.
- **verdict:** FALSE_ALARM (fix, not defect).

### F-L37-3 — INFO / FALSE_ALARM — additive-restore skip cannot show empty over cloud data
- **file:line:** `sync_workout.dart:605` (wlog), `sync_nutrition.dart:535` (saved meal),
  `sync_health.dart:300/331/369/405`.
- **verbatim:** `if (_hive.workoutBox.get(logId) != null) continue;`
- **claim:** The prompt's specific L37 question — "does the additive-restore skip leave a reader
  showing empty when cloud actually had data?" — is NO. The skip fires ONLY when a local row already
  exists (`get(key) != null`); when local is absent the cloud row IS written. So a reader is never
  left empty for data the cloud held. The local-wins choice (ADR-0014) can leave a STALE-but-present
  local row over a newer cloud row, but that is an intentional offline-first trade-off, not an
  empty/null coercion. phaseForDate (:793-810) catches Hive-not-ready and records a non-fatal before
  the `return 1` fallback, so the wrong-phase default stays observable (not silent).
- **verification:** Read `sync_workout.dart:585-624`, `workout_schedule_read_service.dart:793-833`,
  CLAUDE.md restore-additive pitfall row. Tests `restore_local_wins_additive_test.dart`,
  `restore_orphan_completion_test.dart` in scope.
- **verdict:** FALSE_ALARM.

### F-L37-4 — INFO / FALSE_ALARM — profile image URL read returns null (not "" default) on absent
- **file:line:** `lib/features/profile/utils/profile_image_url.dart:24-27`.
- **verbatim:** `if (storedUrl == null || storedUrl.isEmpty) return null;`
- **claim:** Read path returns null on missing/empty (the avatar widget falls back to a placeholder),
  rather than coercing to a broken URL string. No silent plausible-but-wrong default. The b1f3a7 fix
  removed the per-build cache-buster; versioning is now stamped at write time. No L37 exposure.
- **verification:** Read :19-40 + reader callsites `profile_content.dart:91-93`.
- **verdict:** FALSE_ALARM.

---

## Summary

**0 REAL L37 findings in the delta.** The focused readers (reports this-week count c2e8b4, phase-
expiry a1d4f9, train expired-state b6e1c3, profile image b1f3a7, additive-restore skip paths) are
the FIXES for prior null/stale-default masking bugs and each now either (a) reads a truthful 0/empty
for genuinely-absent data, (b) cross-checks a second source before defaulting, or (c) returns null /
records a non-fatal rather than coercing silently. No reader computes a count/label from a field that
defaults to a plausible-but-wrong value, and the additive-restore skip never leaves a reader empty
over cloud-held data.
