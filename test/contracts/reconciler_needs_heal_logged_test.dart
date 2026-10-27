// test/contracts/reconciler_needs_heal_logged_test.dart
//
// Proves the wiring at plan_integrity_reconciler.dart:99 (needsHeal,
// isWorkout) actually changes when the OI-126 flag flips, calling the REAL
// static method — not a reconstruction of its logic.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Box cb;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('oi126_reconciler_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.configBoxName);
    HiveService.instance.markInitializedForTests();
    cb = HiveService.instance.configBox;
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('a logged, incomplete, exercise-less row needs healing once the flag is on', () {
    final entries = [
      {'type': 'logged', 'status': 'planned', 'exercises': <Map<String, dynamic>>[]},
    ];

    // Flag OFF (default): needsHeal's isWorkout check excludes 'logged' under
    // the pre-fix inline form → the row is skipped (`continue`) → no heal
    // need is ever reported for it, regardless of its missing exercises.
    expect(PlanIntegrityReconciler.needsHeal(entries), isFalse,
        reason: 'flag off: a logged row is not treated as a workout, so its empty exercises are never checked');

    cb.put('enable_logged_counts_as_phase_training_day', true);

    // Flag ON: 'logged' now counts as a workout → the row is NOT skipped →
    // its empty exercises trip the restore-skip symptom → heal needed.
    expect(PlanIntegrityReconciler.needsHeal(entries), isTrue,
        reason: 'flag on: a logged row now counts as a workout, exposing its missing exercises as a heal-need');
  });
}
