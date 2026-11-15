---
reviewed_at: 2026-11-11T11:40:00+05:30
staged_against: 71f07c62 (branch exlog-type-filter-readers, staged diff, 13 files)
blast_radius: account
reviewer: claude-sonnet-via-skill (one fresh context-blind seat)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 2
verdict: accepted
verdict_note: no P0 or P1; one P2 fixed with a mutation-proven test, one P2 closed with evidence.
---

# Code Review: exlog type-filter readers (Part P, diagnose 81c4e2)

Scope: three Hive readers filtered `exlog_*` rows on `type: 'exercise_log'`, which only the cloud restore writes. They are the FINISH PR scan, `BadgeService` PR count and the Profile lifetime volume. They now walk rows through `WorkoutReadService.exlogRows`. A PR beats the best of strictly earlier IST dates, and the badge reads no stored `is_pr`.

The seat got the staged diff, the 8 lenses, an exhaustive command list (read-only git, file reads, the named test files, `dart analyze` per staged file, mutation of the 4 staged `lib/` files under a backup / sha256 restore protocol) and a ban on scripts, the `supabase` CLI, network tools and any database statement.

Before dispatch, the gate loop was green:
- whole-project `flutter analyze --no-fatal-infos`: 0 warnings;
- full Flutter suite: 13,951 passed;
- pre-commit loop: green.

Step 0 and step 0b were clean (no `MM`/`AM`; HEAD...origin/main = 0 0).

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** test/contracts/exlog_type_field_read_ban_test.dart:20-23 (`_typeComparison`)
- **claim:** The ban matched only `['type'] ==/!= 'exercise_log'` in either operand order. It missed the pre-fix lifetime-volume spelling, `final type = v['type']?.toString(); if (type != 'exercise_log') continue;`, which is one of the three readers this batch fixed. It also missed `?.toString() ==` and a named constant.
- **verification:** `git diff --cached -- lib/features/train/repositories/workout_repository.dart` (the removed lines)
- **suggested-fix:** Ban the literal outside the writer, and add scanner fixtures for the other spellings.
- **status:** accepted, fixed. The test now bans the quoted literal `'exercise_log'` (exact word, either quote) anywhere in `lib/` with comments stripped. A reader cannot filter on the value without it.
  - The one exception is the restore writer's map entry in `sync_workout.dart`, and that file must hold exactly one hit. A second hit, or a Dart 3 map pattern, is an offender.
  - Op types such as `'upsert_exercise_log'` and the `exercise_log_index_` prefix are different words and are not matched.
  - Scanner fixtures cover the pre-fix spelling, `?.toString() ==`, both operand orders, a `case`, a constant, the writer entry under a Windows path, a duplicate entry and a map pattern.
  - Mutants, each restored by sha256:
    - B-M1, the pre-fix spelling re-added in the lifetime loop: 3 pass / 1 fail.
    - B-M2, a map-pattern reader added to `sync_workout.dart`: 3 pass / 1 fail.
    - B-M3, the old comparison regex restored: 1 pass / 3 fail.

## Finding 2 — P2 — asserted_fixture_value / blast_radius_mismatch
- **file:line:** lib/core/services/badge_service.dart:114-122 (`countBeatenPrs`), `checkAll` at :133-136
- **claim:** The recomputed PR count is not monotonic. A back-filled heavier earlier row turns a PR into a non-PR. The seat did not trace whether a badge can relock.
- **verification:** `grep -n "tryUnlock\|_badgesKey" lib/core/services/badge_service.dart`
- **status:** no_change_needed. Unlocks are one-way:
  - `tryUnlock` (`badge_service.dart:42-47`) only adds a key that is absent.
  - The only writer of `unlockedBadges` is `badge_service.dart:65`, which writes that superset.
  - `totalPrs` is a transient input to `checkAll`. Nothing in `lib/` stores or shows it; `ai_snapshot_builder.dart:1635` has its own local count.
  - The old stored-`is_pr` count was not monotonic either: the rescan at `workout_write_service.dart:1441` rewrites `is_pr`, including to false.

## Clean lenses (seat summary)
- **writer_reader_drift:**
  - Every `exlog_` writer goes through `exlogKey`: `logExercise`, the restore (`sync_workout.dart:1082`, the only `type` stamp), `ExlogKeyMigrator`, `moveExerciseLogs`, and the coach path through `logExercise`.
  - The index keys (`exercise_log_index_`) and `pending_exlog_deletes` do not start with `exlog_`.
  - Restored and device copies share one deterministic key, so lifetime volume cannot double-count.
- **function_exception_swallow, unawaited_no_error_sink, secrets_in_tree:** no hits in scope.
- **blast_radius_mismatch:** client read paths only; no writer or schema change.
- **missing_input:**
  - Rows with no date or no name are skipped.
  - A 0 kg earlier max never yields a PR.
  - The FINISH skip date is the same `resolveSessionDate(now)` that the write uses, so the two agree across IST midnight.
- **asserted_fixture_value:** fixtures use realistic shapes: device rows without `type`, restore rows with it, `sets[]`, bodyweight 12/10/8, and trailing-space names.

## Mutants run by the seat
| file | edit | test | red |
|---|---|---|---|
| badge_service.dart | `compareTo(r.key) < 0` to `<= 0` | exlog_type_filter_reader_drift_behavioral_test.dart | 5 |
| train_provider.dart | FINISH session-date skip compares to `'9999-01-01'` | same | 2 |
| workout_repository.dart | `if (v['type'] != 'exercise_log') continue;` re-added | behavioral + ban test | 1 + 1 |

Every file was restored by sha256, and `git status --porcelain` showed no second-column letter.

## Founder triage notes
Coordinator triage 2026-11-11 (account tier): F1 fixed, F2 no change (evidence above).

## Tuning entry
- **2026-11-11** - blast-radius account - 2 findings; 0 false_alarm; tuning: none. The seat broke a source-grep ban by reading the code the batch had just removed: the fixed reader's own old spelling is the first mutant any ban must catch. Ban the token a reader needs, not one spelling of the comparison (the lens 6 "source grep, assume defeatable" rule).
