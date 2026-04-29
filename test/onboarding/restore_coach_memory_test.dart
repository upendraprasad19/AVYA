// test/onboarding/restore_coach_memory_test.dart
//
// Contract test for B7: verifies that after _restoreCoachMemory writes
// induction columns into coachBox, InductionService correctly reports the
// user as inducted — and that an empty coachBox (un-inducted user) reports
// not inducted.
//
// We don't mock Supabase here. Instead we simulate what the restore method
// does (put keys into coachBox) and assert that InductionService reads them
// correctly. The production _restoreCoachMemory code is audited at
// lib/core/services/sync_service.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  group('coach_memory restore behavior', () {
    test(
        'after logout + restore, induction state written to coachBox reflects '
        'InductionService.inductionCompleted = true', () async {
      // Simulate what _restoreCoachMemory writes into local Hive
      // (the 9 induction columns fetched via maybeSingle() from cloud)
      await HiveService.instance.coachBox
          .put('committed_at', '2026-04-27T12:00:00Z');
      await HiveService.instance.coachBox
          .put('committed_to_lt_cdr', true);
      await HiveService.instance.coachBox
          .put('induction_completed_at', '2026-04-27T12:05:00Z');
      await HiveService.instance.coachBox.put('why_now', 'October wedding');
      await HiveService.instance.coachBox
          .put('definition_of_winning', 'Run 10 km without stopping');
      await HiveService.instance.coachBox.put('known_injuries', 'Left knee');
      await HiveService.instance.coachBox
          .put('typical_wake_time', '06:00');
      await HiveService.instance.coachBox
          .put('preferred_workout_time', 'morning');
      await HiveService.instance.coachBox
          .put('body_part_priorities', 'Core, Legs');

      // After the restore puts, InductionService must report fully inducted
      expect(InductionService.instance.hasCommitted, isTrue,
          reason: 'committed_to_lt_cdr=true should make hasCommitted true');
      expect(InductionService.instance.inductionCompleted, isTrue,
          reason:
              'induction_completed_at present should make inductionCompleted true');
    });

    test(
        'un-inducted user (no cloud row → no coachBox writes) reports '
        'hasCommitted=false, inductionCompleted=false', () async {
      // No writes — simulates _restoreCoachMemory receiving maybeSingle()=null
      // and returning early without touching coachBox.
      expect(InductionService.instance.hasCommitted, isFalse);
      expect(InductionService.instance.inductionCompleted, isFalse);
    });
  });
}
