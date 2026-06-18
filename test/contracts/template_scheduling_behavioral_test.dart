// BEHAVIORAL CONTRACT TEST — template_scheduling
//
// Concept:   template_scheduling
// Writer:    lib/core/services/template_service.dart
//            (assignTemplateToDate, unscheduleTemplateFromDate)
// Reader:    Hive read-back via WorkoutScheduleReadService.getScheduleForDate
//
// Assert:
//   1. After assignTemplateToDate(id, date):
//      a. schedule_<date> exists and has type=='custom_template'.
//      b. displaced_<date> holds the ORIGINAL plan entry (the backup).
//   2. After unscheduleTemplateFromDate(date):
//      a. schedule_<date> is restored to the original (displaced) entry.
//      b. displaced_<date> is deleted.
//   3. If no displaced entry exists, unscheduleTemplateFromDate deletes
//      schedule_<date> entirely (no phantom remains).
//
//   These asserts FAIL if:
//   - _schedulePrefix / _displacedPrefix constants drift.
//   - assignTemplateToDate stops writing displaced backup to workoutBox.
//   - unscheduleTemplateFromDate stops restoring from displaced_ before deleting.
//   - WorkoutWriteService.upsertScheduled key formula changes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/template_service.dart'
    show AssignTemplateOk, TemplateService;
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

// Test date and template id.
final _testDate = DateTime(2026, 7, 15); // Wednesday
const _templateId = 'template_test_001';
const _originalWorkoutName = 'Original Chest Day';
const _templateWorkoutName = 'Custom Pull Day';

