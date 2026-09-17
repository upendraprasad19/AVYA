// C2 review-fixes (ai-coach-ux-tool-integrity, diagnose e8f4a3) — terminal
// 'moved'/'dropped' schedule rows must be INVISIBLE to the display read path.
//
// THE BUG (post-C2): rescheduleWeek correctly WRITES terminal rows, but the
// READER side was only half-wired — WorkoutScheduleReadService
// .getScheduleForDate (the read path behind todayWorkoutProvider, the Home
// week strip, the Train week renderer, hold rows and workoutDayForDate's
// START gate) returned ANY status, so a 'moved' row for TODAY rendered a live
// Start CTA on the Home Today card and a 'dropped' row in the current week
// rendered as a planned workout.
//
// THE FIX: getScheduleForDate filters WorkoutRepository.isInvisibleToStreak
// statuses ({paused, moved, dropped}) — terminal rows read as ABSENT through
// the display path. Audit/restore callers read RAW via
// getScheduleRowForDate. The streak walk already filtered these (C1).
//
// Each test below FAILS against the pre-fix behavior (getScheduleForDate
// returned the terminal row verbatim).
//
// MUTATION PROOF: comment out the isInvisibleToStreak filter inside
// getScheduleForDate → the three filter tests in group
// 'display read path hides terminal rows' redden. Recorded in
// docs/diagnoses/2026-09-18-reschedule-terminal-rows-e8f4a3.md.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart'
    show authStateProvider;
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart'
    show workoutDayForDate;

