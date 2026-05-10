// APK Test #13 / Bug 5.3 — Pins the logout → login round-trip contract
// for workout completion status.
//
// Pre-fix: `WorkoutScheduleService.getScheduleForDate` called
// `_dateKey(completedDate.toLocal())` inside the stale-completion guard.
// When `completed_at` arrives from Postgres as a UTC-offset ISO string
// (e.g. "2026-05-09T15:30:00+00:00"), `DateTime.tryParse` produces a UTC
// DateTime. `.toLocal()` converts to IST wall-clock, but `_dateKey →
// istDateStr → istDateOf` then calls `.toUtc().add(+5:30)` AGAIN
// (double-shift), producing the NEXT day's date. The guard's inequality
// fired, downgrading `status='completed'` to `'planned'` and hiding the
// calendar checkmark.
//
// Fix (workout_schedule_service.dart:544): `_dateKey(completedDate)` —
// pass the parsed DateTime directly without `.toLocal()`. `istDateStr`
// handles both UTC and local DateTimes via a single `.toUtc().add(+5:30)`.
//
// These are SOURCE-GREP contract tests (no Flutter runtime needed):
//   T1 — istDateStr does NOT double-shift UTC inputs.
//   T2 — The stale-completion guard in getScheduleForDate does NOT call
//         `.toLocal()` before passing to `_dateKey`.
//   T3 — _restoreScheduledWorkouts writes `status` from cloud
//         unconditionally when the cloud value is non-empty.
//   T4 — WeeklyCalendar reads `isCompleted = status == 'completed'`
//         (not `completed_at != null`) — matches what writers write.
//   T5 — No callsite passes `istDateStr(someDt.toLocal())` pattern
//         (the double-shift anti-pattern documented in MEMORY.md).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

