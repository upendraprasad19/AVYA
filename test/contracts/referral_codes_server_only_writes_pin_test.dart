// Pin of migration 189 (referral_codes: no client write path; public.issue_referral_code() from
// migration 186 is the only writer; OI-348 B2 PR C, diagnose c2e8a4).
//
// The behaviour is proven live by test/sql/referral_codes_server_only_writes_live_verify.sql (the
// client role refused every write by privilege, own-row read kept, the function still writes) and by
// the migration's own self-check block. Gate 39 hashes the applied file. What neither sees is a
// LATER migration that quietly re-opens the hole (a new policy, a re-grant, a bulk grant on every
// table of schema public, a role membership or attribute for anon/authenticated, an owner change,
// row security forced or disabled, the same statements built as dynamic SQL): that is this file's
// tripwire. It fails CLOSED: any later statement that names referral_codes together with GRANT,
// POLICY, OWNER, ROW LEVEL SECURITY, RENAME or EXECUTE is flagged, so a harmless one (a grant to
// service_role, ENABLE ROW LEVEL SECURITY, a self-check message that says "policy") needs an edit
// here on purpose. REVOKE and DROP POLICY only narrow and are not flagged. A file named outside the
// known schemes is scanned too. The DDL list and the self-check's checks (one message per check)
// are pinned, so neither can change without this file changing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _name = '189_referral_codes_server_only_writes.sql';
const _path = 'supabase/migrations/$_name';

/// Removes `--` line comments and `/* */` block comments that are OUTSIDE single-quoted literals
/// (a `--` inside a string is text, and a comment is skipped before its apostrophes are seen).
String _stripSqlComments(String src) {
  final out = StringBuffer();
  var inQuote = false;
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    final next = i + 1 < src.length ? src[i + 1] : '';
    if (!inQuote && c == '-' && next == '-') {
      final nl = src.indexOf('\n', i);
      if (nl == -1) break;
      i = nl;
      continue;
    }
    if (!inQuote && c == '/' && next == '*') {
      final end = src.indexOf('*/', i + 2);
      if (end == -1) break;
      out.write(' ');
      i = end + 2;
      continue;
    }
    if (c == "'") inQuote = !inQuote;
    out.write(c);
    i++;
  }
  return out.toString();
}

/// Squashes whitespace OUTSIDE single-quoted literals only.
String _squash(String s) {
  final parts = s.split("'");
  for (var i = 0; i < parts.length; i += 2) {
    parts[i] = parts[i].replaceAll(RegExp(r'\s+'), ' ');
  }
  return parts.join("'").trim();
}

String _normalised(String src) => _squash(_stripSqlComments(src));

/// The top-level statements of the migration, in order, before its self-check block.
List<String> _ddl(String text) {
  final head = text.split(r'DO $selfcheck$').first;
  return [
    for (final s in head.split(';'))
      if (s.trim().isNotEmpty) '${s.trim()};',
  ];
}

/// One message per check of the self-check block, in order (the literal after `v_bad := v_bad ||`).
List<String> _selfCheckMessages(String text) => [
      for (final m in RegExp(r"v_bad := v_bad \|\| (?:format\()?'([^']*)'").allMatches(text)) m.group(1)!,
    ];

/// Files in supabase/migrations that predate the numeric scheme and are never scanned.
const _legacyNames = {'all_migrations_combined.sql'};

/// A migration file that could come after this one. 3-digit numbers >= 189 (any letter suffix);
/// timestamp names dated 2026-11-25 or later (an 8-14 digit prefix); any OTHER .sql name that is not
/// a known legacy file (fail closed). Never this file itself.
bool _isLaterMigration(String name) {
  if (name == _name || !name.endsWith('.sql') || _legacyNames.contains(name)) return false;
  final n = RegExp(r'^(\d{3})[a-z]?_').firstMatch(name);
  if (n != null) return int.parse(n.group(1)!) >= 189;
  final t = RegExp(r'^(\d{8,14})_').firstMatch(name);
  if (t != null) return int.parse(t.group(1)!.substring(0, 8)) >= 20261125;
  return true;
}

List<File> _laterMigrations() => [
      for (final e in Directory('supabase/migrations').listSync(recursive: true))
        if (e is File && _isLaterMigration(e.uri.pathSegments.last)) e,
    ];

final _ci = (String p) => RegExp(p, caseSensitive: false);

