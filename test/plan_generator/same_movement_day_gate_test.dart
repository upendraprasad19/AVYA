// Library Batch S1b-2 (plan docs/plans/2026-11-09-library-batch-s1b2-loaded-versions.md, Decision 6): the founder's
// condition (2026-11-08) that a loaded version and its original never share a day, gated on the PRODUCTION path.
//
// The REAL generateV4 over the 998 golden personas, with the core-list pool OFF (today's path for every user) and ON
// (ship-dark), each variant's day of each week read from the built Phase. Hard zero: no day holds a row and the row its
// `same_movement_as` names. The oracle restates the link from the raw library JSON (it never calls SameMovement), so a
// broken helper cannot pass its own test. Non-vacuity: in each world, days holding a member of a pair must exist, and
// some must hold a LOADED version (otherwise the zero would say nothing about the rule).
//
// Mutations (diagnose doc): the queryV4 expansion removed (OFF red), the ON picked partners removed (ON red).
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

import '../helpers/generator_golden_personas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  // Oracle: loaded version name -> original name, restated from the raw library.
  late Map<String, String> originalOf;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('same_movement_gate');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final r in rows) {
      await exBox.put(r['id'] as String, r);
    }
    final nameById = {for (final r in rows) r['id'] as String: r['name'] as String};
    originalOf = {
      for (final r in rows)
        if (r['same_movement_as'] is String) r['name'] as String: nameById[r['same_movement_as']]!,
    };
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> runWorld(bool on) async {
    await HiveService.instance.configBox.put('enable_core_list_pool', on);
    final bad = <String>[];
    var daysWithMember = 0, daysWithLoaded = 0;
    for (final p in generatorGoldenPersonas()) {
      final Phase phase = p.run();
      for (var w = 0; w < phase.weekPlans.length && w < 2; w++) {
        final days = phase.weekPlans[w].workoutDays;
        for (var d = 0; d < days.length; d++) {
          final names = {for (final e in days[d].exercises) e.exerciseName};
          var member = false;
          for (final n in names) {
            final orig = originalOf[n];
            if (orig != null) {
              member = true;
              daysWithLoaded++;
              if (names.contains(orig)) bad.add('${p.key} week ${w + 1} day ${d + 1}: $n with $orig');
            } else if (originalOf.containsValue(n)) {
              member = true;
            }
          }
          if (member) daysWithMember++;
        }
      }
    }
    await HiveService.instance.configBox.put('enable_core_list_pool', false);
    expect(originalOf.length, 9, reason: 'the nine loaded versions (N14 to N22)');
    expect(daysWithMember, greaterThan(0), reason: 'non-vacuity: no day held a member of a pair');
    // Measured floors (2026-11-09, 998 personas): OFF 5 placements, ON 977. `> 0` alone let OFF collapse to one day
    // unnoticed (B-pass seat A); a change that moves these on purpose re-measures them here.
    expect(daysWithLoaded, greaterThanOrEqualTo(on ? 977 : 5),
        reason: 'non-vacuity: fewer days held a loaded version than measured ($daysWithLoaded)');
    expect(bad, isEmpty, reason: '${bad.length} day(s) hold a loaded version and its original');
    // ignore: avoid_print
    print('same-movement gate ${on ? 'ON' : 'OFF'}: $daysWithMember day(s) with a member, '
        '$daysWithLoaded loaded-version placement(s), 0 shared days');
  }

  test('OFF (every user today): no day holds a loaded version and its original', () => runWorld(false));
  test('ON (core-list pool, ship-dark): no day holds a loaded version and its original', () => runWorld(true));
}
