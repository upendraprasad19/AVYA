// Bug w7r4c3 regression test (APK Test #16.2).
//
// Pins the contract that the weight-log write path is awaitable:
//
//   1. WeightLogNotifier.logWeight returns Future<void>.
//   2. WeightLogSheet._save awaits the logWeight call before
//      invalidating the reader providers.
//   3. ConversationalLogHandler._logWeight awaits the logWeight call
//      before any downstream read.
//
// Pre-fix, all three were sync-signature / fire-and-forget. The
// HealthWriteService.logWeight implementation awaits a per-key mutex
// BEFORE calling box.put, so the Hive write resolves on a later
// microtask than the synchronous return — and the caller's
// ref.invalidate(weightHistoryProvider) read stale Hive, leaving the
// "N ENTRIES" footer stuck at the prior count.
//
// Source-grep contract (strips comments first per
// feedback_source_grep_strip_comments_first.md to avoid matching the
// anti-pattern's own explanatory comment).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
    .split('\n')
    .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
    .join('\n');

void main() {
  test('w7r4c3 — WeightLogNotifier.logWeight returns Future<void>', () {
    final src = _strip(
        File('lib/features/home/providers/home_provider.dart')
            .readAsStringSync());
    expect(
      src.contains(RegExp(r'Future<void>\s+logWeight\s*\(\s*double\s+weightKg\s*\)\s*async')),
      isTrue,
      reason: 'WeightLogNotifier.logWeight must be Future<void> async '
          '(not void) so callers can await before invalidating readers.',
    );
  });

  test(
      'w7r4c3 — WeightLogSheet._save awaits logWeight BEFORE invalidating reader providers',
      () {
    final src = _strip(
        File('lib/features/home/widgets/weight_log_sheet.dart')
            .readAsStringSync());

    final awaitIdx = src.indexOf(RegExp(
        r'await\s+ref\.read\(weightLogNotifierProvider\.notifier\)\.logWeight\b'));
    expect(awaitIdx, isNonNegative,
        reason:
            'WeightLogSheet._save must `await ref.read(...).logWeight(_weight)`. '
            'Sync call leaves the provider invalidate racing the Hive put.');

    final invalidateIdx =
        src.indexOf('ref.invalidate(weightHistoryProvider)', awaitIdx);
    expect(invalidateIdx, isNonNegative,
        reason:
            'WeightLogSheet._save must invalidate weightHistoryProvider AFTER awaiting logWeight.');
    expect(invalidateIdx, greaterThan(awaitIdx),
        reason: 'invalidate must follow the await — pre-fix order was reversed.');
  });

  test(
      'w7r4c3 — ConversationalLogHandler._logWeight awaits logWeight + invalidates readers',
      () {
    final src = _strip(File(
            'lib/features/ai_coach/services/conversational_log_handler.dart')
        .readAsStringSync());

    expect(
      src.contains(RegExp(
          r'await\s+ref\.read\(weightLogNotifierProvider\.notifier\)\.logWeight\b')),
      isTrue,
      reason:
          'ConversationalLogHandler._logWeight must await the WeightLogNotifier.logWeight call.',
    );
    expect(
      src.contains(RegExp(r'_logWeight\s*\([^)]*\)\s*async')),
      isTrue,
      reason:
          'ConversationalLogHandler._logWeight must be an async Future<bool> method '
          '(was sync bool pre-fix).',
    );
    expect(
      src.contains('ref.invalidate(weightHistoryProvider)') ||
          src.contains('ref.invalidate(todayWeightLoggedProvider)'),
      isTrue,
      reason:
          'ConversationalLogHandler._logWeight should invalidate the reader providers '
          'AFTER the await so the chat-driven write surfaces to home cards immediately.',
    );
  });

  test(
      'w7r4c3 — ConversationalLogHandler.executeAction awaits _logWeight in switch case',
      () {
    final src = _strip(File(
            'lib/features/ai_coach/services/conversational_log_handler.dart')
        .readAsStringSync());

    final caseIdx = src.indexOf('LogActionType.weight:');
    expect(caseIdx, isNonNegative,
        reason:
            'LogActionType.weight switch case must still exist in executeAction.');
    final returnIdx = src.indexOf('return', caseIdx);
    final segment = src.substring(returnIdx, returnIdx + 60);
    expect(
      segment.contains('await _logWeight'),
      isTrue,
      reason:
          'executeAction must `return await _logWeight(...)` so the outer Future<bool> '
          'resolves only after the Hive put.',
    );
  });
}
