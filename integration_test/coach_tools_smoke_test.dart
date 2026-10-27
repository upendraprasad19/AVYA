import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AI coach tool flow E2E', (tester) async {
    // TODO: Phase E quality work.
    // This test should:
    //  1. Boot the app with overridden ai-proxy returning canned tool_intents
    //  2. Send a message that triggers swap_exercise
    //  3. Verify ToolConfirmCard appears with "Squat → Goblet Squat"
    //  4. Tap Confirm
    //  5. Verify Hive schedule entry updated
    //  6. Verify all 6 providers invalidated
    //
    // Setup requires:
    //  - Hive.initFlutter with temp dir
    //  - Sample exerciseBox + workoutBox seed data
    //  - HTTP mock (or AiService stub via ProviderContainer override)
    //  - Riverpod ProviderScope with overrides
  }, skip: true); // TODO Phase E follow-up
}
