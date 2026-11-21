// OI-479 (diagnose 5970aa) — migration-text pins for migration 177
// (`user_preferences.coach_chat_cleared_at` + `raise_coach_chat_cleared_at`).
// PRESENCE-class (source text): the behaviour is proved against a real
// Postgres by test/sql/coach_chat_cleared_at_local.sh (local docker, every
// clause below mutated there too) and on the client by
// test/sync/coach_chat_cleared_at_sync_test.dart. Comments are stripped first,
// so a comment that merely MENTIONS a clause can neither satisfy nor break it.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _path = 'supabase/migrations/177_coach_chat_cleared_at.sql';

String _code() => File(_path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((l) {
      final i = l.indexOf('--');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  late String code;
  setUpAll(() => code = _code());

  test('adds a NULLABLE timestamptz column', () {
    expect(
      code,
      contains(
        'ALTER TABLE public.user_preferences ADD COLUMN IF NOT EXISTS '
        'coach_chat_cleared_at timestamptz NULL;',
      ),
    );
  });

  test('the function is SECURITY INVOKER with a pinned search_path', () {
    expect(
      code,
      contains('raise_coach_chat_cleared_at(p_at timestamptz) RETURNS void'),
    );
    expect(code, contains('SECURITY INVOKER'));
    expect(code, isNot(contains('SECURITY DEFINER')));
    expect(code, contains('SET search_path = public, pg_temp'));
  });

  test('refuses a NULL p_at and a missing auth.uid()', () {
    expect(code, contains('IF p_at IS NULL THEN RAISE EXCEPTION'));
    expect(code, contains('IF auth.uid() IS NULL THEN RAISE EXCEPTION'));
  });

  test('monotonic and clamped on BOTH branches, keyed on auth.uid()', () {
    expect(code, contains('VALUES (auth.uid(), LEAST(p_at, now()), now())'));
    expect(code, contains('ON CONFLICT (user_id) DO UPDATE'));
    expect(
      code,
      contains('GREATEST(up.coach_chat_cleared_at, LEAST(p_at, now()))'),
    );
    expect(code, contains('updated_at = now()'));
  });

  test('ACL: no PUBLIC, no anon, only authenticated', () {
    const sig = 'public.raise_coach_chat_cleared_at(timestamptz)';
    expect(code, contains('REVOKE ALL ON FUNCTION $sig FROM PUBLIC;'));
    expect(code, contains('REVOKE EXECUTE ON FUNCTION $sig FROM anon;'));
    expect(code, contains('GRANT EXECUTE ON FUNCTION $sig TO authenticated;'));
  });
}
