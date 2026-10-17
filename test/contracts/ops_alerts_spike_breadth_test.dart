import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cron_job_body_reader.dart';

/// Pins migration 147's rewrite of `alert_client_errors_spike` (diagnose
/// d2c9f4, recurrence of 2026-06-06's f0b9d3 spike-filter-drift class) — the
/// STRUCTURAL assertions that `alert_thresholds_sync_test.dart` deliberately
/// stays out of scope of (it owns the yaml<->migration numeric-drift
/// contract only).
///
/// Reads the LIVE-AUTHORITATIVE `ops_alerts_30min` body via the shared
/// `latestCronJobBody` helper (same reader `alert_sql_job_failures_test.dart`
/// / `alert_cron_job_silent_test.dart` use for their own jobs) rather than a
/// single named migration file, so this test tracks whichever migration is
/// currently live-authoritative for the job — the exact class that let
/// migration 141 silently revert 140's fix while 140's own file stayed
/// correct and untouched (see alert_cron_failures_sync_test.dart's header).
///
/// MUTATION-PROVEN (§4.4 rule 21): the parenthesization test below is a
/// direct instance of the compound-boolean-connective mutation-target class
/// this same batch's B-pass found in migration 146 — an unparenthesized
/// `a OR b OR c AND NOT EXISTS(...)` parses (by SQL's AND-binds-tighter-than-
/// OR precedence) as `a OR b OR (c AND NOT EXISTS(...))`, silently disabling
/// dedup whenever the alert fires via the cnt or users arm alone. Deleting
/// the parens from the live migration text changes the exact substring this
/// test asserts, so the test reddens on that mutation by construction —
/// verified by removing the two parens locally and re-running (both fire
/// tests here go red; no other test in the suite notices, confirming this
/// is the ONLY protection against that specific regression class for this
/// job).
void main() {
  late final CronJobBody job;
  late final String body; // whitespace-normalised
  late final String migration143;

  setUpAll(() {
    job = latestCronJobBody('ops_alerts_30min');
    body = normSql(stripSqlLineComments(job.body));
    migration143 = stripSqlLineComments(
      File(
        'supabase/migrations/143_restore_alert_cron_failures_stuck_job_bound.sql',
      ).readAsStringSync(),
    );
  });

  test('job cadence unchanged at */30 (alter_job keeps schedule, jobid, '
      'and run history — this is a redefinition, not a re-creation)', () {
    expect(job.cadence, '*/30 * * * *');
  });

  test('counts DISTINCT (user, message-prefix, second) MOMENTS, not raw rows '
      '— the d2c9f4 recurrence-class defect', () {
    expect(
      body.contains(
        "COUNT(DISTINCT (coalesce(user_id::text, 'anon'), left(coalesce(error_message, ''), 200), date_trunc('second', created_at)))",
      ),
      isTrue,
      reason: 'a bare COUNT(*) or COUNT(DISTINCT user_id) would let one '
          "client's retry storm inflate the count, or collapse every "
          'distinct failure from one user into a single unit — this must be '
          'DISTINCT on the (user, message-prefix, second) triple',
    );
  });

  test('cnt is DELIBERATELY NOT scoped to exception-shaped rows, unlike the '
      'users/server_events arms — a documented, tracked asymmetry (OI-254), '
      'not an oversight', () {
    // cnt inherits the OUTER breadcrumb-reinclusion regex from 087/f0b9d3,
    // which deliberately re-includes some event/info-coded rows (op_types
    // matching fail|error|crash|...|_null) because logEvent mislabels
    // genuine failures error_code='event'. Adding the users/server_events
    // arms' `error_code NOT IN ('event','info')` guard to cnt too would
    // UNDO that 087 P0 fix (narrowing cnt back to exception-shaped-only
    // reopens the exact blind spot 087 closed). A B-pass review (finding 1,
    // docs/reviews/46c9b9ff3bde-review.md) found this asymmetry and it was
    // evaluated, not overlooked: the real fix is a CLIENT-side rename of
    // the offending op_type — tracked as OI-254, closed in B2a-2b:
    // lib/core/services/subscription_service.dart now emits
    // 'subscription_refresh_no_active_row' instead of the old
    // 'subscription_refresh_query_returned_null', which matched the
    // regex's `_null` alternative despite being a benign expected state
    // transition, not a bug. See
    // test/contracts/oi254_subscription_refresh_op_type_rename_test.dart.
    // This test still pins the STRUCTURAL DECISION (cnt stays unscoped by
    // design) so a future "fix" doesn't silently narrow cnt (or silently
    // widen users/server_events back open) without discussion — that
    // decision is independent of any one op_type's name.
    final cntDef =
        "COUNT(DISTINCT (coalesce(user_id::text, 'anon'), left(coalesce(error_message, ''), 200), date_trunc('second', created_at))) AS cnt,";
    expect(body.contains(cntDef), isTrue,
        reason: 'cnt column definition drifted from its expected form');
    expect(body.contains('$cntDef FILTER'), isFalse,
        reason: 'cnt must NOT carry a FILTER clause — if this now fails '
            'because cnt gained scoping, update OI-254 and this comment '
            'rather than silently deleting the assertion');
  });

  test('offline-noise exclusion: signature present, with an explicit '
      'never-offline override for real HTTP status codes and the four '
      'server-answered exception types', () {
    expect(
      body.contains(
        "'(failed host lookup|socketexception|connection (refused|reset|closed|abort)|network is unreachable|software caused connection abort|failed to fetch|load failed|xmlhttprequest error)'",
      ),
      isTrue,
      reason: 'offline signature regex missing or drifted',
    );
    expect(
      body.contains("'status(Code)?: ?[1-9][0-9]{2}'"),
      isTrue,
      reason: 'a real HTTP status code must NEVER be treated as offline '
          'noise even if the message also contains an offline-shaped '
          'substring',
    );
    expect(
      body.contains(
        "'(PostgrestException|FunctionsHttpException|FunctionsRelayException|AuthApiException)'",
      ),
      isTrue,
      reason: 'these four types mean the request reached a server and got '
          'an answer — never offline noise, exact types only',
    );
    // The override sits inside a `NOT (offline AND NOT (status OR type))`
    // shape — assert the negation wraps BOTH conjuncts, not just the
    // signature, or the override arm is dead code that never actually
    // rescues an overridden row.
    expect(
      body.contains(
        "AND NOT ( coalesce(error_message, '') ~* '(failed host lookup",
      ),
      isTrue,
      reason: 'the offline exclusion must wrap the WHOLE '
          '(signature AND NOT override) expression, not just the signature '
          'half',
    );
  });

  test('offline-caused client TIMEOUTS are NOT excluded (residual, '
      'deliberate — matches the client-side offlineSignature contract '
      'B2a-2b will add)', () {
    // Scoped to the OFFLINE SIGNATURE regex specifically — "timeout" is a
    // legitimate, unrelated substring of the pre-existing op_type
    // re-inclusion regex (`fail|error|...|timeout|denied|_null`, verbatim
    // from 143), so a whole-body check would false-fail against that regex
    // rather than testing anything about the offline signature.
    final sigStart = body.indexOf("'(failed host lookup");
    expect(sigStart, greaterThanOrEqualTo(0),
        reason: 'offline signature regex not found');
    final sigEnd = body.indexOf("'", sigStart + 1);
    final signature = body.substring(sigStart, sigEnd + 1);
    expect(signature.toLowerCase().contains('timeout'), isFalse,
        reason: 'the offline signature must not mention "timeout" at all — '
            'a stalled request without a clear connectivity signal stays '
            'counted as real, and undercounting is the worse failure mode '
            'here');
  });

  test('per-user breadth arm counts EXCEPTION-SHAPED rows only (excludes '
      "the routine 'event'-coded subscription_refresh_query_returned_null "
      'breadcrumb — otherwise this arm would trip on ordinary telemetry, '
      'not incidents)', () {
    expect(
      body.contains(
        "COUNT(DISTINCT coalesce(user_id::text, 'anon')) FILTER ( WHERE coalesce(error_code, '') NOT IN ('event', 'info') ) AS users",
      ),
      isTrue,
      reason: 'the users arm must FILTER to error_code NOT IN (event, info) '
          '— counting ALL real rows (including event-coded breadcrumbs) '
          'would have hit >=3 users routinely, per the R2 fix; live 36-day '
          'replay with THIS filter never exceeded 2 users/hour',
    );
  });

  test('server-error-class arm matches Postgres/Edge-Function failure '
      'signatures (PGRST00x, statement-timeout 57014, '
      'WORKER_RESOURCE_LIMIT, bare 5xx) among exception-shaped rows only',
      () {
    expect(
      body.contains(
        r"error_message ~* '(PGRST00[0-9]|57014|canceling statement due to statement timeout|WORKER_RESOURCE_LIMIT|status(Code)?: ?5[0-9]{2})'",
      ),
      isTrue,
    );
    // The server_events FILTER must ALSO require exception-shaped rows,
    // mirroring the users arm — otherwise a benign event-coded breadcrumb
    // whose message happens to mention a 5xx (e.g. relaying a server error
    // string for display) would count toward an infra-incident signal.
    //
    // Asserted as ONE exact contiguous literal of the whole column
    // definition, not a windowed substring around `AS server_events` — a
    // fixed-size lookback window is itself a mutation-target hazard (round-3
    // review, this batch): the `server_events` FILTER body is 328 chars and
    // a 400-char window bleeds 72 chars into the immediately-preceding
    // `users` arm's OWN identical `error_code NOT IN` guard, so mutating
    // away JUST the server_events arm's guard (leaving the users arm's copy
    // untouched) left this assertion green — reddening nothing, the exact
    // "green check whose input set is too wide" class. A whole-literal match
    // cannot bleed into a neighboring clause.
    expect(
      body.contains(
        "COUNT(DISTINCT (coalesce(user_id::text, 'anon'), left(coalesce(error_message, ''), 200), date_trunc('second', created_at))) FILTER ( WHERE coalesce(error_code, '') NOT IN ('event', 'info') AND error_message ~* '(PGRST00[0-9]|57014|canceling statement due to statement timeout|WORKER_RESOURCE_LIMIT|status(Code)?: ?5[0-9]{2})' ) AS server_events",
      ),
      isTrue,
      reason: 'server_events FILTER must also require exception-shaped rows '
          '(same guard as the users arm, in the SAME clause)',
    );
  });

  test('fire condition is PARENTHESIZED around the three-arm OR before '
      'ANDing with the dedup NOT EXISTS — compound-boolean-connective '
      'mutation target (this batch\'s own B-pass P1 class, migration 146)',
      () {
    expect(
      body.contains(
        'WHERE (c.cnt >= 40 OR c.users >= 3 OR c.server_events >= 3) AND NOT EXISTS (',
      ),
      isTrue,
      reason: "SQL's AND binds tighter than OR: an UNPARENTHESIZED "
          '`cnt>=40 OR users>=3 OR server_events>=3 AND NOT EXISTS(...)` '
          'parses as `cnt>=40 OR users>=3 OR (server_events>=3 AND NOT '
          'EXISTS(...))`, silently disabling dedup whenever the alert fires '
          'via the cnt or users arm alone',
    );
  });

  test('dedup is RANK-BASED (equal-or-higher severity suppresses), not a '
      'bare source+ack check — a lower severity must never mask a higher '
      'one, and severity_rank is computed ONCE and reused for both the '
      'emitted severity and the dedup comparison', () {
    expect(
      body.contains(
        "CASE a.severity WHEN 'critical' THEN 3 WHEN 'warn' THEN 2 ELSE 1 END >= c.severity_rank",
      ),
      isTrue,
      reason: 'dedup must compare severity RANK, not just source+ack, or a '
          'quiet info-level open alert would suppress a genuine critical '
          'firing 20 minutes later',
    );
    expect(
      body.contains(
        "CASE c.severity_rank WHEN 3 THEN 'critical' WHEN 2 THEN 'warn' ELSE 1 END",
      ),
      isFalse,
      reason: "sanity: the emitted-severity CASE keys on c.severity_rank "
          "with text arms ('critical'/'warn'), not integer 1 in the THEN "
          'position — a copy-paste from the dedup CASE would silently '
          'insert the wrong literal type',
    );
  });

  test('alert_edge_function_health sub-block is byte-identical to migration '
      '143 (out of scope for this fix)', () {
    final block143 = _extractInsertBlock(migration143, 'alert_edge_function_health');
    final block147 = _extractInsertBlock(stripSqlLineComments(job.body), 'alert_edge_function_health');
    expect(block147, block143,
        reason: 'alert_edge_function_health must be reproduced VERBATIM — '
            'any diff here means this migration accidentally touched code '
            'outside its stated scope');
  });

  test('alert_cron_failures sub-block is byte-identical to migration 143 '
      '(out of scope for this fix)', () {
    final block143 = _extractInsertBlock(migration143, 'alert_cron_failures');
    final block147 = _extractInsertBlock(stripSqlLineComments(job.body), 'alert_cron_failures');
    expect(block147, block143,
        reason: 'alert_cron_failures must be reproduced VERBATIM — any diff '
            'here means this migration accidentally touched code outside '
            'its stated scope');
  });
}

/// Extracts the `INSERT INTO public.alerts ... ;` statement whose SELECT
/// names [source] as its first literal, from raw (comment-stripped) SQL
/// text. Used only to compare the two out-of-scope sub-blocks byte-for-byte
/// between migration 143 and whichever migration is live-authoritative now.
String _extractInsertBlock(String sql, String source) {
  final marker = "'$source',";
  final markerIdx = sql.indexOf(marker);
  if (markerIdx < 0) {
    fail('could not find a block emitting source $source');
  }
  final insertStart = sql.lastIndexOf('INSERT INTO public.alerts', markerIdx);
  if (insertStart < 0) {
    fail('could not find the enclosing INSERT for source $source');
  }
  final end = sql.indexOf(';', markerIdx);
  if (end < 0) {
    fail('could not find the terminating ; for source $source\'s INSERT');
  }
  return sql.substring(insertStart, end + 1).trim();
}
