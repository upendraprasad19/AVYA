// PRESENCE pins on the progress-photos free weekly cap migration (OI-348 Landing 3c),
// read from its DRAFT `test/sql/progress_photos_free_weekly_cap_draft.sql` until the
// founder's go turns it into supabase/migrations/NNN_progress_photos_free_weekly_cap.sql
// (then [_sqlPath] follows the file; supabase/migrations/CLAUDE.md, migration-190 rule).
//
// Each object is pinned WHOLE (comment- and whitespace-insensitive, through the readers
// of test/helpers/progress_photo_rule_sql.dart) against a hand-written literal, so a
// deliberate change has to edit the pin on purpose. Every protection is then MUTATED
// in-process (a [_mutants] entry rewrites the draft text the way a regression would
// re-enter) and each mutant must break at least one pin. The behavioural proof is the
// always-aborting live verify `test/sql/progress_photos_free_weekly_cap_live_verify.sql`,
// run with the founder's go.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/progress_photo_rule_sql.dart';

const String _draftPath = 'test/sql/progress_photos_free_weekly_cap_draft.sql';

/// The draft, or the applied migration once it exists (exactly one of them).
String get _sqlPath {
  final applied = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .map((f) => f.path.replaceAll(r'\', '/'))
      .where((p) => RegExp(r'/\d{3}_progress_photos_free_weekly_cap\.sql$').hasMatch(p))
      .toList();
  if (applied.isNotEmpty) return applied.single;
  return _draftPath;
}

const String _weekStart = r'''
CREATE OR REPLACE FUNCTION public.progress_photo_week_start(p_at timestamptz)
RETURNS timestamptz LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $fn$
  SELECT (date_trunc('week', p_at AT TIME ZONE 'Asia/Kolkata')) AT TIME ZONE 'Asia/Kolkata'
$fn$;''';

const String _objectCap = r'''
CREATE OR REPLACE FUNCTION public.enforce_progress_photo_object_cap()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
DECLARE
  v_owner uuid;
  v_caller uuid := auth.uid();
  v_role text := auth.role();
BEGIN
  BEGIN
    v_owner := ((storage.foldername(NEW.name))[1])::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    v_owner := NULL;
  END;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = '42501';
  END IF;
  IF v_role IN ('anon', 'authenticated') AND v_owner IS DISTINCT FROM v_caller THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.subscriptions s
    WHERE s.user_id = v_owner
      AND s.status = 'active'
      AND s.end_date > now()
  ) THEN
    RETURN NEW;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('progress_photo_cap:' || v_owner::text, 0));
  IF EXISTS (
    SELECT 1 FROM storage.objects o
    WHERE o.bucket_id = 'progress-photos'
      AND o.name LIKE v_owner::text || '/%'
      AND o.created_at >= public.progress_photo_week_start(now())
  ) THEN
    RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$fn$;''';

const String _rowCap = r'''
CREATE OR REPLACE FUNCTION public.enforce_progress_photo_pro()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
DECLARE
  v_week timestamptz;
BEGIN
  NEW.created_at := COALESCE(
    (SELECT o.created_at FROM storage.objects o
      WHERE o.bucket_id = 'progress-photos'
        AND o.name = NEW.storage_path
        AND o.name LIKE NEW.user_id::text || '/%'),
    now());
  IF EXISTS (
    SELECT 1 FROM public.subscriptions s
    WHERE s.user_id = NEW.user_id
      AND s.status = 'active'
      AND s.end_date > now()
  ) THEN
    RETURN NEW;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('progress_photo_cap:' || NEW.user_id::text, 0));
  v_week := public.progress_photo_week_start(NEW.created_at);
  IF EXISTS (
    SELECT 1 FROM public.progress_photos p
    WHERE p.user_id = NEW.user_id
      AND p.created_at >= v_week
      AND p.created_at < v_week + interval '168 hours'
  ) THEN
    RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$fn$;''';

const String _keepCreatedAt = r'''
CREATE OR REPLACE FUNCTION public.keep_progress_photo_created_at()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
BEGIN
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$fn$;''';

const String _objectTrigger = '''
CREATE TRIGGER trg_progress_photo_object_cap
  BEFORE INSERT ON storage.objects
  FOR EACH ROW
  WHEN (NEW.bucket_id = 'progress-photos')
  EXECUTE FUNCTION public.enforce_progress_photo_object_cap();''';

const String _keepTrigger = '''
CREATE TRIGGER trg_progress_photo_created_at_keep
  BEFORE UPDATE ON public.progress_photos
  FOR EACH ROW EXECUTE FUNCTION public.keep_progress_photo_created_at();''';

const String _ownFolderCheck =
    "bucket_id = 'progress-photos' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text";

/// The statement inventory, in order (function bodies masked).
const List<String> _inventory = [
  'PERFORM set_config',
  'CREATE OR REPLACE FUNCTION public.progress_photo_week_start',
  'REVOKE EXECUTE',
  'CREATE OR REPLACE FUNCTION public.enforce_progress_photo_object_cap',
  'REVOKE EXECUTE',
  'DROP TRIGGER IF EXISTS trg_progress_photo_object_cap ON storage.objects',
  'CREATE TRIGGER trg_progress_photo_object_cap ON storage.objects',
  'ALTER POLICY progress_photos_insert_own ON storage.objects',
  'CREATE POLICY progress_photos_insert_own ON storage.objects',
  'CREATE OR REPLACE FUNCTION public.enforce_progress_photo_pro',
  'REVOKE EXECUTE',
  'CREATE OR REPLACE FUNCTION public.keep_progress_photo_created_at',
  'REVOKE EXECUTE',
  'DROP TRIGGER IF EXISTS trg_progress_photo_created_at_keep ON public.progress_photos',
  'CREATE TRIGGER trg_progress_photo_created_at_keep ON public.progress_photos',
];

const List<String> _revokes = [
  'REVOKE EXECUTE ON FUNCTION public.progress_photo_week_start(timestamptz) FROM PUBLIC, anon, authenticated;',
  'REVOKE EXECUTE ON FUNCTION public.enforce_progress_photo_object_cap() FROM PUBLIC, anon, authenticated;',
  'REVOKE EXECUTE ON FUNCTION public.enforce_progress_photo_pro() FROM PUBLIC, anon, authenticated;',
  'REVOKE EXECUTE ON FUNCTION public.keep_progress_photo_created_at() FROM PUBLIC, anon, authenticated;',
];

/// Every pin, as (label, ok) over [sql]. A mutant must make at least one false.
List<(String, bool)> _pins(String sql) {
  final norm = normalizeSql(sql);
  final checks = storagePolicyWithChecks(sql, 'progress_photos_insert_own');
  return [
    ('week start', functionStatement(sql, 'progress_photo_week_start') == normalizeSql(_weekStart)),
    ('object cap', functionStatement(sql, 'enforce_progress_photo_object_cap') == normalizeSql(_objectCap)),
    ('row cap', functionStatement(sql, 'enforce_progress_photo_pro') == normalizeSql(_rowCap)),
    ('keep created_at', functionStatement(sql, 'keep_progress_photo_created_at') == normalizeSql(_keepCreatedAt)),
    ('object trigger', triggerStatement(sql, 'trg_progress_photo_object_cap') == normalizeSql(_objectTrigger)),
    ('keep trigger', triggerStatement(sql, 'trg_progress_photo_created_at_keep') == normalizeSql(_keepTrigger)),
    ('policy both branches own-folder only',
        checks.length == 2 && checks.every((c) => c == normalizeSql(_ownFolderCheck))),
    ('revokes', _revokes.map(normalizeSql).every(norm.contains)),
    ('inventory', _listEq(ddlInventory(sql), _inventory)),
    ('row trigger of 154 not re-created', triggerStatement(sql, 'trg_progress_photo_pro') == null),
    ('ascii', nonAsciiInExecutableText(sql).isEmpty),
  ];
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Regressions the pins must catch: (name, from, to). `from` must occur in the draft.
const List<(String, String, String)> _mutants = [
  ('WHEN clause dropped (every bucket calls the function)',
      "  FOR EACH ROW\n    WHEN (NEW.bucket_id = 'progress-photos')\n", '  FOR EACH ROW\n'),
  ('week bound dropped at the storage door (a lifetime cap)',
      "        AND o.created_at >= public.progress_photo_week_start(now())\n", ''),
  ('lock moved after the count', "    PERFORM pg_catalog.pg_advisory_xact_lock(\n      pg_catalog.hashtextextended('progress_photo_cap:' || v_owner::text, 0));\n", ''),
  ('storage door made INVOKER', 'RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS \$fn\$\n  DECLARE\n    v_owner uuid;',
      'RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS \$fn\$\n  DECLARE\n    v_owner uuid;'),
  ('PRO branch removed at the storage door',
      "      WHERE s.user_id = v_owner\n", "      WHERE s.user_id = v_owner AND false\n"),
  ('other-folder early return without the role test',
      "IF v_role IN ('anon', 'authenticated') AND v_owner IS DISTINCT FROM v_caller THEN",
      'IF v_caller IS NOT NULL AND v_owner <> v_caller THEN'),
  ('NULL owner allowed', "    IF v_owner IS NULL THEN\n      RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = '42501';\n    END IF;\n", ''),
  ('row created_at never taken from the object (always now())',
      "          AND o.name = NEW.storage_path\n", "          AND false\n"),
  ('row created_at may adopt another user\'s object', "          AND o.name LIKE NEW.user_id::text || '/%'),\n", '),\n'),
  ('row week upper bound dropped', "        AND p.created_at < v_week + interval '168 hours'\n", ''),
  ('UPDATE guard dropped', "    NEW.created_at := OLD.created_at;\n", ''),
  ('policy keeps the 154 subscription conjunct',
      "        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text\n      );\n  ELSE",
      "        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text\n        AND EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.user_id = (SELECT auth.uid()))\n      );\n  ELSE"),
  ('a revoke dropped', 'REVOKE EXECUTE ON FUNCTION public.enforce_progress_photo_object_cap() FROM PUBLIC, anon, authenticated;', ''),
  ('trg_progress_photo_pro re-created',
      '  -- (5) an UPDATE cannot move created_at\n',
      '  CREATE TRIGGER trg_progress_photo_pro BEFORE INSERT ON public.progress_photos FOR EACH ROW EXECUTE FUNCTION public.enforce_progress_photo_pro();\n  -- (5) an UPDATE cannot move created_at\n'),
  ('error code of the storage door changed to P0001',
      "      RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = '42501';\n    END IF;\n    RETURN NEW;",
      "      RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = 'P0001';\n    END IF;\n    RETURN NEW;"),
];

/// The commented rollback block, un-commented.
String _rollback(String sql) {
  final start = sql.indexOf(r'-- DO $rb$');
  final end = sql.indexOf(r'-- $rb$;', start);
  expect(start, greaterThan(0));
  expect(end, greaterThan(start));
  return sql
      .substring(start, end + r'-- $rb$;'.length)
      .split('\n')
      .map((l) => l.startsWith('--') ? l.substring(l.startsWith('-- ') ? 3 : 2) : l)
      .join('\n');
}

void main() {
  late String sql;
  late String sql154;

  setUpAll(() {
    sql = File(_sqlPath).readAsStringSync().replaceAll('\r\n', '\n');
    sql154 = File('supabase/migrations/154_progress_photos_pro_insert_rls_rule.sql')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
  });

  test('the four-tag header is present and says inline rollback', () {
    final head = sql.split('\n').take(4).toList();
    expect(head[0], startsWith('-- Intent: '));
    expect(head[1], startsWith('-- Destructive?: yes'));
    expect(head[2], startsWith('-- Rollback strategy: inline'));
    expect(head[3], startsWith('-- Linked diagnose-doc: f3c9a1'));
  });

  test('every pin holds on the file', () {
    final failed = [for (final (l, ok) in _pins(sql)) if (!ok) l];
    expect(failed, isEmpty, reason: 'pins failing: $failed');
  });

  group('every mutant breaks at least one pin', () {
    for (final (name, from, to) in _mutants) {
      test(name, () {
        expect(sql.contains(from), isTrue, reason: 'mutant "$name" did not apply');
        final mutated = sql.replaceFirst(from, to);
        final failed = [for (final (l, ok) in _pins(mutated)) if (!ok) l];
        expect(failed, isNotEmpty, reason: 'mutant "$name" survived every pin');
      });
    }
  });

  test('the rollback restores migration 154: its policy text and its function body', () {
    final rb = _rollback(sql);
    expect(storagePolicyWithChecks(rb, 'progress_photos_insert_own'),
        storagePolicyWithChecks(sql154, 'progress_photos_insert_own').take(1).toList());
    final fn154 = functionStatement(sql154, 'enforce_progress_photo_pro')!;
    final fnRb = functionStatement(rb, 'enforce_progress_photo_pro')!;
    expect(fnRb.replaceFirst(' SECURITY INVOKER', ''), fn154);
    expect(fnRb, contains('SECURITY INVOKER'),
        reason: 'a CREATE OR REPLACE keeps SECURITY DEFINER unless INVOKER is stated');
    final n = normalizeSql(rb);
    for (final s in [
      'DROP TRIGGER IF EXISTS trg_progress_photo_object_cap ON storage.objects;',
      'DROP FUNCTION IF EXISTS public.enforce_progress_photo_object_cap();',
      'DROP TRIGGER IF EXISTS trg_progress_photo_created_at_keep ON public.progress_photos;',
      'DROP FUNCTION IF EXISTS public.keep_progress_photo_created_at();',
      'GRANT EXECUTE ON FUNCTION public.enforce_progress_photo_pro() TO PUBLIC, anon, authenticated, service_role;',
      'DROP FUNCTION IF EXISTS public.progress_photo_week_start(timestamptz);',
    ]) {
      expect(n, contains(normalizeSql(s)));
    }
  });

  test('the client week start and the SQL week start name the same rule', () {
    final dart = File('lib/features/profile/repositories/progress_photo_repository.dart')
        .readAsStringSync();
    expect(dart.contains('mirror of the SQL `public.progress_photo_week_start(now())`'),
        isTrue);
    expect(normalizeSql(sql), contains("date_trunc('week',p_at AT TIME ZONE 'Asia/Kolkata')"));
  });
}
