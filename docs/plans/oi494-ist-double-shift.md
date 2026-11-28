# OI-494: istNow() double shift (food search, coach snapshot)

Branch `oi494-food-search-date`. Blast radius `platform` (computed:
`dart run scripts/blast_radius_from_diff.dart` on the lib files: `account` for the three fix sites; the B-pass round
added a comment-only edit in `lib/core/services/sync/sync_profile.dart`, which is `platform` by path). Tier M under §4.12.6 (touches
`ai_coach` and `core/utils`, and the bug is a recurrence class), so: two plan reviews, a B-pass, a
plan-review record. Execution mode: inline (one session, one worktree). Diagnose doc:
`docs/diagnoses/2026-11-11-ist-now-double-shift-food-search-4f9b2e.md`.

## Problem

`istNow()` is `_wallNow().toUtc().add(5:30)`, a UTC-flagged value holding IST components.
`istDateStr(t)` is `t.toUtc().add(5:30)`. On a UTC-flagged value `toUtc()` does nothing, so
`istDateStr(istNow())` adds 5:30 twice. From 18:30 IST the result is tomorrow, on every host zone
(measured on this VPS under `TZ=Asia/Kolkata` and `TZ=UTC`).

Sites that feed an `istNow()` value into a shifting helper:

| # | file:line (on main, before the fix) | effect |
|---|---|---|
| 1 | `lib/features/nutrition/providers/nutrition_provider.dart:1056` `logMeal(date: istNow())` | food search and the coach food card store an evening meal on tomorrow's `nlog_` key and `date` |
| 2 | `lib/features/ai_coach/services/ai_snapshot_builder.dart:688-693` | coach `this_week_workouts`: window and `todayStr` a day late from 18:30 IST |
| 3 | `lib/features/ai_coach/services/ai_snapshot_builder.dart:754-755` | coach `step_history_7d` starts at tomorrow |

Sites with no shifting helper and no reader, moved anyway after the B-pass (they wrote the IST clock reading with a
`Z` suffix): `profile_write_service.dart:67,95` (`updated_at`, not in the push payload, removed from both sides of the
restore skip) and `stat_snapshot_service.dart:317` (photo `taken_at`, unreachable: no caller passes `photoUrls`).

Live data: one `nutrition_logs` row of 82 has `date` after the IST date of `created_at` (a tester, 23:39 IST).
No heal (pre-launch, testers only).

## Changes

1. `nutrition_provider.dart` `FoodLogNotifier.logFood`: `date: nowWall()`.
2. `ai_snapshot_builder.dart` `_getThisWeekWorkouts`: `wall = nowWall()`, `istWeekday = istDateOf(wall).weekday`,
   `weekStart = wall - (istWeekday - 1) days`, `weekEnd = weekStart + 6 days`, all three strings via `istDateStr`
   once. IST has no DST, so whole-day `Duration` arithmetic on an instant moves the IST date by whole days.
3. `ai_snapshot_builder.dart` `_getStepHistory`: `nowWall().subtract(...)`.
4. `ist_date.dart`: correct the `istNow()` doc comment (it said `isUtc` is false).
4b. (after the B-pass) `profile_write_service.dart` `updated_at` and `stat_snapshot_service.dart` photo `taken_at`:
   `nowWall().toUtc().toIso8601String()`; `workout_repository.dart:641` local `istNow` renamed `istWall`;
   `sync_profile.dart` restore-skip comment no longer names `istNow()`. lib/ then holds no `istNow` token outside
   `ist_date.dart`.
5. Tests:
   - NEW `test/contracts/ist_now_double_shift_behavioral_test.dart`: A (logFood at 18:31, 23:59 and the 18:29 control),
     B (Sunday 22:30 IST week window), B2 (Monday 03:00 IST, IST weekday vs UTC weekday; it is green on main too and
     pins the M4 mutant, a host-zone weekday, not the original bug), C (step history at 22:30),
     E (profile `updated_at` is the real UTC instant, clock pinned with a local DateTime),
     D (no `istNow` token in `lib/` outside `ist_date.dart`: calls, tear-offs, prefixed calls, comments stripped by a
     string-aware scanner; the allowlist is empty), D0 (pins that scanner: a `//` inside a string, nested block
     comments, interpolations, tear-offs).
   - REPOINT `food_log_notifier_to_nutrition_log_items_test.dart` (it required `istNow()`: now requires
     `date: nowWall(),` and bans `date: istNow()`).
   - REPOINT `ai_snapshot_builder_only_test.dart` planned_this_week (its oracle had the same double shift: now
     pins the clock to Sunday 22:30 IST and spells the week).
6. `.claude/skills/debugging/bug-classes.md` §2.2: the UTC-flag fact, the WriteService `date:` shape, 4f9b2e,
   the guard.
7. `docs/sot_registry.yaml`: every `line_range` citing `nutrition_provider.dart` or `ai_snapshot_builder.dart`
   re-anchored from the method's own start and end lines (19 ranges, plus the water `ist_sites` line 409, a blank line above the class, to 412, the `build()` declaration).
   Most were already stale on main; the parity gate checks bounds only, so it had not seen them.

## Not in scope

- Changing `istNow()` itself to return a local value: every caller that reads its components would shift
  (value-semantics change across the app). The guard (test D) stops new callers instead.
- The other `logMeal` callers (`barcode_scan_sheet.dart:173`, `scan_meal_section.dart:443`,
  `search_mode_body.dart:303`, `nutrition_provider.dart:970`, `simulation_service.dart:562`) pass `DateTime.now()`
  or a sim date: correct. `tool_dispatcher.dart:1713` passes `DateTime.tryParse('<YYYY-MM-DD>')`, which is LOCAL
  midnight: on a device east of IST (e.g. UTC+9) that is the previous IST day. Different class (date string parsed
  as local midnight), coach path only, so it is added to the OI-493 coach-vs-screen survey (next landing, same
  board) rather than widened into this fix. It is written into the OI-493 entry in `docs/audit/open_issues.md` in this
  commit, so it has a tracked home.
- OI-493 (coach vs screen meal parity) is the next landing.

## Verification

Both zones green for the new file; mutants M1-M4 and MD1-MD2 red (table in the diagnose doc); whole-project
`flutter analyze --no-fatal-infos`, full `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden`, and the
pre-commit gate loop before each review round.
