import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #14 / Bug A — stale-completion guard discipline contract.
///
/// `WorkoutScheduleService.getScheduleForDate` (lib/core/services/
/// workout_schedule_service.dart:530-575) used to downgrade any
/// status='completed' Hive row whose `completed_at` IST date != the
/// schedule_date. This wrongly killed:
///   - retroactive completions (user logs Tuesday's workout on Sunday)
///   - late-night IST-midnight crossings (cloud completed_at lands one
///     IST date later than schedule_date)
///
/// Bulk retroactive completions in cloud carrying completed_at='2026-05-07
/// 21:19Z' (= 02:49 IST May 8) for schedule_dates May 5/6/7 caused all
/// three calendar checkmarks to vanish on the founder's account.
///
/// Fixed by relaxing the guard to fire ONLY on impossible-past
/// completions (completed_at < schedule_date — real corruption). This
/// contract pins the predicate so future edits don't slip back to the
/// equality check.
///
/// closes-diagnose: 2026-05-10-stale-guard-overeager
void main() {
  late String schedSvcSrc;

  setUpAll(() {
    final f = File('lib/core/services/workout_schedule_service.dart');
    expect(f.existsSync(), isTrue,
        reason: 'workout_schedule_service.dart must exist');
    schedSvcSrc = f.readAsStringSync();
  });

  group('stale-completion guard predicate', () {
    test('uses compareTo(...) < 0 (impossible-past), NOT != equality', () {
      // The fix: ONLY downgrade when completed_at is strictly before
      // schedule_date (impossible without clock skew or test-data corruption).
      expect(
        schedSvcSrc.contains('completedDateStr.compareTo(requestedDateStr) < 0'),
        isTrue,
        reason:
            'getScheduleForDate must downgrade only on impossible-past '
            'completions (completed_at < schedule_date). The pre-Test-#14 '
            'equality check (completedDateStr != requestedDateStr) wrongly '
            'flagged retroactive logs and late-night IST-midnight crossings, '
            'hiding their calendar checkmarks. closes-diagnose: '
            '2026-05-10-stale-guard-overeager',
      );
    });

    test('forbidden: equality-mismatch downgrade pattern absent', () {
      // Pre-Test-#14 line read:
      //   if (requestedDateStr != completedDateStr) { ... downgrade ... }
      // It must not return.
      expect(
        schedSvcSrc.contains(
            'if (requestedDateStr != completedDateStr)'),
        isFalse,
        reason:
            'forbidden equality-mismatch downgrade in getScheduleForDate: '
            'retroactive + late-night completions would be downgraded again. '
            'Use compareTo(...) < 0 instead.',
      );
    });

    test('guard preserves the existing UTC->IST single-shift fix', () {
      // Bug 5.3 (Test #13) removed `.toLocal()` before `_dateKey`. We must
      // not regress on that — istDateStr handles both UTC and naive-local
      // DateTimes correctly via a single .toUtc().add(+5:30) shift.
      expect(
        schedSvcSrc.contains('_dateKey(completedDate.toLocal())'),
        isFalse,
        reason:
            'forbidden double-shift: _dateKey(completedDate.toLocal()) maps '
            'a UTC DateTime to IST then to UTC then adds +5:30 again. Use '
            '_dateKey(completedDate) directly.',
      );
      expect(
        schedSvcSrc.contains('_dateKey(completedDate)'),
        isTrue,
        reason: 'guard must call _dateKey(completedDate) (single IST shift)',
      );
    });

    test('downgrade returns a defensive copy, never mutates Hive in-place', () {
      // The historical bug: an earlier version wrote `safe['status'] =
      // 'planned'` back to Hive via `box.put`, masking subsequent restore
      // pulls. The guard MUST return a copy without persisting.
      final guardWindow = _extractGuardWindow(schedSvcSrc);
      // Match `Map<String, dynamic>.from(` followed by any identifier — the
      // existing code uses `from(map)` but a future refactor might rename
      // the local without breaking the contract. The check is "does the
      // downgrade construct a fresh Map".
      final cloneRegex =
          RegExp(r'Map<String,\s*dynamic>\.from\(\s*\w+\s*\)');
      expect(cloneRegex.hasMatch(guardWindow), isTrue,
          reason:
              'downgrade must clone the map (Map<String, dynamic>.from(...)) '
              'inside the guard window; the guard returns a fresh map, never '
              'mutates the original Hive value.');
      expect(
          guardWindow.contains('workoutBox.put') ||
              guardWindow.contains('_hive.workoutBox.put'),
          isFalse,
          reason:
              'guard must NOT write back to Hive — it returns a transient '
              'planned-shaped view; restore is the only path that should '
              'mutate the row.');
    });
  });
}

/// Extracts the ~50-line window around the stale-completion guard so the
/// last two source-grep tests scope precisely to that block. Uses the
/// "Guard against stale completion" comment which is unique to the
/// `getScheduleForDate` guard (line 536), distinguishing it from the
/// 3 other `if (map['status'] == 'completed')` occurrences in the file.
String _extractGuardWindow(String src) {
  const marker = '// Guard against stale completion';
  final start = src.indexOf(marker);
  if (start < 0) {
    fail('Could not locate stale-completion guard marker in source. '
        'Did the predicate get refactored? Update this test.');
  }
  // Window must be large enough to encompass the full guard block, including
  // the new comment (Test #14) before the predicate plus the downgrade body.
  // Empirically ~3500 chars covers the block with comfortable margin. Without
  // this margin the defensive-copy check would scan the comment-only prefix.
  final end = (start + 3500).clamp(0, src.length);
  return src.substring(start, end);
}