/// True when [sql] (normalised) could give a client role a write path on referral_codes again.
/// Per statement (split on `;`, so a statement inside a DO body is its own piece):
///   * it names referral_codes AND says GRANT, POLICY, OWNER, ROW LEVEL SECURITY, RENAME or EXECUTE
///     (a GRANT listing several tables, dynamic SQL in a string, a quoted name all count), unless it
///     starts with REVOKE or DROP POLICY (those only narrow);
///   * a GRANT ON ALL TABLES IN SCHEMA public;
///   * ALTER ROLE anon / authenticated (BYPASSRLS, a new password, ...);
///   * a role membership GRANT (no ON) to anon, authenticated or PUBLIC.
bool _reopensReferralCodes(String sql) {
  for (final raw in sql.split(';')) {
    final s = raw.trim();
    if (s.isEmpty) continue;
    if (_ci(r'^(REVOKE|DROP POLICY)\b').hasMatch(s)) continue;
    if (_ci(r'\breferral_codes\b').hasMatch(s) &&
        _ci(r'\b(GRANT|POLICY|OWNER|ROW LEVEL SECURITY|RENAME|EXECUTE)\b').hasMatch(s)) {
      return true;
    }
    if (_ci(r'\bGRANT\b.*\bON ALL TABLES IN SCHEMA "?public"?').hasMatch(s)) return true;
    if (_ci(r'\bALTER ROLE "?(anon|authenticated)"?\b').hasMatch(s)) return true;
    if (_ci(r'^GRANT\b(?!.*\bON\b).*\bTO\b.*\b(anon|authenticated|PUBLIC)\b').hasMatch(s)) return true;
  }
  return false;
}

