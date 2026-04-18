import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/ai_service.dart';

void main() {
  test('_compactContext keeps coach_memory when total exceeds 9.5KB', () {
    final padding = List.generate(200, (i) => {'k$i': 'v$i' * 30});
    final ctx = {
      'profile': {'name': 'Upen', 'goal': 'fat_loss'},
      'coach_memory': {
        'preferred_name': 'Upen',
        'communication_style': 'hinglish',
      },
      'step_history_7d': padding,
      'weight_trend': padding,
      'nutrition_trend': padding,
      'exercise_history': padding,
      'personal_records': padding,
      'coach_notices': padding,
      'coaching_notes': 'a' * 5000,
      'fitness_summary': 'b' * 1000,
    };
    expect(json.encode(ctx).length, greaterThan(9500));

    final compact = AiService.compactForTest(ctx);
    expect(compact['coach_memory'], isNotNull,
        reason: 'coach_memory must survive aggressive trimming');
    expect(compact['coach_memory']['preferred_name'], equals('Upen'));
  });
}
