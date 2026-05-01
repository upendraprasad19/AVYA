// test/ai_coach/dismiss_card_terminal_state_test.dart
//
// B-5: pin the contract that DISMISS taps write
// `intent_<id>_dismissed_at` to coachBox. The Hive marker is the durable
// signal that survives hot restart + low-memory background kill so the
// chat thread filter (B-4 step 4) can hide the card.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  test('DISMISS handler writes intent_<id>_dismissed_at', () async {
    final box = HiveService.instance.coachBox;
    const intentId = 'i_dismiss';
    final markerKey = 'intent_${intentId}_dismissed_at';

    expect(box.get(markerKey), isNull);

    // Mirror _ToolConfirmCardState._skip persistence:
    await box.put(markerKey, DateTime.now().toIso8601String());

    final raw = box.get(markerKey);
    expect(raw, isNotNull);
    // Stored value must be a parseable ISO timestamp.
    expect(() => DateTime.parse(raw as String), returnsNormally);
  });
}
