// Whole-text pin of migration 186 (public.issue_referral_code(), OI-348 B2, diagnose c2e8a4).
//
// The live verify (test/sql/referral_code_issue_live_verify.sql) runs the function in ONE session,
// so some of its guards are invisible to it: the per-user advisory lock (two sessions), the
// byte-rejection rule (a biased draw still yields valid codes), the retry's constraint-name check
// (a code collision cannot be forced) and the final re-select (the upsert always leaves a row).
// This test pins the WHOLE migration text, comments stripped and whitespace squashed, against a
// hand-kept literal: any edit to the body, the security clauses or the privilege statements has
// to change this file on purpose. PRESENCE only; the behaviour is the live verify.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _path = 'supabase/migrations/186_issue_referral_code.sql';

String _stripSqlComments(String src) => src.split('\n').map((line) {
      final i = line.indexOf('--');
      return i == -1 ? line : line.substring(0, i);
    }).join('\n');

/// Squashes whitespace OUTSIDE single-quoted literals only: a changed space inside a message or
/// the alphabet is a change (odd segments of a split on `'` are literal contents; `''` is an
/// empty literal and stays one).
String _squash(String s) {
  final parts = s.split("'");
  for (var i = 0; i < parts.length; i += 2) {
    parts[i] = parts[i].replaceAll(RegExp(r'\s+'), ' ');
  }
  return parts.join("'").trim();
}

String _normalised(String src) => _squash(_stripSqlComments(src));

/// The migration as it must read, comments stripped, whitespace squashed.
const _expected = r"CREATE OR REPLACE FUNCTION public.issue_referral_code() "
    r"RETURNS TABLE (out_code text, out_expires_at timestamptz) LANGUAGE plpgsql "
    r"SECURITY DEFINER SET search_path = '' AS $$ DECLARE v_uid uuid := auth.uid(); "
    r"v_alphabet constant text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'; v_body text; "
    r"v_bytes bytea; v_byte int; v_i int; v_attempt int; v_constraint text; BEGIN "
    r"IF v_uid IS NULL THEN RAISE EXCEPTION 'issue_referral_code: not authenticated' "
    r"USING ERRCODE = '42501'; END IF; PERFORM pg_catalog.pg_advisory_xact_lock( "
    r"pg_catalog.hashtextextended('issue_referral_code:' || v_uid::text, 0)); "
    r"IF EXISTS ( SELECT 1 FROM public.referral_codes rc WHERE rc.user_id = v_uid "
    r"AND rc.expires_at > pg_catalog.now() ) THEN RETURN QUERY SELECT rc.code, "
    r"rc.expires_at FROM public.referral_codes rc WHERE rc.user_id = v_uid; RETURN; "
    r"END IF; FOR v_attempt IN 1..5 LOOP v_body := ''; "
    r"WHILE pg_catalog.length(v_body) < 8 LOOP "
    r"v_bytes := extensions.gen_random_bytes(16); FOR v_i IN 0..15 LOOP "
    r"EXIT WHEN pg_catalog.length(v_body) >= 8; "
    r"v_byte := pg_catalog.get_byte(v_bytes, v_i); IF v_byte < 252 THEN "
    r"v_body := v_body || pg_catalog.substr(v_alphabet, (v_byte % 36) + 1, 1); "
    r"END IF; END LOOP; END LOOP; BEGIN INSERT INTO public.referral_codes AS rc "
    r"(user_id, code, expires_at, created_at) VALUES (v_uid, 'AVYA-' || v_body, "
    r"pg_catalog.now() + interval '7 days', pg_catalog.now()) ON CONFLICT (user_id) "
    r"DO UPDATE SET code = EXCLUDED.code, expires_at = pg_catalog.now() + interval '7 days', "
    r"created_at = pg_catalog.now() WHERE rc.expires_at <= pg_catalog.now(); EXIT; "
    r"EXCEPTION WHEN unique_violation THEN "
    r"GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME; "
    r"IF v_constraint IS DISTINCT FROM 'referral_codes_code_key' THEN RAISE; END IF; "
    r"IF v_attempt = 5 THEN RAISE EXCEPTION "
    r"'issue_referral_code: no free code after 5 attempts'; END IF; END; END LOOP; "
    r"RETURN QUERY SELECT rc.code, rc.expires_at FROM public.referral_codes rc "
    r"WHERE rc.user_id = v_uid; IF NOT FOUND THEN RAISE EXCEPTION "
    r"'issue_referral_code: no row for the caller after the write'; END IF; END; $$; "
    r"REVOKE EXECUTE ON FUNCTION public.issue_referral_code() FROM PUBLIC, anon; "
    r"GRANT EXECUTE ON FUNCTION public.issue_referral_code() TO authenticated;";

/// A migration file that could come after this one: 3-digit number >= 186 with any letter suffix
/// (a manual follow-up is `186b_...`), never this file itself.
bool _isLaterMigration(String name) {
  if (name == '186_issue_referral_code.sql') return false;
  final m = RegExp(r'^(\d{3})[a-z]?_.*\.sql$').firstMatch(name);
  return m != null && int.parse(m.group(1)!) >= 186;
}

