// f9d2e7 — writer->reader FIELD-NAME contract for the first-PRO grant flag.
//
// Gate 9 (check_writeservice_contracts) requires this file for the
// streak_freeze_first_pro_grant SoT concept (hive key_prefix: "progress").
// It pins the SEMANTIC the recurring writer/reader-drift class breaks: the
// grant-done flag MUST be the SAME key — streak_freezes_first_pro_grant_done
// (PLURAL "freezes") — at the WRITER (grantFirstProFreezes) AND every READER
// (the idempotency re-check, the sync push, the restore, the cloud column).
// A singular/plural drift here would silently re-grant (or never grant) the
// 3 freezes. The behavioral grant/lapse semantics live in the sibling
// streak_freeze_first_pro_grant_behavioral_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

const _pluralKey = 'streak_freezes_first_pro_grant_done';
const _singularDrift = 'streak_freeze_first_pro_grant_done'; // the bug shape

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  group('streak_freeze_first_pro_grant — writer->reader field contract (f9d2e7)',
      () {
    test('grantFirstProFreezes WRITES the plural flag key; getProgress READS it',
        () async {
      await HiveService.instance.userBox
          .put('progress', {'streak_freezes_available': 0});
      StreakProgressService.instance.grantFirstProFreezes();
      final p = UserRepository.instance.getProgress()!;
      expect(p.containsKey(_pluralKey), isTrue,
          reason: 'writer must use the plural key the readers expect');
      expect(p[_pluralKey], true);
      expect(p[_singularDrift], isNull,
          reason: 'the singular mis-spelling (drift bug shape) must NOT exist');
      expect(p['streak_freezes_available'], 3, reason: 'grant set 0 -> 3');
    });

    test('source contract: writer + sync use the plural key, never the singular',
        () {
      final writer = File('lib/core/services/streak_progress_service.dart')
          .readAsStringSync();
      final sync =
          File('lib/core/services/sync/sync_restore_completeness.dart')
              .readAsStringSync();
      // The singular token is NOT a substring of the plural ("freezes" vs
      // "freeze_"), so a standalone-singular match is a genuine drift hit.
      final singularRe = RegExp('$_singularDrift(?![a-z])');
      for (final entry in {'writer': writer, 'sync': sync}.entries) {
        expect(entry.value.contains(_pluralKey), isTrue,
            reason: '${entry.key}: plural key must be present');
        expect(singularRe.hasMatch(entry.value), isFalse,
            reason: '${entry.key}: singular-spelled drift key must be absent');
      }
    });
  });
}
