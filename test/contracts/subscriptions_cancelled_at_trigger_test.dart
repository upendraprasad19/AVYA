import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Pins migration 138 (B3, observation-batch-and-digest-redesign, 2026-09-21)
/// — subscriptions.cancelled_at + trg_set_subscription_cancelled_at.
///
/// This is a source-pin test, not a live-Postgres behavioral one: the
/// migration has NOT been applied to prod (a live apply needs its own
/// explicit founder authorization per CLAUDE.md §4.3, separate from this
/// batch's implementation work), so there is no live column/trigger yet to
/// exercise. Pins the DDL SHAPE that will implement the "self-maintaining,
/// fires only on a real transition INTO 'cancelled'" contract the digest
/// (B3's "Cancelled (manual)" figure) depends on.
void main() {
  late final String sql;

  setUpAll(() {
    final file =
        File('supabase/migrations/138_subscriptions_cancelled_at_trigger.sql');
    expect(file.existsSync(), isTrue, reason: '${file.path} must exist');
    sql = file.readAsStringSync();
  });

  test('adds cancelled_at as a nullable column (no backfill)', () {
    expect(
      sql.contains(
          'ALTER TABLE public.subscriptions ADD COLUMN IF NOT EXISTS cancelled_at timestamptz NULL'),
      isTrue,
      reason: 'must be nullable — the 3 pre-existing cancelled rows are '
          'deliberately NOT backfilled (founder-accepted)',
    );
  });

  test('trigger fires BEFORE UPDATE, not AFTER — must be able to mutate NEW',
      () {
    expect(sql.contains('BEFORE UPDATE ON public.subscriptions'), isTrue,
        reason: 'an AFTER trigger cannot mutate NEW.cancelled_at on the row '
            'being written');
  });

  test('stamps cancelled_at only on a REAL transition into cancelled, not '
      'a no-op re-save of the same status', () {
    expect(
      sql.contains(
          "IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN"),
      isTrue,
      reason: 'without the OLD.status guard, re-saving an already-cancelled '
          'row (e.g. an unrelated field edit) would re-stamp cancelled_at to '
          'now(), corrupting the "when did this actually cancel" figure the '
          "digest's yesterday-window query depends on",
    );
  });

  test('the guarded branch actually sets cancelled_at, and the function '
      'always returns NEW (never blocks the write)', () {
    final ifIdx = sql.indexOf(
        "IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN");
    expect(ifIdx, greaterThanOrEqualTo(0));
    final endIfIdx = sql.indexOf('END IF;', ifIdx);
    expect(endIfIdx, greaterThan(ifIdx));
    final guardedBody = sql.substring(ifIdx, endIfIdx);
    expect(guardedBody.contains('NEW.cancelled_at := now();'), isTrue);
    expect(sql.contains('RETURN NEW;'), isTrue,
        reason: 'a BEFORE UPDATE trigger that does not RETURN NEW silently '
            'cancels the write — this must never block a real subscription '
            'update');
  });

  test('lives in the private schema (PostgREST-invisible), not public', () {
    expect(
      sql.contains(
          'CREATE OR REPLACE FUNCTION private.set_subscription_cancelled_at()'),
      isTrue,
      reason: 'a public SECURITY DEFINER function is anon-executable by '
          'default on this project (see supabase/migrations/CLAUDE.md) — '
          'living in private dodges the class entirely, same as migration 133',
    );
  });

  test('idempotent re-apply: drops the trigger before recreating it', () {
    final dropIdx = sql
        .indexOf('DROP TRIGGER IF EXISTS trg_set_subscription_cancelled_at');
    final createIdx = sql.indexOf('CREATE TRIGGER trg_set_subscription_cancelled_at');
    expect(dropIdx, greaterThanOrEqualTo(0));
    expect(createIdx, greaterThan(dropIdx),
        reason: 'DROP must precede CREATE so replaying this migration on an '
            'already-applied database does not fail on a duplicate trigger');
  });
}
