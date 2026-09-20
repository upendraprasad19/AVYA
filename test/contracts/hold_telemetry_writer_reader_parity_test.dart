// Writer/reader parity for the hold telemetry, ACROSS the language boundary.
//
// CLAUDE.md §4.1: "Writer/reader drift is the default suspect class." This
// contract is unusually exposed to it, because the writer and the reader are
// not even in the same language:
//
//   WRITER  lib/core/services/workout_schedule_write_service.dart
//           -> AppEventsService.log('hold_week_started', ...)
//           -> app_events_service.dart serializes {event: ..., ...metadata}
//              with Dart's Map.toString() into ai_coach_interactions.user_message
//
//   READER  supabase/migrations/120_...sql
//           -> user_message like '%hold_week_started%'
//
// Rename the event in Dart and NOTHING fails: the Dart tests still pass (they
// assert whatever name the writer now emits), the SQL is still valid, the
// migration still applies, and `holds_started_today` silently returns 0
// forever. A metric that reads 0 is indistinguishable from "no user has taken a
// hold yet" — which is the expected reading while enable_hold_weeks is OFF, so
// the failure is invisible precisely during the window it would be introduced.
//
// This test is the only thing that connects the two halves.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// The literal passed to AppEventsService.log inside holdWeek().
String _emittedEventName() {
  final src =
      File('lib/core/services/workout_schedule_write_service.dart').readAsStringSync();
  final m = RegExp(r"AppEventsService\.instance\.log\(\s*'([a-z0-9_]+)'")
      .firstMatch(src);
  return m?.group(1) ?? '';
}

File _migration() => File(
    'supabase/migrations/120_engagement_metric_channel_filter_and_hold_telemetry.sql');

String _sqlWithoutComments() {
  final sql = _migration().readAsStringSync();
  return sql
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
      .replaceAll(RegExp(r'--[^\n]*'), ' ');
}

void main() {
  test('the event name holdWeek EMITS is the one the SQL metric MATCHES', () {
    final event = _emittedEventName();
    expect(event, isNotEmpty,
        reason: 'no AppEventsService.instance.log(...) literal found in '
            'workout_schedule_write_service.dart — either the emit was removed '
            '(which hold_week_mechanic_behavioral_test.dart also catches) or it '
            'was refactored into a form this parity check can no longer read. '
            'Either way the two halves are no longer connected.');

    final sql = _sqlWithoutComments();
    expect(sql.contains("like '%$event%'"), isTrue,
        reason: 'migration 120 must match the SAME event string the writer '
            'emits. Writer emits "$event", and no `like \'%$event%\'` predicate '
            'was found in the migration (comments stripped, so a commented-out '
            'predicate cannot satisfy this).\n'
            'Rename one side without the other and holds_started_today / '
            '_7d / holders_total silently return 0 forever — which looks '
            'exactly like "nobody has held yet", the CORRECT reading while '
            'enable_hold_weeks is OFF. Nothing else in the repo would notice.');
  });

  test('all three hold_* metric columns key off that same event name', () {
    final event = _emittedEventName();
    final sql = _sqlWithoutComments();

    // One predicate per column; a column that keyed off a different string
    // would diverge from the other two without any single assertion failing.
    final occurrences = RegExp("like '%$event%'").allMatches(sql).length;
    expect(occurrences, 3,
        reason: 'expected exactly 3 `like \'%$event%\'` predicates — one each '
            'for holds_started_today, holds_started_7d and holders_total. '
            'Found $occurrences. Fewer means a column was left keyed to a stale '
            'string (it would read 0 while its siblings work, the hardest shape '
            'to spot); more means a new consumer was added without updating '
            'this expectation, which should be a deliberate edit.');
  });

  test('the app_event channel the writer uses is the one the metric filters on',
      () {
    final writer = File('lib/core/services/app_events_service.dart').readAsStringSync();
    final m = RegExp(r"_channel\s*=\s*'([a-z0-9_]+)'").firstMatch(writer);
    expect(m, isNotNull, reason: 'AppEventsService._channel literal not found');
    final channel = m!.group(1)!;

    final sql = _sqlWithoutComments();
    expect(sql.contains("channel = '$channel'"), isTrue,
        reason: 'AppEventsService writes channel=\'$channel\', so the hold '
            'metric must filter on that same value. A mismatch returns 0 rows '
            'with no error.');

    // The other half of the same seam: that channel must stay OUT of the
    // coach-message predicate, or the overcount this migration removed comes
    // straight back.
    expect(RegExp("channel in \\([^)]*'$channel'").hasMatch(sql), isFalse,
        reason: 'channel=\'$channel\' is analytics, not coach chat. If it ever '
            'appears in ai_messages_today\'s channel set, the 5.3x overcount '
            'this migration exists to remove is reintroduced.');
  });
}
