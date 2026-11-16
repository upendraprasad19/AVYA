// Unit 3C (docs/plans/2026-11-16-generator-step3c-cardio-finisher.md §3, the re-record oracle; round 3 A-F2): what
// moved the 1,010 golden personas, in two checkable claims, before generator_golden_hashes.json is re-recorded.
//
// (1) The ATTACHMENT: with `CardioFinisher.debugReserve = false` (the finisher built, its time not reserved), ON and OFF
//     (`disable_cardio_finisher_shown`) differ ONLY in each day's `finisher` maps (the injury rule, the round rests,
//     d76's short finisher): every other byte of every persona is equal.
// (2) The RESERVATION: with it, every build_muscle and strength persona equals OFF byte for byte; the moved cardio-goal
//     personas are counted (the allocator's weekly ledger is shared, so a non-finisher day may move too; the share is
//     printed for the diagnose doc and bounded by the plan's §2.2 table, not asserted per day).
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/cardio_finisher.dart';
import '../helpers/generator_golden_personas.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('finisher_attribution');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List;
    for (final r in rows.whereType<Map>()) {
      await exBox.put((r['id'] ?? r['name']).toString(), Map<String, dynamic>.from(r));
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    await HiveService.instance.configBox.delete('disable_cardio_finisher_shown');
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// [m] with every `finisher` key removed, at any depth (`Phase.toMap` writes each day twice).
  Object? strip(Object? m) {
    if (m is Map) return {for (final e in m.entries) if (e.key != 'finisher') e.key: strip(e.value)};
    if (m is List) return [for (final v in m) strip(v)];
    return m;
  }

  Future<Map<String, String>> runAll({required bool off, bool reserve = true, bool stripFinisher = false}) async {
    if (off) {
      await HiveService.instance.configBox.put('disable_cardio_finisher_shown', true);
    } else {
      await HiveService.instance.configBox.delete('disable_cardio_finisher_shown');
    }
    CardioFinisher.debugReserve = reserve;
    try {
      return {
        for (final p in generatorGoldenPersonas())
          p.key: jsonEncode(stripFinisher ? strip(p.run().toMap()) : p.run().toMap()),
      };
    } finally {
      CardioFinisher.debugReserve = true;
      await HiveService.instance.configBox.delete('disable_cardio_finisher_shown');
    }
  }

  test('(1) attachment only: ON without the reservation equals OFF once the finisher maps are set aside', () async {
    final off = await runAll(off: true, stripFinisher: true);
    final onNoReserve = await runAll(off: false, reserve: false, stripFinisher: true);
    final diffs = [for (final k in off.keys) if (off[k] != onNoReserve[k]) k];
    expect(diffs, isEmpty, reason: '${diffs.length} personas differ outside the finisher; first 10: ${diffs.take(10)}');
    // The finisher itself did move (else the comparison above proves nothing).
    final offFull = await runAll(off: true);
    final onNoReserveFull = await runAll(off: false, reserve: false);
    expect([for (final k in offFull.keys) if (offFull[k] != onNoReserveFull[k]) k], isNotEmpty);
  });

  test('(2) the reservation: Build and strength unchanged; the moved cardio personas counted', () async {
    final off = await runAll(off: true);
    final on = await runAll(off: false);
    final moved = [for (final k in off.keys) if (off[k] != on[k]) k];
    final nonCardio = [
      for (final k in moved)
        if (k.contains('|build_muscle|') || k.contains('|strength|')) k,
    ];
    expect(nonCardio, isEmpty, reason: 'a Build / strength persona moved: ${nonCardio.take(10)}');
    final byGoal = <String, int>{};
    for (final k in moved) {
      final goal = k.split('|')[2];
      byGoal[goal] = (byGoal[goal] ?? 0) + 1;
    }
    // The share of changed days that carry the finisher (the golden personas all run at the default 60 minutes, so the
    // per-minutes split lives in the reservation test and the plan's §2.2 table).
    var changedDays = 0, changedFinisherDays = 0;
    for (final k in moved) {
      final a = (jsonDecode(off[k]!) as Map)['week_plans'] as List;
      final b = (jsonDecode(on[k]!) as Map)['week_plans'] as List;
      for (var w = 0; w < b.length; w++) {
        final da = (a[w] as Map)['workout_days'] as List;
        final db = (b[w] as Map)['workout_days'] as List;
        for (var d = 0; d < db.length; d++) {
          if (jsonEncode(strip(da[d])) == jsonEncode(strip(db[d]))) continue;
          changedDays++;
          final f = (db[d] as Map)['finisher'];
          if (f is List && f.isNotEmpty) changedFinisherDays++;
        }
      }
    }
    // ignore: avoid_print
    print('[finisher attribution] moved ${moved.length} of ${off.length}: $byGoal; changed days $changedDays, '
        'of which finisher days $changedFinisherDays');
  });
}
