// Source-grep contract for OI-45's usage-counter-race batch (2026-07-29).
// Presence-only (feedback_source_grep_false_confidence.md) — the behavioral
// companion is usage_counter_service_race_behavioral_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('OI-45 UsageCounterService per-key mutex', () {
    test('increment() is wrapped in _withLock, not a bare read-then-write',
        () {
      final src = _src('lib/core/services/usage_counter_service.dart');
      expect(src.contains('_withLock('), isTrue);
      expect(src.contains('Map<String, Completer<void>> _locks'), isTrue);

      final incrementStart = src.indexOf('Future<void> increment(');
      final incrementEnd = src.indexOf('\n  }', incrementStart);
      final incrementBody = src.substring(incrementStart, incrementEnd);
      expect(
        incrementBody.contains('_withLock('),
        isTrue,
        reason: 'increment() must serialize its read-modify-write through '
            '_withLock, not race a bare read/write pair.',
      );
    });

    test('MessageLimitNotifier.incrementToday() has the same defensive lock',
        () {
      final src = _src('lib/features/ai_coach/providers/ai_coach_provider.dart');
      expect(src.contains('Completer<void>? _lock;'), isTrue);

      final incrementStart = src.indexOf('Future<void> incrementToday(');
      expect(incrementStart, greaterThan(-1));
      final incrementEnd = src.indexOf('\n  }', incrementStart);
      final incrementBody = src.substring(incrementStart, incrementEnd);
      expect(
        incrementBody.contains('_lock'),
        isTrue,
        reason: 'incrementToday() must serialize through the same-shaped '
            'lock as UsageCounterService.increment (sibling finding, same '
            'batch).',
      );
    });
  });
}