import '../helpers/hive_test_setup.dart';

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await tearDownHiveForTests(tempDir);
  });

  final today = nowWall();
  final todayStr = istDateStr(today);

  Map? rawRow(String dateStr) =>
      HiveService.instance.workoutBox.get('schedule_$dateStr') as Map?;

  group('display read path hides terminal rows (C2 review, e8f4a3)', () {
    test(
      'moved row for TODAY reads ABSENT via getScheduleForDate '
      '(today-card read path) — raw read still sees it',
      () async {
        await HiveService.instance.workoutBox.put('schedule_$todayStr', {
          'date': todayStr,
          'week': 1,
          'day_of_week': today.weekday - 1,
          'workout_name': 'Push A',
          'status': 'moved',
          'type': 'custom_template',
          'moved_to': istDateStr(today.add(const Duration(days: 1))),
          'moved_via': 'ai_coach',
          'moved_at': DateTime.now().toIso8601String(),
          'exercises': [
            {'exercise_name': 'Bench Press'},
          ],
        });

        // The read path behind todayWorkoutProvider / the Home Today card.
        final viaReader =
            WorkoutScheduleReadService.instance.getScheduleForDate(today);
        expect(viaReader, isNull,
            reason: 'a terminal moved row must read as ABSENT through '
                'getScheduleForDate — pre-fix it fell through to the '
                'planned-workout render with a live Start CTA.');

        // The START gate (train_provider.workoutDayForDate) — the workout
        // that STARTS must be the workout that was DISPLAYED.
        expect(workoutDayForDate(today), isNull,
            reason: 'no START CTA may exist for a day whose workout moved '
                'elsewhere.');

        // Audit callers read RAW — the terminal row itself is untouched.
        final raw = WorkoutScheduleReadService.instance
            .getScheduleRowForDate(today);
        expect(raw, isNotNull);
        expect(raw!['status'], 'moved');
        expect(raw['moved_to'],
            istDateStr(today.add(const Duration(days: 1))));
      },
    );

    test(
      'dropped row in the CURRENT week renders NOWHERE as a live workout '
      '(week strip + calendar week read path)',
      () async {
        final monday = DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: (today.weekday - 1) % 7));
        // Drop the row on a mid-week day so it is unambiguous.
        final droppedDate = monday.add(const Duration(days: 2));
        final droppedStr = istDateStr(droppedDate);
        await HiveService.instance.workoutBox.put('schedule_$droppedStr', {
          'date': droppedStr,
          'week': 1,
          'day_of_week': 2,
          'workout_name': 'Legs B',
          'status': 'dropped',
          'type': 'custom_template',
          'dropped_via': 'ai_coach',
          'dropped_at': DateTime.now().toIso8601String(),
          'exercises': [
            {'exercise_name': 'Squat'},
          ],
        });

        // Per-day read — the CalendarWeekNotifier / WeeklyCalendar /
        // swap-sheet read path (all call getScheduleForDate per day).
        expect(
            WorkoutScheduleReadService.instance
                .getScheduleForDate(droppedDate),
            isNull,
            reason: 'a dropped row must read as ABSENT per-day — the home '
                'week strip and train week renderer iterate exactly this '
                'call.');

        // getCurrentCalendarWeek — the week-strip snapshot read path. The
        // dropped day must come back as the no-plan placeholder, not a live
        // workout.
        final week =
            WorkoutScheduleReadService.instance.getCurrentCalendarWeek();
        final dayEntry =
            week.firstWhere((m) => m['date'] == droppedStr);
        expect(dayEntry['type'], 'none',
            reason: 'a dropped row must render as the no-plan placeholder in '
                'the week strip — never as a live workout.');
        expect(dayEntry['status'], 'none');

        // Raw read still sees the audit row.
        final raw = WorkoutScheduleReadService.instance
            .getScheduleRowForDate(droppedDate);
        expect(raw, isNotNull);
        expect(raw!['status'], 'dropped');
      },
    );

    test(
      'over-filter guard: completed + planned rows STILL read through '
      'getScheduleForDate (the filter must not eat live rows)',
      () async {
        await HiveService.instance.workoutBox.put('schedule_$todayStr', {
          'date': todayStr,
          'week': 1,
          'day_of_week': today.weekday - 1,
          'workout_name': 'Push A',
          'status': 'completed',
          'type': 'custom_template',
          'exercises': [
            {'exercise_name': 'Bench Press'},
          ],
        });
        final viaReader =
            WorkoutScheduleReadService.instance.getScheduleForDate(today);
        expect(viaReader, isNotNull);
        expect(viaReader!['status'], 'completed',
            reason: 'completed-day view (Train) relies on the completed row '
                'reading through — the invisible filter must be scoped to '
                '{paused, moved, dropped} only.');
      },
    );

    test(
      'coach log_set on a MOVED day must NOT auto-complete the terminal row '
      '(derived-completion guard)',
      () async {
        await HiveService.instance.workoutBox.put('schedule_$todayStr', {
          'date': todayStr,
          'week': 1,
          'day_of_week': today.weekday - 1,
          'workout_name': 'Push A',
          'status': 'moved',
          'type': 'custom_template',
          'moved_to': istDateStr(today.add(const Duration(days: 1))),
          'moved_via': 'ai_coach',
          'moved_at': DateTime.now().toIso8601String(),
          'exercises': [
            {'exercise_name': 'Bench Press'},
          ],
        });

        final container = ProviderContainer(overrides: [
          authStateProvider.overrideWith((ref) => const Stream.empty()),
        ]);
        addTearDown(container.dispose);
        final ref = container.read(_refProvider);

        final intent = ToolIntent(
          id: 'intent_logset_moved_day',
          type: 'log_set',
          payload: {
            'exerciseId': 'Bench Press',
            'weightKg': 60,
            'reps': 8,
            'sets': 3,
            'date': todayStr,
          },
          confirmationClass: ConfirmationClass.reviewable,
          previewSummary: '',
          createdAt: DateTime.now(),
        );
        final res = await ToolDispatcher.instance.execute(ref, intent);
        expect(res.success, isTrue, reason: 'the LOG itself must succeed');

        final row = rawRow(todayStr);
        expect(row, isNotNull);
        expect(row!['status'], 'moved',
            reason: 'pre-fix, _maybeCompleteScheduledDay saw the terminal '
                "row as a live planned workout and flipped it to 'completed' "
                '— resurrecting the moved workout on the OLD date and '
                'crediting streak for a workout done elsewhere.');
        expect(row['completed_at'], isNull);
      },
    );
  });
}