void main() {
  late String text;
  setUpAll(() => text = _normalised(File(_path).readAsStringSync()));

  test('the four-tag header is present and links the diagnose doc', () {
    final head = File(_path).readAsLinesSync().take(4).toList();
    expect(head[0], startsWith('-- Intent: '));
    expect(head[1], startsWith('-- Destructive?: no'));
    expect(head[2], startsWith('-- Rollback strategy: inline'));
    expect(head[3], '-- Linked diagnose-doc: c2e8a4');
  });

  test('the DDL is exactly: drop the INSERT policy, revoke everything from clients, grant SELECT to authenticated', () {
    expect(_ddl(text), [
      "SET lock_timeout = '3s';",
      'DROP POLICY IF EXISTS "Users can insert own referral code" ON public.referral_codes;',
      'REVOKE ALL ON public.referral_codes FROM PUBLIC;',
      'REVOKE ALL ON public.referral_codes FROM anon, authenticated;',
      'GRANT SELECT ON public.referral_codes TO authenticated;',
    ]);
  });

  test('the self-check runs every check (one message each), raises on a bad state, and the file ends with RESET', () {
    expect(_selfCheckMessages(text), [
      ' anon holds %s;',
      ' anon holds a column privilege;',
      ' authenticated holds %s;',
      ' authenticated holds a column write privilege;',
      ' authenticated lost SELECT (restore reads its own row);',
      ' service_role lost %s;',
      ' postgres lost %s;',
      ' a write policy remains on referral_codes;',
      ' the own-row SELECT policy is missing or changed;',
      ' referral_codes is not (RLS on, not forced, owner postgres);',
      ' issue_referral_code is not SECURITY DEFINER owned by postgres;',
      ' authenticated cannot execute issue_referral_code;',
      ' anon can execute issue_referral_code;',
    ]);
    // the predicates a message alone does not pin (the SELECT policy's roles and condition, the RLS state)
    expect(text, contains("AND pp.roles = '{public}'::name[] AND pp.qual = '(( SELECT auth.uid() AS uid) = user_id)'"));
    expect(text, contains("AND c.relrowsecurity AND NOT c.relforcerowsecurity AND c.relowner = 'postgres'::regrole"));
    expect(text, contains(r'DO $selfcheck$'));
    expect(text, contains("RAISE EXCEPTION 'migration 189 self-check failed:%', v_bad;"));
    expect(text, endsWith(r'END $selfcheck$; RESET lock_timeout;'));
  });

  test('the rollback block is present (commented) and restores the policy and the default grants', () {
    final raw = File(_path).readAsStringSync();
    expect(raw, contains('--   CREATE POLICY "Users can insert own referral code"'));
    expect(raw,
        contains('--   GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.referral_codes TO anon, authenticated;'));
  });

  test("this migration's narrowing statements are not flagged; its one GRANT SELECT is", () {
    final ddl = _ddl(text);
    expect(ddl.where(_reopensReferralCodes), ['GRANT SELECT ON public.referral_codes TO authenticated;']);
  });

  test('no later migration re-opens a client write path on referral_codes without changing this test', () {
    final touching = [
      for (final f in _laterMigrations())
        if (_reopensReferralCodes(_normalised(f.readAsStringSync()))) f.path,
    ];
    expect(touching, isEmpty,
        reason: 'a later migration grants on referral_codes, adds or alters a policy on it, changes its '
            'owner or row security, grants on every table of schema public, or changes the anon / '
            'authenticated roles. Since migration 189 the only writer is public.issue_referral_code(); '
            'review it, then extend this test.');
  });

  group('the tripwire reads every spelling (controls)', () {
    for (final s in [
      'CREATE POLICY p ON public.referral_codes FOR INSERT WITH CHECK (true);',
      'create policy "x" on referral_codes for update using (true);',
      'CREATE POLICY p ON public.referral_codes FOR ALL USING (true);',
      'ALTER POLICY "Users can read own referral code" ON public.referral_codes USING (true);',
      'GRANT INSERT ON public.referral_codes TO authenticated;',
      'grant all on table "public"."referral_codes" to anon;',
      'GRANT UPDATE (code) ON referral_codes TO authenticated;',
      'GRANT INSERT ON public.referral_codes TO PUBLIC;',
      'GRANT INSERT ON TABLE public.referral_redemptions, public.referral_codes TO authenticated;',
      'GRANT ALL ON public.x, public.referral_codes TO anon;',
      'GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;',
      'ALTER TABLE public.referral_codes FORCE ROW LEVEL SECURITY;',
      'alter table if exists only referral_codes disable row level security;',
      'ALTER TABLE public.referral_codes NO FORCE ROW LEVEL SECURITY;',
      'ALTER TABLE public.referral_codes OWNER TO authenticated;',
      'ALTER TABLE public.referral_codes RENAME TO rc;',
      "DO \$\$ BEGIN EXECUTE format('GRANT INSERT ON %I TO anon', 'referral_codes'); END \$\$;",
      "DO \$\$ BEGIN EXECUTE 'GRANT INSERT ON public.' || 'referral_codes TO anon'; END \$\$;",
      'GRANT service_role TO authenticated;',
      'grant postgres to anon;',
      'ALTER ROLE authenticated BYPASSRLS;',
    ]) {
      test('flags: $s', () => expect(_reopensReferralCodes(_normalised(s)), isTrue));
    }
    for (final s in [
      'REVOKE ALL ON public.referral_codes FROM anon, authenticated;',
      'REVOKE GRANT OPTION FOR ALL ON public.referral_codes FROM authenticated;',
      'DROP POLICY IF EXISTS "Users can read own referral code" ON public.referral_codes;',
      'SELECT code FROM public.referral_codes WHERE user_id = x;',
      'INSERT INTO public.referral_codes (user_id, code) VALUES (x, y);',
      'GRANT SELECT ON public.referral_codes_archive TO authenticated;',
      'GRANT ALL ON ALL TABLES IN SCHEMA private TO service_role;',
      'GRANT ALL ON SCHEMA public TO anon;',
      'ALTER TABLE public.referral_redemptions ENABLE ROW LEVEL SECURITY;',
    ]) {
      test('does not flag: $s', () => expect(_reopensReferralCodes(_normalised(s)), isFalse));
    }
  });

  group('comments are stripped outside literals only (controls)', () {
    test('a -- inside a string does not hide the rest of the line', () {
      expect(_reopensReferralCodes(_normalised("SELECT '--'; GRANT INSERT ON public.referral_codes TO anon;")), isTrue);
    });
    test('a block comment is not a statement', () {
      expect(_reopensReferralCodes(_normalised('/* GRANT INSERT ON public.referral_codes TO anon; */ SELECT 1;')), isFalse);
    });
    test('a line comment is not a statement, and its apostrophe does not open a literal', () {
      expect(_normalised("-- the client's grant on referral_codes\nSELECT 1;"), 'SELECT 1;');
    });
  });

  group('the later-migration filter (controls)', () {
    for (final (name, later) in [
      ('189b_fix.sql', true),
      ('190_anything.sql', true),
      (_name, false),
      ('188_revenuecat_reconcile_cron.sql', false),
      ('20260328000001_video_renders.sql', false),
      ('20260330_create_promo_codes.sql', false),
      ('20261201093000_dashboard_edit.sql', true),
      ('all_migrations_combined.sql', false),
      ('hotfix.sql', true),
      ('README.md', false),
    ]) {
      test('$name -> $later', () => expect(_isLaterMigration(name), later));
    }
  });
}
