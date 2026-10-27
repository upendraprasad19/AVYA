// Regression test for audit-2026-05-16 reader-side / F2-R3 — sleep
// dual-key hazard.
//
// `ConversationalLogHandler._logSleep` (the AI chat path for sleep
// reporting) was a DIRECT writer to the legacy `sleep_logs` LIST key
// in healthBox. The canonical per-day key `sleep_log_<istDate>` (written
// by `HealthWriteService.logSleep`) was never touched by this path —
// so AI-coach-logged sleeps were invisible to:
//   - `profile_provider.dailySleepProvider` (reads `sleep_log_<date>`)
//   - `ai_coach_repository._countSleepLogsLast7Days` (scans `sleep_log_*`)
//   - The AI snapshot's `sleep_logs_count_7d` field
// User-facing symptom: AI coach reported "your sleep data isn't logged"
// despite the user having reported sleep through the same coach minutes
// earlier.
//
// Fix: chat handler now routes through `HealthWriteService.logSleep`
// (same canonical writer as the manual UI path). closes-diagnose:
// 2026-05-16-sleep-dual-key
//
// This is a source-grep contract test — pins the routing rule rather
// than exercising runtime so it survives signature drift.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/ai_coach/services/conversational_log_handler.dart')
        .readAsStringSync();
  });

  group('AI chat sleep routing', () {
    test('_logSleep delegates to HealthWriteService.logSleep', () {
      // The fix replaced direct `healthBox.put('sleep_logs', logs)` with
      // a call to the canonical writer. The exact call signature.
      expect(
        src.contains('HealthWriteService.instance.logSleep('),
        isTrue,
        reason:
            '_logSleep must route through HealthWriteService.logSleep so '
            'the canonical per-day key sleep_log_<istDate> is written '
            'and downstream readers see the AI-logged sleep.',
      );
    });

    test('_logSleep does NOT directly write the legacy sleep_logs list',
        () {
      // The pre-fix direct write was the bug. Source-grep ensures it
      // doesn't return. Allow the writer mentioning the legacy list in
      // a comment — but no `healthBox.put('sleep_logs'` call.
      final hasDirectListWrite =
          RegExp(r"healthBox\.put\(\s*'sleep_logs'").hasMatch(src);
      expect(hasDirectListWrite, isFalse,
          reason:
              'Pre-fix direct write `healthBox.put(\'sleep_logs\', ...)` '
              'must not return. The legacy list path is read-only at this '
              'point (consumed by sync_health for back-compat) — the chat '
              'handler must NOT add new entries.');
    });

    test('_logSleep does NOT directly write the per-day sleep_log_ key either',
        () {
      // Defense in depth — every healthBox.put for sleep must go through
      // the WriteService, not happen inline.
      final hasDirectPerDayWrite =
          RegExp(r"healthBox\.put\(\s*'sleep_log_").hasMatch(src);
      expect(hasDirectPerDayWrite, isFalse,
          reason:
              'Chat handler must not bypass HealthWriteService for any '
              'sleep key.');
    });
  });
}
