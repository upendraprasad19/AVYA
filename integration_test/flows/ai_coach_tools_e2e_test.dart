// audit-2026-05-11 Phase 7 — AI coach tool-calling E2E.
//
// Critical untested flow: chat → AI calls `logMealByText` →
// confirmation card → user confirms → NutritionWriteService.logMeal
// writes Hive + cloud → home macros update.
//
// 20 AI coach tools live across 4 families (workout/progress/
// nutrition/plan per CLAUDE.md §11). The READ tools execute
// server-side; WRITE tools emit ToolIntent that the client confirms
// via card/sheet then dispatches to the canonical WriteServices.
// The Test #11 L1 founder-reported "didn\'t log" bug was actually a
// missing snackbar — the data WAS saved. End-to-end coverage would
// have caught it.
//
// Run:
//   flutter test --dart-define-from-file=.env \
//     integration_test/flows/ai_coach_tools_e2e_test.dart \
//     --flavor dev

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('AI coach tool-calling E2E', () {
    test('T1 — chat "I had 2 chapatis" triggers logMealByText tool intent',
        () {
      // ai-proxy chat channel → tool-loop → logMealByText emitted →
      // BreakdownCard appears in chat with the parsed items.
    }, skip: 'Phase 7 scaffold — needs Gemini test budget + device harness.');

    test('T2 — confirm card writes Hive nlog_* + shows "Meal saved" snackbar',
        () {
      // Test #11 L1 fix: snackbar appears AFTER nlog_* write.
      // Verify both: nutritionBox has the row AND the snackbar text
      // is visible.
    }, skip: 'Phase 7 scaffold — needs Gemini test budget + device harness.');

    test('T3 — counter increments at API call site, not save site (M1)', () {
      // Free user analyses 5 meals but saves only 3 → counter shows
      // 5 used (server-correct), not 3 (client-stale).
    }, skip: 'Phase 7 scaffold — needs Gemini test budget + device harness.');

    test('T4 — destructive write tool (e.g. regeneratePlanBlock) shows diff sheet',
        () {
      // 3 confirmation classes: trivial (auto-confirm), reviewable
      // (inline card), destructive (bottom-sheet with diff preview).
      // regeneratePlanBlock is destructive.
    }, skip: 'Phase 7 scaffold — needs Gemini test budget + device harness.');

    test('T5 — H-22 length cap: 6000-char food_text request returns 400', () {
      // ai-proxy food_text_analysis branch caps text at 5000 chars
      // post-H-22 fix.
    }, skip: 'Phase 7 scaffold — needs Gemini test budget + device harness.');

    test('T6 — H-21 image cap: 8MB base64 returns 400 on scan_meal', () {
      // ai-proxy scan_meal/cart_auditor branch caps base64 at
      // 7_500_000 chars (~5.6MB decoded) post-H-21 fix.
    }, skip: 'Phase 7 scaffold — needs Gemini test budget + device harness.');
  });
}