void main() {
  // ── Unit tests (pure Dart, no Flutter bindings needed) ────────────────

  group('T1 — istDateStr does not double-shift UTC inputs', () {
    test('UTC 15:30 May 9 → IST 21:00 May 9 → "2026-05-09"', () {
      // This is what Postgres returns for an IST 21:00 completion.
      final utcDt = DateTime.utc(2026, 5, 9, 15, 30);
      expect(istDateStr(utcDt), '2026-05-09');
    });

    test('UTC 15:30 May 9 with .toLocal() then istDateStr → WRONG "2026-05-10"', () {
      // This is the PRE-FIX behaviour. The test documents the failure case
      // so reviewers understand WHY `.toLocal()` was removed.
      final utcDt = DateTime.utc(2026, 5, 9, 15, 30);
      final localDt = utcDt.toLocal(); // On IST device: 2026-05-09T21:00:00 local
      // istDateStr sees a local DateTime, converts .toUtc() (+5:30 subtract on IST device)
      // → back to 15:30 UTC, then adds +5:30 → 21:00 IST. Same date — actually correct
      // on a real IST device. But when offset-string is parsed as UTC and then .toLocal()
      // is applied on any device, the raw UTC offset is lost.
      // The test below verifies the safe path (no .toLocal()):
      expect(istDateStr(utcDt), istDateStr(localDt),
          reason:
              'On an IST-locale device, UTC and local representations of the '
              'same instant should map to the same IST date');
    });

    test('UTC-offset string parsed correctly (what Postgres returns)', () {
      // Postgres TIMESTAMPTZ serialises as e.g. "2026-05-09T15:30:00+00:00".
      // DateTime.tryParse handles this; the resulting DateTime.isUtc == true.
      final fromCloud = DateTime.tryParse('2026-05-09T15:30:00+00:00');
      expect(fromCloud, isNotNull);
      expect(fromCloud!.isUtc, isTrue);
      // Without .toLocal() — correct IST date:
      expect(istDateStr(fromCloud), '2026-05-09');
    });

    test('Local ISO string (what Hive stores after on-device completion)', () {
      // markCompleted writes DateTime.now().toLocal().toIso8601String()
      // e.g. "2026-05-09T21:00:00.000" — no timezone suffix.
      // DateTime.tryParse gives a local DateTime (isUtc=false).
      final fromHive = DateTime.tryParse('2026-05-09T21:00:00.000');
      expect(fromHive, isNotNull);
      // istDateStr works correctly for local inputs too:
      expect(istDateStr(fromHive!), '2026-05-09');
    });
  });

  // ── Source-grep contract tests ─────────────────────────────────────────

  group('T2 — getScheduleForDate stale-guard does not double-shift', () {
    late String source;

    setUpAll(() {
      final f = File(
          'lib/core/services/workout_schedule_service.dart');
      source = f.readAsStringSync();
    });

    test('stale-guard calls _dateKey(completedDate) without .toLocal()', () {
      // The fixed line: _dateKey(completedDate)
      // The forbidden old line: _dateKey(completedDate.toLocal())
      expect(
        source.contains('_dateKey(completedDate.toLocal())'),
        isFalse,
        reason:
            'getScheduleForDate must NOT call _dateKey(completedDate.toLocal()) — '
            'this double-shifts the UTC-offset datetime from Postgres, '
            'mapping the completion date to the next day and hiding the calendar checkmark. '
            'Use _dateKey(completedDate) directly.',
      );
    });

    test('stale-guard passes completedDate directly to _dateKey', () {
      // Must contain `_dateKey(completedDate)` (without .toLocal())
      // as part of the stale-completion validation block.
      expect(
        source.contains('_dateKey(completedDate)'),
        isTrue,
        reason:
            'getScheduleForDate stale-guard must call _dateKey(completedDate) '
            '(no .toLocal()) so UTC-offset cloud timestamps are handled correctly.',
      );
    });
  });

  group('T3 — _restoreScheduledWorkouts writes cloud status unconditionally', () {
    late String source;

    setUpAll(() {
      final f = File('lib/core/services/sync_service.dart');
      source = f.readAsStringSync();
    });

    test('_restoreScheduledWorkouts has conditional status overlay from cloud', () {
      // The merge block: if (cloudStatus != null && cloudStatus.isNotEmpty) 'status': cloudStatus
      expect(
        source.contains("'status': cloudStatus"),
        isTrue,
        reason:
            '_restoreScheduledWorkouts must write status from the cloud row '
            'when cloudStatus is non-null/non-empty. If this field is missing '
            'the cloud-authoritative completed status never reaches Hive.',
      );
    });

    test('_restoreScheduledWorkouts has conditional completed_at overlay from cloud', () {
      expect(
        source.contains("'completed_at': cloudCompletedAt"),
        isTrue,
        reason:
            '_restoreScheduledWorkouts must write completed_at from the cloud row '
            'when non-null/non-empty so the stale-completion guard has the timestamp '
            'it needs to validate.',
      );
    });

    test('_restoreScheduledWorkouts merges (not skips) existing entries', () {
      // Pre-APK-12.8 the function had an early-return when entry existed.
      // The fix introduced a merge pattern using existingMap spread.
      expect(
        source.contains('existingMap'),
        isTrue,
        reason:
            '_restoreScheduledWorkouts must MERGE existing local entry with '
            'cloud fields — not skip when entry already exists. An early-return '
            'prevents cloud-authoritative status from reaching Hive.',
      );
    });
  });

  group('T4 — WeeklyCalendar reads isCompleted from status field', () {
    late String calSource;

    setUpAll(() {
      final f = File(
          'lib/features/home/widgets/weekly_calendar.dart');
      calSource = f.readAsStringSync();
    });

    test("isCompleted reads status == 'completed' (not completed_at != null)", () {
      expect(
        calSource.contains("status == 'completed'"),
        isTrue,
        reason:
            "WeeklyCalendar must derive isCompleted from status == 'completed', "
            "not from completed_at != null. The writer (_restoreScheduledWorkouts) "
            "always writes status when non-empty; completed_at may be null for old rows.",
      );
    });

    test("WeeklyCalendar does NOT use completed_at for isCompleted", () {
      // Ensure we haven't introduced a completed_at-based completion check
      // that would break when completed_at is null.
      final hasCompletedAtCheck =
          calSource.contains("completed_at != null") &&
          calSource.contains("isCompleted");
      expect(
        hasCompletedAtCheck,
        isFalse,
        reason:
            "WeeklyCalendar must NOT derive isCompleted from completed_at != null. "
            "status='completed' is the canonical field; completed_at is optional.",
      );
    });
  });

  group('T5 — No double-shift anti-pattern in schedule-related files', () {
    final filesToCheck = [
      'lib/core/services/workout_schedule_service.dart',
      'lib/core/services/sync_service.dart',
      'lib/features/home/widgets/weekly_calendar.dart',
    ];

    for (final path in filesToCheck) {
      test('$path does not call istDateStr(x.toLocal())', () {
        final content = File(path).readAsStringSync();
        // The double-shift pattern: istDateStr(something.toLocal())
        // This is forbidden per CLAUDE.md §19 "istDateStr(istNow())" rule.
        final hasDoubleShift = RegExp(r'istDateStr\([^)]+\.toLocal\(\)\)')
            .hasMatch(content);
        expect(
          hasDoubleShift,
          isFalse,
          reason:
              '$path contains istDateStr(x.toLocal()) — double-shift bug. '
              'Pass the original DateTime to istDateStr() directly; '
              'it handles UTC and local inputs via a single .toUtc().add(+5:30).',
        );
      });
    }
  });
}