/// Every later migration file, nested folders included.
List<File> _laterMigrations() => [
      for (final e in Directory('supabase/migrations').listSync(recursive: true))
        if (e is File && _isLaterMigration(e.uri.pathSegments.last)) e,
    ];

/// True when [sql] (normalised) holds DDL or a privilege statement about the function, whatever
/// the spelling (schema or not, any case, FUNCTION / ROUTINE / PROCEDURE), or a bulk privilege
/// statement over every function of schema public. A plain call (`SELECT ... issue_referral_code()`)
/// is not.
bool _touchesFunction(String sql) => RegExp(
      r'(CREATE( OR REPLACE)?|ALTER|DROP|COMMENT ON) (FUNCTION|ROUTINE|PROCEDURE) (IF EXISTS )?("?public"?\.)?"?issue_referral_code"?'
      r'|(GRANT|REVOKE)[^;]*\bissue_referral_code\b'
      r'|(GRANT|REVOKE)[^;]* ON ALL (FUNCTIONS|ROUTINES) IN SCHEMA "?public"?',
      caseSensitive: false,
    ).hasMatch(sql);

void main() {
  late String text;
  setUpAll(() => text = _normalised(File(_path).readAsStringSync()));

  test('the whole migration equals the pinned text (body, security clauses, privileges, nothing else)', () {
    expect(text, _expected);
  });

  test('the four-tag header is present and links the diagnose doc', () {
    final head = File(_path).readAsLinesSync().take(4).toList();
    expect(head[0], startsWith('-- Intent: '));
    expect(head[1], startsWith('-- Destructive?: no'));
    expect(head[2], startsWith('-- Rollback strategy: inline'));
    expect(head[3], '-- Linked diagnose-doc: c2e8a4');
  });

  test('the privilege statements revoke anon explicitly (platform default grants) and grant only authenticated', () {
    final privileges = RegExp(r'(GRANT|REVOKE)[^;]*;', caseSensitive: false)
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toList();
    expect(privileges, [
      'REVOKE EXECUTE ON FUNCTION public.issue_referral_code() FROM PUBLIC, anon;',
      'GRANT EXECUTE ON FUNCTION public.issue_referral_code() TO authenticated;',
    ]);
  });

  test('no later migration redefines, alters, drops or re-grants the function without changing this test', () {
    final touching = [
      for (final f in _laterMigrations())
        if (_touchesFunction(_normalised(f.readAsStringSync()))) f.path,
    ];
    expect(touching, isEmpty,
        reason: 'a later migration touches public.issue_referral_code(): a CREATE OR REPLACE resets '
            'SECURITY DEFINER / search_path unless restated, and a signature change re-applies the '
            'platform default grants to anon. Review it, then extend this test.');
  });

  group('the tripwire reads every spelling (controls)', () {
    for (final s in [
      'CREATE OR REPLACE FUNCTION public.issue_referral_code() RETURNS void AS',
      'create function issue_referral_code() returns void as',
      'ALTER FUNCTION public.issue_referral_code() OWNER TO x;',
      'DROP FUNCTION IF EXISTS public.issue_referral_code();',
      'GRANT EXECUTE ON FUNCTION issue_referral_code() TO anon;',
      'grant all on function public.issue_referral_code() to anon;',
      'REVOKE ALL ON FUNCTION public.issue_referral_code() FROM authenticated;',
      'COMMENT ON FUNCTION public.issue_referral_code() IS \'x\';',
      'ALTER ROUTINE public.issue_referral_code() SECURITY INVOKER;',
      'DROP PROCEDURE IF EXISTS issue_referral_code;',
      'GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon;',
      'grant all on all routines in schema "public" to anon;',
    ]) {
      test('flags: $s', () => expect(_touchesFunction(s), isTrue));
    }
    test('a plain call is not DDL', () {
      expect(_touchesFunction('SELECT * FROM public.issue_referral_code();'), isFalse);
    });
    test('a bulk grant on another schema is not this function', () {
      expect(_touchesFunction('GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA private TO service_role;'), isFalse);
    });
  });

  group('the later-migration filter (controls)', () {
    for (final (name, later) in [
      ('186b_fix_issue_referral_code.sql', true),
      ('187_anything.sql', true),
      ('186_issue_referral_code.sql', false),
      ('185_units_pref.sql', false),
      ('20260328000001_video_renders.sql', false),
    ]) {
      test('$name -> $later', () => expect(_isLaterMigration(name), later));
    }
  });

  test('whitespace inside a literal is part of the pin; outside it is not', () {
    expect(_normalised("RAISE EXCEPTION 'no row  for';"), isNot(_normalised("RAISE EXCEPTION 'no row for';")));
    expect(_normalised("RAISE   EXCEPTION\n 'no row for';"), _normalised("RAISE EXCEPTION 'no row for';"));
    expect(_normalised("SET search_path = '' AS"), "SET search_path = '' AS");
  });
}
