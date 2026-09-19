// C5 (ai-coach-ux-tool-integrity) — coach_memory injury-append mutex +
// pausePlan failure telemetry.
//
// FINDING 1: `_appendInjuryToCoachMemory` (tool_dispatcher.dart) does a
// read-modify-write of coachBox 'coach_memory' with NO mutex. Two intent
// cards from one multi-intent turn are confirmed independently
// (pending_tool_intents_provider.confirm — each user tap awaits its own
// ToolDispatcher.execute), so two concurrent executes can race the RMW and
// one injury append is lost. Fix: a chained-future mutex
// (`_coachMemoryLock` + `await prev` under a Completer).
//
// FINDING 2: `_executePausePlan`'s `on PausePlanException` catch returned a
// failure WITHOUT ErrorTelemetry, while every sibling failure path
// (reschedule :805, modify-for-injury :643) logs. Fix: fire
// `tool_dispatch_pause_plan_failed` before the failure return.
//
// Honest note on the behavioral leg (recorded per the C5 brief): the RMW's
// get→build→add section contains no `await`, so within a single isolate the
// pre-fix window may not reproduce deterministically; the 20-trial loop
// below probes it empirically and the source pin makes the mutex
// regression-proof regardless. Pre-fix result is recorded in the
// diagnose-doc.

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_coach_mem_mutex');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final name in [
      HiveService.coachBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'coachBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await HiveUserSession.closeAll();
  });

  List<Map<String, dynamic>> readInjuries() {
    final raw = HiveService.instance.coachBox.get('coach_memory');
    if (raw is! Map) return const [];
    final existing = raw['injuries'];
    if (existing is! List) return const [];
    return existing.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  test('behavioral: two concurrent injury appends BOTH survive (20 trials)',
      () async {
    for (var trial = 0; trial < 20; trial++) {
      await HiveService.instance.coachBox.delete('coach_memory');

      // Fire BOTH without awaiting the first — the concurrent-execution
      // shape a multi-intent turn produces when the user taps two cards
      // back-to-back.
      final f1 = ToolDispatcher.instance
          .appendInjuryToCoachMemoryForTest('knee', 'moderate');
      final f2 = ToolDispatcher.instance
          .appendInjuryToCoachMemoryForTest('shoulder', 'mild');
      await Future.wait([f1, f2]);

      final injuries = readInjuries();
      expect(injuries.length, 2,
          reason: 'trial $trial: BOTH concurrent appends must survive — '
              'got ${injuries.map((e) => e["part"])}');
      final parts = injuries.map((e) => e['part']).toSet();
      expect(parts, containsAll(<String>['knee', 'shoulder']),
          reason: 'trial $trial');
    }
  });

  test('behavioral: sequential appends still accumulate under the lock',
      () async {
    await HiveService.instance.coachBox.delete('coach_memory');
    await ToolDispatcher.instance
        .appendInjuryToCoachMemoryForTest('knee', 'moderate');
    await ToolDispatcher.instance
        .appendInjuryToCoachMemoryForTest('shoulder', 'mild');
    final injuries = readInjuries();
    expect(injuries.length, 2);
  });

  test('source pin: _appendInjuryToCoachMemory is serialized by '
      '_coachMemoryLock (chained-future mutex)', () {
    final src = File('lib/features/ai_coach/services/tool_dispatcher.dart')
        .readAsStringSync();
    expect(src.contains('static Future<void> _coachMemoryLock'), isTrue,
        reason: 'the chained-future mutex field must exist');
    expect(src.contains('await prev;'), isTrue,
        reason: 'each RMW must wait for the previous holder '
            '(_coachMemoryLock await-prev pattern)');
  });

  test('source pin: PausePlanException catch logs tool_dispatch_pause_plan_failed',
      () {
    final src = File('lib/features/ai_coach/services/tool_dispatcher.dart')
        .readAsStringSync();
    final catchIdx = src.indexOf('} on PausePlanException catch (e) {');
    expect(catchIdx, greaterThan(-1),
        reason: 'the PausePlanException catch must exist');
    final window = src.substring(
        catchIdx,
        (catchIdx + 400).clamp(0, src.length));
    expect(window.contains('tool_dispatch_pause_plan_failed'), isTrue,
        reason: 'the pause_plan failure path must log ErrorTelemetry like '
            'its reschedule/modify-for-injury siblings');
  });
}
