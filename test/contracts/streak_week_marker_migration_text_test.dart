// C2 (diagnose a3c8f1) — migration-text pins for raise_streak_week_marker.
// PRESENCE-class (source text); the behaviour is proved by
// test/sql/raise_streak_week_marker_verify.sql against live Postgres and by
// streak_week_marker_push_behavioral_test.dart on the client side. Comments
// are stripped before every absent/present pattern (a comment that merely
// MENTIONS a pattern must not satisfy or break it).
//
// Reads the minted migration `supabase/migrations/NNN_*raise_streak_week_marker*.sql`
// once it exists, else the plan-dir draft (the same text, before the number is
// minted), and fails if neither exists.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnTag = r'$function$';

String _load() {
  final minted = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('raise_streak_week_marker'))
      .toList();
  if (minted.isNotEmpty) return minted.single.readAsStringSync();
  final draft = File(
      'docs/plans/streak-freeze-restore-ownership-addendum-a.migration-draft-c2.sql');
  if (!draft.existsSync()) {
    throw StateError('neither the minted migration nor the draft exists');
  }
  return draft.readAsStringSync();
}

String _stripComments(String sql) => sql
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((l) {
      final i = l.indexOf('--');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The `CREATE OR REPLACE FUNCTION ... $function$;` text, comment-stripped.
String _function(String sql) {
  final code = _stripComments(sql);
  final start =
      code.indexOf('CREATE OR REPLACE FUNCTION public.raise_streak_week_marker(');
  if (start < 0) throw StateError('function not found');
  final open = code.indexOf('AS $_fnTag', start);
  final end = code.indexOf('$_fnTag;', open + 1);
  if (open < 0 || end <= open) throw StateError('function end not found');
  return code.substring(start, end + _fnTag.length + 1);
}

void main() {
  final raw = _load();
  final code = _stripComments(raw);
  final fn = _function(raw);

  group('function body', () {
    test('is SECURITY DEFINER with a pinned search_path and no parameter defaults',
        () {
      expect(fn, contains('SECURITY DEFINER'));
      expect(fn, contains('SET search_path = public'));
      expect(RegExp(r'p_week_key integer\s*=').hasMatch(fn), isFalse,
          reason: 'a DEFAULT would be an overload hazard (R9-4)');
      expect(fn, contains('RETURNS integer'));
    });

    test('carries the cross-account guard verbatim (C1)', () {
      expect(fn, contains('IF p_user_id IS NULL THEN'));
      expect(fn,
          contains('IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN'));
      expect(fn, contains('cross-account progress write blocked'));
    });

    test('a NULL or negative key RETURNs BEFORE the clamp (LEAST(NULL,x) is x)',
        () {
      expect(fn, contains('IF v_key IS NOT NULL AND v_key < 0 THEN'));
      final earlyReturn = fn.indexOf('RETURN v_out;');
      final least = fn.indexOf('LEAST(');
      expect(earlyReturn, greaterThan(0));
      expect(least, greaterThan(0));
      expect(earlyReturn, lessThan(least),
          reason: 'the early RETURN must textually precede the clamp');
      expect(_norm(fn),
          contains('IF v_key IS NULL THEN SELECT last_counted_week_key INTO v_out'));
    });

    test("clamps to THIS IST week's Monday, not today + 7", () {
      expect(fn,
          contains("v_today := (now() AT TIME ZONE 'Asia/Kolkata')::date;"));
      expect(
          fn,
          contains(
              "v_monday := (v_today - (EXTRACT(ISODOW FROM v_today)::int - 1)) - DATE '1970-01-01';"));
      expect(fn, contains('v_key := LEAST(v_key, v_monday);'));
      expect(fn.contains('+ 7'), isFalse);
    });

    test('is a conditional GREATEST and writes nothing else', () {
      expect(
          _norm(fn),
          contains(
              'UPDATE public.user_progress SET last_counted_week_key = v_key WHERE user_id = p_user_id AND (last_counted_week_key IS NULL OR last_counted_week_key < v_key)'));
      expect(fn.contains('updated_at'), isFalse,
          reason: 'does not touch updated_at');
      expect(fn.contains('streak_progress_version'), isFalse,
          reason: 'does not bump the optimistic-lock version');
      expect(fn.contains('INSERT'), isFalse, reason: 'UPDATE only, no INSERT');
    });
  });

  group('migration shell', () {
    test('uses CREATE OR REPLACE and an idempotent column add', () {
      expect(code,
          contains('CREATE OR REPLACE FUNCTION public.raise_streak_week_marker('));
      expect(code,
          contains('ADD COLUMN IF NOT EXISTS last_counted_week_key integer'));
      expect(code.contains('DROP '), isFalse,
          reason: 'nothing is dropped outside the commented reverse block');
    });

    test('lock_timeout is plain SET with a closing RESET, never SET LOCAL', () {
      expect(code, contains("SET lock_timeout = '3s';"));
      expect(code, contains('RESET lock_timeout;'));
      expect(code.contains('SET LOCAL'), isFalse);
    });

    test('ACL names every role and re-grants only authenticated + service_role',
        () {
      expect(
          _norm(code),
          contains(
              'REVOKE ALL ON FUNCTION public.raise_streak_week_marker(uuid, integer) FROM PUBLIC, anon, authenticated;'));
      expect(
          _norm(code),
          contains(
              'GRANT EXECUTE ON FUNCTION public.raise_streak_week_marker(uuid, integer) TO authenticated, service_role;'));
    });

    test('the closing assertion pins grantee set, arity, defaults, return type, anon',
        () {
      expect(code,
          contains("ARRAY['authenticated', 'postgres', 'service_role']::text[]"));
      expect(code, contains('v_nargs <> 2'));
      expect(code, contains('v_ndefaults <> 0'));
      expect(code, contains("v_rettype <> 'integer'::regtype"));
      expect(code, contains("has_function_privilege('anon'"));
      expect(code, contains('data_type'));
    });

    test('the reverse block is LITERAL and the column drop is flagged destructive',
        () {
      expect(raw,
          contains('-- DROP FUNCTION public.raise_streak_week_marker(uuid, integer);'));
      expect(raw, contains('-- DESTRUCTIVE'));
      expect(raw,
          contains('-- ALTER TABLE public.user_progress DROP COLUMN last_counted_week_key;'));
    });

    test('carries the four header tags and the linked diagnose id', () {
      expect(raw, contains('-- Intent:'));
      expect(raw, contains('-- Destructive?: no'));
      expect(raw, contains('-- Rollback strategy: inline'));
      expect(raw, contains('-- Linked diagnose-doc: a3c8f1'));
    });
  });

  test('the SQL harness embeds the SAME function body as the migration', () {
    final harness =
        File('test/sql/raise_streak_week_marker_verify.sql').readAsStringSync();
    final a = harness.indexOf('-- BEGIN-FUNCTION');
    final b = harness.indexOf('-- END-FUNCTION');
    expect(a, greaterThanOrEqualTo(0));
    expect(b, greaterThan(a));
    final embedded = _norm(_stripComments(harness.substring(a, b)));
    expect(embedded, _norm(fn));
  });
}
