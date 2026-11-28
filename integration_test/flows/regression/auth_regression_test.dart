import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icanbefitter/core/constants/app_environment.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../../helpers/hive_test_helper.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// REGRESSION TESTS — AUTH (clearAllData isolation)
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Split from `regression_bug_fixes_test.dart` (T5, audit 2026-05-20).
///
/// R17 — clearAllData wipes coachBox (prevents cross-user chat leakage)

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    kIsDevFlavor = true;
    await initHiveForTest();
    await SupabaseService.instance.initialize();
  });

  tearDown(() async {
    await clearHiveForTest();
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG [Session 2026-04-02] #2 — Auth isolation: clearAllData clears coachBox
  // ─────────────────────────────────────────────────────────────────────────────

  test('R17: clearAllData wipes coachBox (AI chat history)', () async {
    // Seed some chat history.
    await HiveService.instance.coachBox.put('chat_msg_001', {
      'role': 'user',
      'content': 'Hello coach',
      'created_at': DateTime.now().toIso8601String(),
    });
    await HiveService.instance.coachBox.put('chat_msg_002', {
      'role': 'assistant',
      'content': 'Hi there!',
      'created_at': DateTime.now().toIso8601String(),
    });

    expect(HiveService.instance.coachBox.length, equals(2),
        reason: 'Precondition: coachBox should have 2 messages');

    await UserRepository.instance.clearAllData();

    expect(HiveService.instance.coachBox.length, equals(0),
        reason: 'clearAllData must clear coachBox — prevents cross-user chat leakage');
    expect(HiveService.instance.workoutBox.length, equals(0),
        reason: 'clearAllData must also clear workoutBox');
    expect(HiveService.instance.nutritionBox.length, equals(0),
        reason: 'clearAllData must also clear nutritionBox');
  });
}