void main() {
  late Directory tempDir;
  const fakeUserId = '00000000-1111-2222-3333-000000000006';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('ts_behavioral_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.openForUser(fakeUserId);
  });

  tearDown(() async {
    final dateKey = formatDateKey(_testDate);
    final box = HiveService.instance.workoutBox;
    await box.delete('schedule_$dateKey');
    await box.delete('displaced_$dateKey');
    await box.delete(_templateId);
    await HiveUserSession.closeAll();
  });

  // Helper: seed a template entry in workoutBox.
  Future<void> _seedTemplate() async {
    await HiveService.instance.workoutBox.put(_templateId, {
      'name': _templateWorkoutName,
      'type': 'workout_template',
      'exercises': [
        {
          'exercise_id': 'pull_up',
          'exercise_name': 'Pull Up',
          'sets': 3,
          'reps': '8-12',
          'logging_type': 'bodyweight_reps',
        }
      ],
    });
  }

  // Helper: seed an existing planned schedule entry (the one to be displaced).
  Future<void> _seedOriginalSchedule() async {
    await WorkoutWriteService.instance.upsertScheduled(
      date: _testDate,
      entry: {
        'type': 'workout',
        'date': formatDateKey(_testDate),
        'day_of_week': 'Wednesday',
        'workout_name': _originalWorkoutName,
        'status': 'planned',
        'exercises': [
          {
            'exercise_id': 'bench_press',
            'exercise_name': 'Bench Press',
            'sets': 4,
          }
        ],
      },
      source: WriteSource.schedSwap,
    );
  }

  // ── Test 1a: assignTemplateToDate writes schedule_<date> ────────────────
  test(
    'assignTemplateToDate writes schedule_<date> with type==custom_template',
    () async {
      await _seedTemplate();
      await _seedOriginalSchedule();

      final result =
          await TemplateService.instance.assignTemplateToDate(
        _templateId,
        _testDate,
      );

      expect(
        result,
        isA<AssignTemplateOk>(),
        reason:
            'assignTemplateToDate must succeed (AssignTemplateOk) when the '
            'template exists and the date is not already completed.',
      );

      final entry = WorkoutScheduleReadService.instance
          .getScheduleForDate(_testDate);

      expect(
        entry,
        isNotNull,
        reason:
            'schedule_<date> must exist after assignTemplateToDate. '
            'Null means either WorkoutWriteService.upsertScheduled key formula '
            'drifted or the entry was not written at all.',
      );

      expect(
        entry!['type'],
        equals('custom_template'),
        reason:
            'schedule_<date>.type must be custom_template after assignment. '
            "Got: ${entry['type']}. If this is 'workout', the template entry "
            'shape written by assignTemplateToDate drifted.',
      );

      expect(
        entry['template_id'],
        equals(_templateId),
        reason:
            'schedule_<date>.template_id must match the assigned template ID. '
            "Got: ${entry['template_id']}.",
      );
    },
  );

  // ── Test 1b: assignTemplateToDate saves displaced backup ─────────────────
  test(
    'assignTemplateToDate saves displaced_<date> backup of original entry',
    () async {
      await _seedTemplate();
      await _seedOriginalSchedule();

      await TemplateService.instance.assignTemplateToDate(
        _templateId,
        _testDate,
      );

      final dateKey = formatDateKey(_testDate);
      final displaced =
          HiveService.instance.workoutBox.get('displaced_$dateKey');

      expect(
        displaced,
        isNotNull,
        reason:
            "displaced_<date> must contain the original schedule entry after "
            "assignTemplateToDate. Null means the backup write "
            "(_hive.workoutBox.put(displacedKey, existingMap)) was removed. "
            "Without this, unscheduleTemplateFromDate cannot restore the original.",
      );

      final displacedMap = displaced is Map
          ? Map<String, dynamic>.from(displaced)
          : <String, dynamic>{};

      expect(
        displacedMap['workout_name'],
        equals(_originalWorkoutName),
        reason:
            "displaced_<date> must contain the ORIGINAL schedule entry "
            "(workout_name='$_originalWorkoutName'), not the template. "
            "If this holds the template name, the writer is backing up the "
            "wrong entry.",
      );
    },
  );

  // ── Test 2a: unscheduleTemplateFromDate restores original entry ──────────
  test(
    'unscheduleTemplateFromDate restores original schedule from displaced backup',
    () async {
      await _seedTemplate();
      await _seedOriginalSchedule();

      // Assign (creates displaced_ backup + writes template to schedule_).
      await TemplateService.instance.assignTemplateToDate(
        _templateId,
        _testDate,
      );

      // Now unschedule.
      await TemplateService.instance.unscheduleTemplateFromDate(_testDate);

      // schedule_<date> must be the ORIGINAL entry.
      final restored = WorkoutScheduleReadService.instance
          .getScheduleForDate(_testDate);

      expect(
        restored,
        isNotNull,
        reason:
            'schedule_<date> must exist after unscheduleTemplateFromDate when '
            'a displaced backup was present.',
      );
      expect(
        restored!['type'],
        isNot(equals('custom_template')),
        reason:
            'Restored schedule_<date> must NOT be custom_template — '
            'it must be the original plan entry. Type is still custom_template, '
            'which means unscheduleTemplateFromDate did not restore from '
            'displaced_ before deleting it.',
      );
      expect(
        restored['workout_name'],
        equals(_originalWorkoutName),
        reason:
            'Restored schedule_<date>.workout_name must match the original '
            "('$_originalWorkoutName'). "
            'Got: ${restored['workout_name']}.',
      );
    },
  );

  // ── Test 2b: unscheduleTemplateFromDate deletes displaced_ after restore ─
  test(
    'unscheduleTemplateFromDate deletes displaced_<date> after restore',
    () async {
      await _seedTemplate();
      await _seedOriginalSchedule();

      await TemplateService.instance.assignTemplateToDate(
        _templateId,
        _testDate,
      );
      await TemplateService.instance.unscheduleTemplateFromDate(_testDate);

      final dateKey = formatDateKey(_testDate);
      final displaced =
          HiveService.instance.workoutBox.get('displaced_$dateKey');

      expect(
        displaced,
        isNull,
        reason:
            'displaced_<date> must be deleted after unscheduleTemplateFromDate '
            'completes the restore. If this is non-null, workoutBox.delete(displacedKey) '
            'was not called, leaving stale displaced_ keys in Hive.',
      );
    },
  );

  // ── Test 3: unschedule with no displaced → schedule_ deleted ────────────
  test(
    'unscheduleTemplateFromDate deletes schedule_<date> when no displaced backup exists',
    () async {
      await _seedTemplate();

      // Assign without seeding an original schedule first — no existing entry
      // means the template is written but there is no displaced_ backup.
      await TemplateService.instance.assignTemplateToDate(
        _templateId,
        _testDate,
      );

      // Verify no displaced_ was created (since there was no original to back up).
      final dateKey = formatDateKey(_testDate);
      final displaced =
          HiveService.instance.workoutBox.get('displaced_$dateKey');
      // It may or may not exist; we just remove it manually to simulate the
      // "no backup" state (the guard: only backed up when not already a template).
      if (displaced != null) {
        await HiveService.instance.workoutBox.delete('displaced_$dateKey');
      }

      // Unschedule — no displaced, so the schedule_ itself should be deleted.
      await TemplateService.instance.unscheduleTemplateFromDate(_testDate);

      final entry = WorkoutScheduleReadService.instance
          .getScheduleForDate(_testDate);
      expect(
        entry,
        isNull,
        reason:
            'When no displaced_ backup exists, unscheduleTemplateFromDate must '
            'delete schedule_<date> entirely. Non-null result means the '
            '_hive.workoutBox.delete(scheduleKey) branch is broken.',
      );
    },
  );
}
