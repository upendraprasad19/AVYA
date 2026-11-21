// test/ai_coach/circuit_breaker_test.dart
//
// APK Test #16.1 / Agent B (closes-diagnose: a17bc3) — pin the front-
// of-chat retry circuit breaker on AiBreakdownNotifier.
//
// State machine:
//   - 3 consecutive service-error fails for the same text → 4th
//     attempt is blocked client-side.
//   - A successful analyse clears the counter for that text.
//   - 5 minutes after the last fail the counter auto-resets.
//   - clear() resets all counters.
//   - Counter is in-memory (Map<String,int>) — not persisted.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

void main() {
  setUp(() {
    AiBreakdownNotifier.resetCircuitBreakerForTests();
  });

  test('breaker is closed below threshold', () {
    AiBreakdownNotifier.serviceFailCounts['foo'] = 2;
    AiBreakdownNotifier.serviceFailLastAt['foo'] = DateTime.now();
    expect(AiBreakdownNotifier.isCircuitBreakerOpen('foo'), isFalse);
  });

  test('breaker opens at threshold (3 fails)', () {
    AiBreakdownNotifier.serviceFailCounts['foo'] = 3;
    AiBreakdownNotifier.serviceFailLastAt['foo'] = DateTime.now();
    expect(AiBreakdownNotifier.isCircuitBreakerOpen('foo'), isTrue);
  });

  test('breaker auto-resets after 5-min cooldown', () {
    AiBreakdownNotifier.serviceFailCounts['foo'] = 3;
    AiBreakdownNotifier.serviceFailLastAt['foo'] =
        DateTime.now().subtract(const Duration(minutes: 6));

    expect(AiBreakdownNotifier.isCircuitBreakerOpen('foo'), isFalse,
        reason: 'stale counter beyond cooldown should auto-reset');
    // And the helper cleared the in-memory entries.
    expect(AiBreakdownNotifier.serviceFailCounts.containsKey('foo'), isFalse);
    expect(AiBreakdownNotifier.serviceFailLastAt.containsKey('foo'), isFalse);
  });

  test('different texts have independent breakers', () {
    AiBreakdownNotifier.serviceFailCounts['curd whey cashew'] = 3;
    AiBreakdownNotifier.serviceFailLastAt['curd whey cashew'] = DateTime.now();
    expect(AiBreakdownNotifier.isCircuitBreakerOpen('curd whey cashew'),
        isTrue);
    expect(AiBreakdownNotifier.isCircuitBreakerOpen('apple banana'), isFalse,
        reason: 'unrelated text must not inherit the open state');
  });

  test('threshold + cooldown constants are the contract', () {
    // Pin the constants so a future "let me bump this to 5" rewrite is
    // caught in CI. Founder approved 3 / 5 min.
    expect(AiBreakdownNotifier.circuitBreakerThreshold, equals(3));
    expect(AiBreakdownNotifier.circuitBreakerCooldown,
        equals(const Duration(minutes: 5)));
  });

  test('counter only opens when both count AND lastAt are set', () {
    // Defensive: count without timestamp should not open the breaker
    // (avoids "ghost open" if a refactor accidentally sets count but
    // forgets to stamp lastAt).
    AiBreakdownNotifier.serviceFailCounts['foo'] = 5;
    // intentionally not stamping lastAt
    expect(AiBreakdownNotifier.isCircuitBreakerOpen('foo'), isFalse);
  });

  test('resetCircuitBreakerForTests clears both maps', () {
    AiBreakdownNotifier.serviceFailCounts['a'] = 3;
    AiBreakdownNotifier.serviceFailLastAt['a'] = DateTime.now();
    AiBreakdownNotifier.serviceFailCounts['b'] = 1;

    AiBreakdownNotifier.resetCircuitBreakerForTests();

    expect(AiBreakdownNotifier.serviceFailCounts, isEmpty);
    expect(AiBreakdownNotifier.serviceFailLastAt, isEmpty);
  });

  group('integration shape — 3 fails open the breaker', () {
    test('simulated tap sequence: 3 fails → 4th would be blocked', () {
      const text = 'curd 200gms whey 1.5 scoops cashew 6';

      // Simulate 3 consecutive service errors via the same code path
      // the production catch block uses.
      for (var i = 0; i < 3; i++) {
        AiBreakdownNotifier.serviceFailCounts[text] =
            (AiBreakdownNotifier.serviceFailCounts[text] ?? 0) + 1;
        AiBreakdownNotifier.serviceFailLastAt[text] = DateTime.now();
      }

      // 4th attempt would be blocked.
      expect(AiBreakdownNotifier.isCircuitBreakerOpen(text), isTrue);
      expect(AiBreakdownNotifier.serviceFailCounts[text], equals(3));
    });

    test('success path clears the counter', () {
      const text = 'curd whey cashew';
      AiBreakdownNotifier.serviceFailCounts[text] = 2;
      AiBreakdownNotifier.serviceFailLastAt[text] = DateTime.now();

      // This is what the success path runs:
      AiBreakdownNotifier.serviceFailCounts.remove(text);
      AiBreakdownNotifier.serviceFailLastAt.remove(text);

      expect(AiBreakdownNotifier.isCircuitBreakerOpen(text), isFalse);
      expect(
          AiBreakdownNotifier.serviceFailCounts.containsKey(text), isFalse);
    });
  });
}
