@Timeout(Duration(minutes: 2))
library;

// Hermes h6F2 (L40, diagnose e8c3a1) — behavioural half. A failed
// `ai_coach_interactions` upsert used to put the user's raw chat text into
// `client_errors`, because Postgres echoes the rejected row into the error's
// `details` and `_reportSyncFailure` posted `error.toString()` verbatim. This
// drives the REAL coach push against a stub PostgREST that fails the write
// with a real-shaped `Failing row contains (...)` body, then reads what
// actually reached `log-client-error`.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import 'sync_domain_skip_harness.dart';

const _secret = 'my knee hurts since the divorce';

Future<List<Map>> _reports(SyncHarness h, String opType) async {
  List<Map> matches() => h.server.requests
      .where((r) =>
          r.path == '/functions/v1/log-client-error' &&
          r.body is Map &&
          (r.body as Map)['op_type'] == opType)
      .map((r) => r.body as Map)
      .toList();
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (matches().isEmpty && DateTime.now().isBefore(deadline)) {
    await Future.delayed(const Duration(milliseconds: 20));
  }
  return matches();
}

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  test('a failed coach upsert reports the failure WITHOUT the chat text', () async {
    // Empty user_message skips the 5-minute dedup SELECT, so the push goes
    // straight to the orphan upsert that fails below.
    await HiveService.instance.coachBox.put('coach_1758000000000', {
      'user_message': '',
      'ai_response': _secret,
      'model_used': 'gemini',
    });
    h.server.failWritesTo.add('ai_coach_interactions');
    h.server.failBodies['ai_coach_interactions'] = {
      'message': 'new row for relation "ai_coach_interactions" violates '
          'check constraint "x"',
      'code': '23514',
      'details': 'Failing row contains (c0ffee, u1, in_app_orphan, , '
          '$_secret, gemini).',
      'hint': null,
    };

    await SyncService.instance.pushCoachInteractionsForSyncDomain();

    final reports = await _reports(h, 'upsert_coach_interaction');
    expect(reports, isNotEmpty,
        reason: 'the failure must still be reported — redaction must not '
            'swallow the report itself');
    final message = reports.first['error_message'] as String;
    expect(message, isNot(contains(_secret)),
        reason: 'the rejected row echoed by Postgres is user data');
    expect(message, contains('Failing row contains (<redacted>)'));
    expect(message, contains('23514'),
        reason: 'the SQLSTATE code is the diagnostic and must survive');
  });
}
