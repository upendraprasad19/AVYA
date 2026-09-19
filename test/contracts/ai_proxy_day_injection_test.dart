import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for Bug C (APK Test #3, 2026-04-26).
///
/// ai-proxy/index.ts had no day-of-week injection in the system prompt,
/// so Gemini guessed (called Sunday "Monday" + invented "100% skip" stat).
void main() {
  test('ai-proxy injects IST day-of-week into system prompt', () {
    final source = File(
      'supabase/functions/ai-proxy/index.ts',
    ).readAsStringSync();

    // Day-of-week injection
    expect(
      source.contains('Asia/Kolkata') &&
          (source.contains('weekday') || source.contains('day_of_week')),
      isTrue,
      reason: 'ai-proxy must compute current weekday in Asia/Kolkata '
          'timezone and inject it into the system prompt. Bug C.',
    );

    // Anti-fabrication rule must be present
    expect(
      source.contains('NEVER cite percentages') ||
          source.contains('never cite percentages') ||
          source.contains('do not invent statistics') ||
          source.contains('Do NOT invent statistics'),
      isTrue,
      reason: 'ai-proxy system prompt must include an anti-fabrication '
          'rule warning Gemini not to cite percentages/trends without '
          'data support. Bug C ("100% skip Monday workouts" hallucination).',
    );
  });
}
