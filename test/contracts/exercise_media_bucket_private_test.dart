// test/contracts/exercise_media_bucket_private_test.dart
//
// Batch M1 (diagnose b4e7a2, plan docs/plans/2026-10-27-library-batch-m1-media-data.md R7, R10 (d), R15). The
// founder's rule: only a person who has installed the app and logged in may reach the exercise animations, no one
// else. This file pins, in SOURCE, the migration that makes the bucket private and gives it its ONE read policy.
//
// WHAT THIS IS, AND IS NOT. A SOURCE-LEVEL test over SQL. It proves the migration TEXT is the frozen text and that
// no other migration can silently re-open the bucket by NAMING it. It cannot prove what the live database does:
// that is test/sql/exercise_media_bucket_live_verify.sql (the role probe) and its rehearsal-only twin
// test/sql/exercise_media_bucket_wrong_policies_rehearsal.sql, run in Task 8.4 and again after the upload.
//
// ITS BLIND SPOT (stated here, in docs/operations/EXERCISE_MEDIA.md and in the migration header): a later migration
// that does not name the bucket (an unscoped policy on storage.objects for anon, a GRANT, an UPDATE of
// storage.buckets without the id) is not caught by text. The guard for that class is the role probe, re-run after
// any storage-policy change.
//
// THE DRAFT. Gate 14 (scripts/check_migrations_applied.dart) fails any .sql in supabase/migrations/ that has no
// ledger entry, so the migration is drafted at docs/plans/library-batch-m/exercise_media_bucket.sql.draft until its
// live apply and then moved with the ledger entry in ONE commit (plan 8.5). Exactly ONE of the two paths must exist;
// the pins read whichever does (the promo-codes precedent, test/contracts/promo_codes_server_only_writer_to_reader_test.dart).
//
// HOW THE PINS ARE BUILT. WHOLE-expression equality against hand-written literals normalised by the shared helper
// (a clause-presence pin passes when an AND becomes an OR). `bucketRuleViolations` and `sqlFilesViolations` are PURE
// functions returning the ids of the pins a text violates: the real text returns none, and every in-process mutant
// (no file edit) returns the id it is expected to trip, so the pins are mutation-proven on every run.
//
// Groups: 1 the source; 2 the pins on the real text; 3 mutants of the migration; 4 the mirror (no other migration
// re-opens the bucket); 5 the two SQL files; 6 mutants of the SQL files; 7 the documents state the blind spot.
//
// Run: flutter test test/contracts/exercise_media_bucket_private_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/progress_photo_rule_sql.dart';

const String _draftPath = 'docs/plans/library-batch-m/exercise_media_bucket.sql.draft';
const String _migrationsDir = 'supabase/migrations';
const String _tablePath = 'scripts/data/library_media_v16.json';
const String _verifyPath = 'test/sql/exercise_media_bucket_live_verify.sql';
const String _rehearsalPath = 'test/sql/exercise_media_bucket_wrong_policies_rehearsal.sql';
const String _docPath = 'docs/operations/EXERCISE_MEDIA.md';
final RegExp _finalName = RegExp(r'^\d{3}[a-z]?_exercise_media_bucket\.sql$');
const String _policyName = 'exercise_media_authenticated_read';

// ── the expected literals (written by hand; whole statements) ─────────────────────────────────────────────

const String _usingExpr = '''
bucket_id = 'exercise-media'
  AND coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false''';

const String _policyStmt = '''
CREATE POLICY exercise_media_authenticated_read ON storage.objects
  FOR SELECT TO authenticated
  USING ($_usingExpr);''';

const String _tupleStmt = '''
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('exercise-media', 'exercise-media', false, 1500000, ARRAY['image/webp'])''';

const String _doUpdateStmt = '''
DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;''';

const String _selfCheckBucketClause = '''
id = 'exercise-media'
  AND public = false
  AND file_size_limit = 1500000
  AND allowed_mime_types = ARRAY['image/webp']''';

/// The whole migration, comment-stripped and normalised: the lock budget, the bucket, the policy, the three
/// self-checks, in this order. It carries no number: the number is only in the file name.
final String _expectedWhole = normalizeSql('''
DO \$mig\$
BEGIN
  PERFORM set_config('lock_timeout', '5s', true);
  $_tupleStmt
  ON CONFLICT (id) $_doUpdateStmt
  DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;
  $_policyStmt
  IF NOT EXISTS (
    SELECT 1 FROM storage.buckets
    WHERE $_selfCheckBucketClause
  ) THEN
    RAISE EXCEPTION 'exercise_media_bucket self-check: the bucket row is not private, 1500000 bytes, image/webp';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'exercise_media_authenticated_read'
      AND cmd = 'SELECT'
      AND roles = ARRAY['authenticated']::name[]
      AND qual LIKE '%exercise-media%'
      AND strpos(qual, 'is_anonymous') > 0
  ) THEN
    RAISE EXCEPTION 'exercise_media_bucket self-check: the read policy is missing or is not SELECT TO authenticated with the bucket and is_anonymous predicates';
  END IF;
  IF (
    SELECT count(*) FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND (coalesce(qual, '') LIKE '%exercise-media%' OR coalesce(with_check, '') LIKE '%exercise-media%')
  ) <> 1 THEN
    RAISE EXCEPTION 'exercise_media_bucket self-check: some other policy of storage.objects names exercise-media';
  END IF;
END
\$mig\$;
''');

final String _normTuple = normalizeSql(_tupleStmt);
final String _normDoUpdate = normalizeSql(_doUpdateStmt);
final String _normPolicy = normalizeSql(_policyStmt);
final String _normUsing = normalizeSql(_usingExpr);
final String _normSelfCheckBucket = normalizeSql(_selfCheckBucketClause);

// ── the pure checks over the migration text ───────────────────────────────────────────────────────────────

/// The ids of the pins [sql] (the migration text, comments included) violates. [tableMaxBytes] is the provenance
/// table's `_meta.webp_bytes_max` (R10 (d) second half: the bucket's limit equals it).
List<String> bucketRuleViolations(String sql, {required int tableMaxBytes}) {
  final v = <String>{};
  final norm = normalizeSql(sql);
  if (norm != _expectedWhole) v.add('body');

  // header: the four tags, no number of its own in any header line
  final lines = sql.split('\n');
  if (lines.length < 4 ||
      !lines[0].startsWith('-- Intent: ') ||
      !lines[1].startsWith('-- Destructive?: yes ') ||
      !lines[2].startsWith('-- Rollback strategy: inline ') ||
      lines[3] != '-- Linked diagnose-doc: b4e7a2') {
    v.add('header');
  }
  final headerLines = <String>[];
  for (final l in lines) {
    if (l.trim().isEmpty || l.startsWith('--')) {
      headerLines.add(l);
    } else {
      break;
    }
  }
  if (headerLines.any((l) => RegExp(r'\d{3}[a-z]?_exercise_media_bucket').hasMatch(l))) v.add('header_number');

  // the inline rollback: drop the policy, then the Storage API for the bucket
  final rbAt = sql.indexOf('Rollback (inline)');
  final rollback = rbAt < 0
      ? ''
      : sql.substring(rbAt).replaceAll(RegExp(r'^--', multiLine: true), '').replaceAll(RegExp(r'\s+'), ' ');
  if (!rollback.contains('DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;') ||
      !rollback.contains('upload_exercise_media.js --delete-bucket --execute --confirm-bucket exercise-media')) {
    v.add('rollback');
  }

  // the bucket row
  final tupleAt = norm.indexOf('INSERT INTO storage.buckets');
  final conflictAt = tupleAt < 0 ? -1 : norm.indexOf('ON CONFLICT', tupleAt);
  final tuple = (tupleAt < 0 || conflictAt < 0) ? '' : norm.substring(tupleAt, conflictAt);
  if (tuple != _normTuple) v.add('bucket_tuple');
  final tupleLimit = RegExp(r',(\d+),ARRAY').firstMatch(tuple)?.group(1);
  if (tupleLimit == null || int.parse(tupleLimit) != tableMaxBytes) v.add('limit_vs_table');
  final updAt = norm.indexOf('DO UPDATE SET');
  final updEnd = updAt < 0 ? -1 : norm.indexOf(';', updAt);
  final upd = (updAt < 0 || updEnd < 0) ? '' : norm.substring(updAt, updEnd + 1);
  if (upd != _normDoUpdate) v.add('do_update_set');
  if (RegExp(r'public\s*=\s*true', caseSensitive: false).hasMatch(norm)) v.add('public_true');

  // the policy: exactly one statement, whole, then its pieces
  final policyAt = norm.indexOf('CREATE POLICY $_policyName');
  final policyEnd = policyAt < 0 ? -1 : norm.indexOf(';', policyAt);
  final policy = (policyAt < 0 || policyEnd < 0) ? '' : norm.substring(policyAt, policyEnd + 1);
  if (policy != _normPolicy) v.add('policy_statement');
  if (!policy.contains(' FOR SELECT ')) v.add('policy_command');
  if (!policy.contains(' TO authenticated USING(')) v.add('policy_roles');
  final usingAt = policy.indexOf('USING(');
  final usingExpr = usingAt < 0 ? null : balancedAfter(policy, usingAt + 5);
  if (usingExpr == null || usingExpr != _normUsing) v.add('policy_using');
  final namingBucket = norm
      .split(';')
      .where((s) => RegExp(r'(CREATE|ALTER)\s+POLICY').hasMatch(s) && s.contains('exercise-media'))
      .length;
  if (namingBucket != 1 || RegExp(r'ALTER\s+POLICY').hasMatch(norm)) v.add('one_policy');

  // the self-check of the bucket row
  final scAt = norm.indexOf('SELECT 1 FROM storage.buckets WHERE ');
  final scEnd = scAt < 0 ? -1 : norm.indexOf(')THEN', scAt);
  final selfCheck = (scAt < 0 || scEnd < 0)
      ? ''
      : norm.substring(scAt + 'SELECT 1 FROM storage.buckets WHERE '.length, scEnd);
  if (selfCheck != _normSelfCheckBucket) v.add('self_check');
  if (!selfCheck.contains(' AND public = false')) v.add('self_check_public');
  final scLimit = RegExp(r'file_size_limit = (\d+)').firstMatch(selfCheck)?.group(1);
  if (scLimit == null || int.parse(scLimit) != tableMaxBytes) v.add('self_check_limit');
  return v.toList()..sort();
}

/// The ids of the pins the OTHER migrations ([others]: repo path to text, every migration except the one source)
/// violate. A file counts only when it names the bucket or the policy; the unscoped class is the blind spot.
List<String> mirrorViolations(Map<String, String> others) {
  final v = <String>{};
  for (final e in others.entries) {
    final text = stripSqlAllComments(e.value);
    final names = text.contains('exercise-media');
    for (final stmt in text.split(';')) {
      final s = stmt.replaceAll(RegExp(r'\s+'), ' ');
      if (stmt.contains(_policyName) && RegExp(r'(CREATE|ALTER|DROP)\s+POLICY', caseSensitive: false).hasMatch(s)) {
        v.add('mirror_policy_name');
      }
      if (!names || !stmt.contains('exercise-media')) continue;
      if (RegExp(r'(CREATE|ALTER)\s+POLICY', caseSensitive: false).hasMatch(s)) v.add('mirror_policy');
      if (RegExp(r'\bpublic\s*=\s*true\b', caseSensitive: false).hasMatch(s) ||
          RegExp(r"'exercise-media'\s*,\s*'exercise-media'\s*,\s*true", caseSensitive: false).hasMatch(s)) {
        v.add('mirror_public');
      }
      if (RegExp(r'(INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+storage\.buckets', caseSensitive: false).hasMatch(s)) {
        v.add('mirror_bucket_row');
      }
    }
  }
  return v.toList()..sort();
}

// ── the pure checks over the two SQL files ────────────────────────────────────────────────────────────────

String _between(String text, String begin, String end) {
  final a = text.indexOf(begin);
  final b = text.indexOf(end);
  if (a < 0 || b < 0 || b < a) return '';
  final from = text.indexOf('\n', a);
  return text.substring(from + 1, text.lastIndexOf('\n', b));
}

int _count(String text, String needle) => needle.isEmpty ? 0 : text.split(needle).length - 1;

/// The text of the migration's DO block body (between its BEGIN and END), comments included.
String migrationBody(String migration) {
  final m = RegExp(r'DO \$mig\$\s*BEGIN([\s\S]*)\nEND\s*\$mig\$;').firstMatch(migration);
  return m == null ? '' : m.group(1)!;
}

const String _expectedArrays = '''
v_names text[] := ARRAY['baseline', 'v1_to_public', 'v2_no_is_anonymous', 'v3_unscoped_bucket', 'v4_for_all', 'v5_buckets_update_policy'];
v_expected text[] := ARRAY['0/1/0/0', '1/1/0/0', '0/1/1/0', '0/1/0/1', '0/1/0/0', '0/1/0/0'];
v_expected_w text[] := ARRAY['refused/0/0/0', 'refused/0/0/0', 'refused/0/0/0', 'refused/0/0/0', 'inserted/1/1/0', 'refused/0/0/0'];
v_expected_c text[] := ARRAY[
  'SELECT|{authenticated}|true|true|none|none',
  'SELECT|{public}|true|true|exercise_media_authenticated_read|none',
  'SELECT|{authenticated}|true|false|none|none',
  'SELECT|{authenticated}|false|true|none|none',
  'ALL|{authenticated}|true|true|none|none',
  'SELECT|{authenticated}|true|true|none|buckets.exercise_media_buckets_wrong'];''';

/// The grant-dependent expectation of variant 5 and the composition of the catalog reading.
const List<String> _expectedFlow = <String>[
  "IF v_bucket_upd_priv THEN v_expected_w[6] := 'refused/0/0/open'; END IF;",
  '''
v_cat := coalesce(v_policy_cmd, 'absent') || '|' || coalesce(v_policy_roles, 'absent') || '|'
  || coalesce(v_qual_bucket, 'absent') || '|' || coalesce(v_qual_anon, 'absent') || '|'
  || v_anon_public || '|' || v_unscoped_write;''',
  '''
v_flag := CASE WHEN v_actual = v_expected[v_i] AND v_actual_w = v_expected_w[v_i] AND v_cat = v_expected_c[v_i] AND v_anon_priv
               THEN 'OK' ELSE 'STOP' END;''',
  '''
v_flag := CASE WHEN v_actual = v_expected[v_i] AND v_actual_w = v_expected_w[v_i] AND v_cat = v_expected_c[v_i]
               THEN 'RED' ELSE 'STOP' END;''',
];

/// The probe's refusal messages are matched against the specific table, and the underscored words are looked up with
/// strpos (a LIKE underscore is a wildcard). Each needle must be in the probe or the catalog block of BOTH files.
const List<String> _expectedMessages = <String>[
  "LIKE 'permission denied for table objects%'",
  "LIKE 'new row violates row-level security policy for table \"objects\"%'",
  "LIKE 'permission denied for table buckets%'",
  "strpos(qual, 'is_anonymous') > 0",
  "strpos(qual, 'bucket_id') = 0",
  "tablename IN ('objects', 'buckets')",
  // The bucket leg has NO WHERE and sets a constant (a WHERE on id would also need a SELECT-visible row, so an UPDATE-only
  // policy on storage.buckets would hide from it), and it reads any row as 'open'.
  'UPDATE storage.buckets SET public = true;',
  "CASE WHEN v_n = 0 THEN '0' ELSE 'open' END",
  // The unscoped-write check also flags a write policy that names exercise-media or negates the bucket test.
  "strpos(coalesce(qual, '') || coalesce(with_check, ''), 'exercise-media') > 0",
  "~ '(<>|!=|NOT )'",
];

const List<String> _expectedVariants = <String>[
  '''
IF v_i = 2 THEN
  DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;
  CREATE POLICY exercise_media_authenticated_read ON storage.objects
    FOR SELECT TO public
    USING (
      bucket_id = 'exercise-media'
      AND coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
    );''',
  '''
ELSIF v_i = 3 THEN
  DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;
  CREATE POLICY exercise_media_authenticated_read ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'exercise-media');''',
  '''
ELSIF v_i = 4 THEN
  DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;
  CREATE POLICY exercise_media_authenticated_read ON storage.objects
    FOR SELECT TO authenticated
    USING (coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false);''',
  '''
ELSIF v_i = 5 THEN
  DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;
  CREATE POLICY exercise_media_authenticated_read ON storage.objects
    FOR ALL TO authenticated
    USING (
      bucket_id = 'exercise-media'
      AND coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
    );''',
  '''
ELSIF v_i = 6 THEN
  CREATE POLICY exercise_media_buckets_wrong ON storage.buckets
    FOR UPDATE TO authenticated
    USING (true);
END IF;''',
];

const String _expectedVerdict1 = '''
WHEN v_anon = '0' AND v_auth = '1' AND v_anon_session = '0' AND v_other = '0'
 AND v_write_insert = 'refused' AND v_write_update = '0' AND v_write_delete = '0' AND v_write_bucket = '0'
 AND v_anon_priv
 AND v_bucket_public = 'false' AND v_bucket_limit = '1500000' AND v_bucket_mime = '{image/webp}'
 AND v_policy_cmd = 'SELECT' AND v_policy_roles = '{authenticated}'
 AND v_qual_bucket = 'true' AND v_qual_anon = 'true'
 AND v_anon_public = 'none' AND v_unscoped_write = 'none'
THEN 'PASS' ELSE 'FAIL' END;''';

const String _expectedGuard2 = '''
BEGIN
IF EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'exercise-media') THEN
  RAISE EXCEPTION 'REHEARSAL_ONLY: the exercise-media bucket already exists; this file must not run after the apply';
END IF;''';

const String _expectedVerdict2 = "v_stop = 0 AND v_red = 5 AND v_anon_priv THEN 'PASS' ELSE 'FAIL' END";

/// The ids of the pins the two SQL files [f1] (live verify) and [f2] (wrong-policies rehearsal) violate against
/// the [migration] text.
List<String> sqlFilesViolations({required String f1, required String f2, required String migration}) {
  final v = <String>{};
  final n1 = normalizeSql(f1);
  final n2 = normalizeSql(f2);

  if (_count(f1, '-- PROBE-BEGIN') != 1 ||
      _count(f1, '-- PROBE-END') != 1 ||
      _count(f1, '-- PRELUDE-INSERT-POINT') != 1 ||
      _count(f1, '-- CATALOG-BEGIN') != 1 ||
      _count(f1, '-- CATALOG-END') != 1 ||
      _count(f2, '-- CATALOG-BEGIN') != 1 ||
      _count(f2, '-- CATALOG-END') != 1 ||
      _count(f2, '-- PROBE-BEGIN') != 1 ||
      _count(f2, '-- PROBE-END') != 1 ||
      _count(f2, '-- PRELUDE-BEGIN') != 1 ||
      _count(f2, '-- PRELUDE-END') != 1) {
    v.add('markers');
  }
  final probe1 = normalizeSql(_between(f1, '-- PROBE-BEGIN', '-- PROBE-END'));
  final probe2 = normalizeSql(_between(f2, '-- PROBE-BEGIN', '-- PROBE-END'));
  if (probe1.isEmpty || probe1 != probe2) v.add('probe_equal');
  final whereLeg = normalizeSql('UPDATE storage.buckets SET public = true WHERE');
  if (probe1.contains(whereLeg) || probe2.contains(whereLeg)) v.add('bucket_leg_where');
  final catalog1 = normalizeSql(_between(f1, '-- CATALOG-BEGIN', '-- CATALOG-END'));
  final catalog2 = normalizeSql(_between(f2, '-- CATALOG-BEGIN', '-- CATALOG-END'));
  if (catalog1.isEmpty || catalog1 != catalog2) v.add('catalog_equal');
  for (final needle in _expectedMessages) {
    if (!probe1.contains(normalizeSql(needle)) && !catalog1.contains(normalizeSql(needle))) v.add('messages');
    if (!probe2.contains(normalizeSql(needle)) && !catalog2.contains(normalizeSql(needle))) v.add('messages');
  }
  final underscoreLike = RegExp(r"LIKE\s*'%(is_anonymous|bucket_id)%'", caseSensitive: false);
  if (underscoreLike.hasMatch(executableText(f1)) || underscoreLike.hasMatch(executableText(f2))) {
    v.add('no_underscore_like');
  }
  final prelude = normalizeSql(_between(f2, '-- PRELUDE-BEGIN', '-- PRELUDE-END'));
  final body = normalizeSql(migrationBody(migration));
  if (body.isEmpty || prelude != body) v.add('prelude_equal');

  final ddl = RegExp(r'\b(CREATE|ALTER|DROP|GRANT|REVOKE|TRUNCATE)\b');
  if (ddl.hasMatch(executableText(f1))) v.add('f1_no_ddl');
  final txn = RegExp(r'^\s*(BEGIN|START\s+TRANSACTION|COMMIT|ROLLBACK)\s*;', multiLine: true, caseSensitive: false);
  if (txn.hasMatch(stripSqlAllComments(f1)) || txn.hasMatch(stripSqlAllComments(f2))) v.add('no_txn_control');
  if (_count(n1, "RAISE EXCEPTION 'VERIFY_RESULTS%'") != 1 || _count(n2, "RAISE EXCEPTION 'VERIFY_RESULTS%'") != 1) {
    v.add('verify_results_once');
  }

  if (!n1.contains(normalizeSql(_expectedVerdict1))) v.add('f1_verdict');
  if (!n2.contains(normalizeSql(_expectedGuard2))) v.add('f2_guard');
  if (!n2.contains(normalizeSql(_expectedArrays))) v.add('f2_expected');
  if (!n2.contains(normalizeSql(_expectedVerdict2)) || !n2.contains('FOR v_i IN 1..6 LOOP')) v.add('f2_verdict');
  for (final stmt in _expectedFlow) {
    if (!n2.contains(normalizeSql(stmt))) v.add('f2_flow');
  }
  for (final stmt in _expectedVariants) {
    if (!n2.contains(normalizeSql(stmt))) v.add('f2_variants');
  }
  return v.toList()..sort();
}

// ── the sources ────────────────────────────────────────────────────────────────────────────────────────────

List<String> _finalPaths() {
  final dir = Directory(_migrationsDir);
  if (!dir.existsSync()) return const <String>[];
  return dir
      .listSync()
      .whereType<File>()
      .map((f) => f.path.replaceAll('\\', '/'))
      .where((p) => _finalName.hasMatch(p.substring(p.lastIndexOf('/') + 1)))
      .toList()
    ..sort();
}

/// The paths that hold the migration text: the draft and any final file (exactly one must exist).
List<String> _presentSources() => <String>[
      ..._finalPaths(),
      if (File(_draftPath).existsSync()) _draftPath,
    ];

/// The migration's path and text, from whichever of the draft and the final file exists; an empty text when
/// the count is not exactly one (the first test of group 1 reports that, so the load itself never throws).
({String path, String text}) _source() {
  final present = _presentSources();
  if (present.length != 1) return (path: '', text: '');
  return (path: present.single, text: File(present.single).readAsStringSync());
}

int _tableMax() {
  final table = jsonDecode(File(_tablePath).readAsStringSync()) as Map<String, dynamic>;
  return (table['_meta'] as Map<String, dynamic>)['webp_bytes_max'] as int;
}

String _replaceOnce(String text, String from, String to) {
  expect(text.contains(from), isTrue, reason: 'the mutant target is not in the text: $from');
  return text.replaceFirst(from, to);
}

void main() {
  final src = _source();
  final migration = src.text;
  final max = _tableMax();

  group('1 the source', () {
    test('exactly one of the draft and the final file exists, and the table limit is the contract limit', () {
      expect(_presentSources().length, 1,
          reason: 'exactly one of the draft ($_draftPath) and a final $_migrationsDir/NNN_exercise_media_bucket.sql '
              'must exist, found ${_presentSources()}');
      expect(src.path == _draftPath || RegExp(r'^supabase/migrations/\d{3}[a-z]?_exercise_media_bucket\.sql$').hasMatch(src.path),
          isTrue);
      expect(max, 1500000, reason: 'the bucket limit literal of the migration is 1,500,000 (R7)');
    });

    test('the migration carries no number in any header line (draft and final are byte-identical)', () {
      expect(bucketRuleViolations(migration, tableMaxBytes: max), isNot(contains('header_number')));
    });
  });

  group('2 the pins on the real text', () {
    test('the real migration violates no pin', () {
      expect(bucketRuleViolations(migration, tableMaxBytes: max), isEmpty);
    });

    test('the bucket is private, webp only, and the limit is the table maximum', () {
      final norm = normalizeSql(migration);
      expect(norm, contains(_normTuple));
      expect(RegExp(r'public\s*=\s*true', caseSensitive: false).hasMatch(norm), isFalse);
    });

    test('there is exactly one policy, for SELECT TO authenticated, naming the bucket and the anonymous clause', () {
      final norm = normalizeSql(migration);
      expect(_count(norm, 'CREATE POLICY'), 1);
      expect(norm, contains(_normPolicy));
      expect(norm, isNot(contains('TO anon')));
      expect(norm, isNot(contains('TO public')));
      expect(RegExp(r'FOR\s+(INSERT|UPDATE|DELETE|ALL)', caseSensitive: false).hasMatch(norm), isFalse);
    });
  });

  group('3 mutants of the migration (in-process, no file edit): each trips the pin written for it', () {
    // (name, mutate, ids that must appear)
    final mutants = <(String, String Function(String), List<String>)>[
      ('bucket made public in the tuple', (s) => _replaceOnce(s, "'exercise-media', 'exercise-media', false", "'exercise-media', 'exercise-media', true"), ['bucket_tuple']),
      ('limit changed in the tuple only', (s) => _replaceOnce(s, "false, 1500000, ARRAY", "false, 2500000, ARRAY"), ['bucket_tuple', 'limit_vs_table']),
      ('limit changed in the self-check only', (s) => _replaceOnce(s, 'AND file_size_limit = 1500000', 'AND file_size_limit = 2500000'), ['self_check_limit']),
      ('mime list widened', (s) => _replaceOnce(s, "ARRAY['image/webp'])\n  ON CONFLICT", "ARRAY['image/webp', 'image/png'])\n  ON CONFLICT"), ['bucket_tuple']),
      ('DO UPDATE list missing public', (s) => _replaceOnce(s, '    public = EXCLUDED.public,\n', ''), ['do_update_set']),
      ('self-check public check removed', (s) => _replaceOnce(s, '      AND public = false\n', ''), ['self_check_public']),
      ('self-check public check inverted', (s) => _replaceOnce(s, '      AND public = false\n', '      AND public = true\n'), ['self_check_public']),
      ('policy TO public', (s) => _replaceOnce(s, 'FOR SELECT TO authenticated\n    USING', 'FOR SELECT TO public\n    USING'), ['policy_roles', 'policy_statement']),
      ('policy TO authenticated, anon', (s) => _replaceOnce(s, 'FOR SELECT TO authenticated\n    USING', 'FOR SELECT TO authenticated, anon\n    USING'), ['policy_roles', 'policy_statement']),
      ('policy FOR ALL', (s) => _replaceOnce(s, 'FOR SELECT TO authenticated\n    USING', 'FOR ALL TO authenticated\n    USING'), ['policy_command', 'policy_statement']),
      ('bucket scope clause removed', (s) => _replaceOnce(s, "      bucket_id = 'exercise-media'\n      AND coalesce(", '      coalesce('), ['policy_using', 'policy_statement']),
      ('AND turned into OR', (s) => _replaceOnce(s, "      AND coalesce(((select auth.jwt())", "      OR coalesce(((select auth.jwt())"), ['policy_using', 'policy_statement']),
      ('is_anonymous clause dropped', (s) => _replaceOnce(s, "\n      AND coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false\n    );", '\n    );'), ['policy_using', 'policy_statement']),
      ('select wrap removed', (s) => _replaceOnce(s, 'coalesce(((select auth.jwt()) ->>', 'coalesce((auth.jwt() ->>'), ['policy_using', 'policy_statement']),
      ('a second policy naming the bucket', (s) => _replaceOnce(s, '  -- (3) read-back self-check', "  CREATE POLICY exercise_media_extra ON storage.objects FOR SELECT TO anon USING (bucket_id = 'exercise-media');\n\n  -- (3) read-back self-check"), ['one_policy', 'body']),
      ('an ALTER POLICY in the body', (s) => _replaceOnce(s, '  -- (3) read-back self-check', '  ALTER POLICY exercise_media_authenticated_read ON storage.objects TO public;\n\n  -- (3) read-back self-check'), ['one_policy', 'body']),
      ('destructive tag flipped', (s) => _replaceOnce(s, '-- Destructive?: yes ', '-- Destructive?: no '), ['header']),
      ('diagnose id changed', (s) => _replaceOnce(s, '-- Linked diagnose-doc: b4e7a2', '-- Linked diagnose-doc: n/a'), ['header']),
      ('a number added to a header line', (s) => _replaceOnce(s, '-- exercise_media_bucket\n', '-- 170_exercise_media_bucket.sql\n'), ['header_number']),
      ('rollback loses the Storage API step', (s) => _replaceOnce(s, 'node scripts/upload_exercise_media.js --delete-bucket', 'node scripts/upload_exercise_media.js --delete-nothing'), ['rollback']),
      ('rollback loses the policy drop', (s) => _replaceOnce(s, '--        DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;', '--        SELECT 1;'), ['rollback']),
      ('lock budget removed', (s) => _replaceOnce(s, "  PERFORM set_config('lock_timeout', '5s', true);\n", ''), ['body']),
      ('one extra statement', (s) => _replaceOnce(s, '  -- (3) read-back self-check', '  PERFORM 1;\n\n  -- (3) read-back self-check'), ['body']),
    ];
    for (final (name, mutate, ids) in mutants) {
      test(name, () {
        final got = bucketRuleViolations(mutate(migration), tableMaxBytes: max);
        for (final id in ids) {
          expect(got, contains(id), reason: 'mutant "$name" must trip $id, got $got');
        }
      });
    }

    test('a table maximum that differs from the literal is a violation (R10 (d) second half)', () {
      expect(bucketRuleViolations(migration, tableMaxBytes: 1400000), containsAll(['limit_vs_table', 'self_check_limit']));
    });

    test('the pins are real: a text with the policy absent trips them rather than passing vacuously', () {
      final got = bucketRuleViolations('-- Intent: x\nSELECT 1;\n', tableMaxBytes: max);
      expect(got, containsAll(['body', 'header', 'rollback', 'bucket_tuple', 'policy_statement', 'one_policy']));
    });
  });

  group('4 the mirror: no other migration re-opens the bucket or touches its policy', () {
    Map<String, String> others() {
      final out = <String, String>{};
      for (final f in Directory(_migrationsDir).listSync().whereType<File>()) {
        final p = f.path.replaceAll('\\', '/');
        if (!p.endsWith('.sql') || p == src.path) continue;
        out[p] = f.readAsStringSync();
      }
      return out;
    }

    test('no migration other than the source names the bucket or the policy in a way that opens it', () {
      final all = others();
      expect(all, isNotEmpty, reason: 'positive control: the loader sees the other migrations');
      expect(mirrorViolations(all), isEmpty);
    });

    test('exactly one CREATE POLICY naming exercise-media exists across the migrations and the source', () {
      var n = 0;
      for (final text in [...others().values, migration]) {
        for (final s in stripSqlAllComments(text).split(';')) {
          if (RegExp(r'CREATE\s+POLICY', caseSensitive: false).hasMatch(s) && s.contains('exercise-media')) n++;
        }
      }
      expect(n, 1);
    });

    final cases = <(String, String, String)>[
      ('a later UPDATE flips the bucket public', "UPDATE storage.buckets SET public = true WHERE id = 'exercise-media';", 'mirror_public'),
      ('a later INSERT recreates the bucket public', "INSERT INTO storage.buckets (id, name, public) VALUES ('exercise-media', 'exercise-media', true);", 'mirror_public'),
      ('a later INSERT touches the bucket row at all', "INSERT INTO storage.buckets (id, name, public) VALUES ('exercise-media', 'exercise-media', false);", 'mirror_bucket_row'),
      ('a later policy naming the bucket', "CREATE POLICY open_media ON storage.objects FOR SELECT TO anon USING (bucket_id = 'exercise-media');", 'mirror_policy'),
      ('a later ALTER of the policy to public', 'ALTER POLICY exercise_media_authenticated_read ON storage.objects TO public;', 'mirror_policy_name'),
      ('a later DROP of the policy', 'DROP POLICY exercise_media_authenticated_read ON storage.objects;', 'mirror_policy_name'),
      ('a later re-CREATE of the policy without naming the bucket', 'CREATE POLICY exercise_media_authenticated_read ON storage.objects FOR SELECT TO anon USING (true);', 'mirror_policy_name'),
    ];
    for (final (name, sql, id) in cases) {
      test('mirror mutant: $name', () {
        expect(mirrorViolations({'supabase/migrations/999_later.sql': sql}), contains(id));
      });
    }

    test('mirror controls: an unrelated policy, a commented mention and another bucket stay clean', () {
      expect(
          mirrorViolations({
            'a.sql': "CREATE POLICY avatars_read ON storage.objects FOR SELECT TO public USING (bucket_id = 'avatars');",
            'b.sql': "-- UPDATE storage.buckets SET public = true WHERE id = 'exercise-media';\nSELECT 1;",
            'c.sql': "UPDATE storage.buckets SET public = true WHERE id = 'banners';",
          }),
          isEmpty);
    });
  });

  group('5 the two SQL files', () {
    final f1 = File(_verifyPath).readAsStringSync();
    final f2 = File(_rehearsalPath).readAsStringSync();

    test('the files exist, carry their markers and violate no pin', () {
      expect(sqlFilesViolations(f1: f1, f2: f2, migration: migration), isEmpty);
    });

    test('the probe block is byte-equal after normalisation in both files, and the prelude equals the migration body', () {
      final p1 = normalizeSql(_between(f1, '-- PROBE-BEGIN', '-- PROBE-END'));
      final p2 = normalizeSql(_between(f2, '-- PROBE-BEGIN', '-- PROBE-END'));
      expect(p1, isNotEmpty);
      expect(p1, p2);
      expect(normalizeSql(_between(f2, '-- PRELUDE-BEGIN', '-- PRELUDE-END')), normalizeSql(migrationBody(migration)));
    });

    test('the probe covers the four reads and the four write legs (insert, update, delete, the bucket row)', () {
      final p = normalizeSql(_between(f1, '-- PROBE-BEGIN', '-- PROBE-END'));
      for (final needle in ['SET LOCAL ROLE anon', "'is_anonymous',false", "'is_anonymous',true", "bucket_id = 'coach-media'", 'INSERT INTO storage.objects', 'UPDATE storage.objects', 'DELETE FROM storage.objects', 'UPDATE storage.buckets SET public = true;']) {
        expect(p, contains(needle));
      }
      expect(p, isNot(contains('UPDATE storage.buckets SET public = true WHERE')));
      expect(_count(p, 'SET LOCAL ROLE authenticated'), 7);
    });

    test('the catalog block is byte-equal in both files and reads storage.buckets policies as well as storage.objects', () {
      final c1 = normalizeSql(_between(f1, '-- CATALOG-BEGIN', '-- CATALOG-END'));
      final c2 = normalizeSql(_between(f2, '-- CATALOG-BEGIN', '-- CATALOG-END'));
      expect(c1, isNotEmpty);
      expect(c1, c2);
      expect(c1, contains(normalizeSql("tablename IN ('objects', 'buckets')")));
    });

    test('the live verify has no DDL and neither file controls a transaction', () {
      expect(RegExp(r'\b(CREATE|ALTER|DROP|GRANT|REVOKE|TRUNCATE)\b').hasMatch(executableText(f1)), isFalse);
      for (final f in [f1, f2]) {
        expect(RegExp(r'^\s*(BEGIN|START\s+TRANSACTION|COMMIT|ROLLBACK)\s*;', multiLine: true, caseSensitive: false).hasMatch(stripSqlAllComments(f)), isFalse);
      }
    });
  });

  group('6 mutants of the SQL files (in-process): each trips the pin written for it', () {
    final f1 = File(_verifyPath).readAsStringSync();
    final f2 = File(_rehearsalPath).readAsStringSync();
    final mutants = <(String, ({String f1, String f2, String migration}) Function(), List<String>)>[
      ('a leg dropped from the FILE 2 probe copy', () => (f1: f1, f2: _replaceOnce(f2, 'v_other := v_n::text;', "v_other := 'x';"), migration: migration), ['probe_equal']),
      ('a leg dropped from the FILE 1 probe copy', () => (f1: _replaceOnce(f1, 'v_other := v_n::text;', "v_other := 'x';"), f2: f2, migration: migration), ['probe_equal']),
      ('an extra statement in the FILE 2 prelude', () => (f1: f1, f2: _replaceOnce(f2, "  PERFORM set_config('lock_timeout', '5s', true);", "  PERFORM set_config('lock_timeout', '5s', true);\n  PERFORM 1;"), migration: migration), ['prelude_equal']),
      ('the migration changes and the prelude does not', () => (f1: f1, f2: f2, migration: _replaceOnce(migration, 'file_size_limit = 1500000\n      AND allowed', 'file_size_limit = 1400000\n      AND allowed')), ['prelude_equal']),
      ('an expected quadruple changed in FILE 2', () => (f1: f1, f2: _replaceOnce(f2, "'1/1/0/0'", "'0/1/0/0'"), migration: migration), ['f2_expected']),
      ('an expected write row changed in FILE 2', () => (f1: f1, f2: _replaceOnce(f2, "'inserted/1/1/0'", "'refused/0/0/0'"), migration: migration), ['f2_expected']),
      ('variant 1 no longer TO public', () => (f1: f1, f2: _replaceOnce(f2, 'FOR SELECT TO public', 'FOR SELECT TO authenticated'), migration: migration), ['f2_variants']),
      ('a variant dropped from the loop', () => (f1: f1, f2: _replaceOnce(f2, 'FOR v_i IN 1..6 LOOP', 'FOR v_i IN 1..5 LOOP'), migration: migration), ['f2_verdict']),
      ('the FILE 2 verdict accepts four of five', () => (f1: f1, f2: _replaceOnce(f2, 'v_red = 5', 'v_red = 4'), migration: migration), ['f2_verdict']),
      ('the FILE 2 guard removed', () => (f1: f1, f2: _replaceOnce(f2, "IF EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'exercise-media') THEN", "IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'exercise-media') THEN"), migration: migration), ['f2_guard']),
      ('a DDL statement in FILE 1', () => (f1: _replaceOnce(f1, '  v_anon_priv := has_table_privilege', "  DROP POLICY IF EXISTS x ON storage.objects;\n  v_anon_priv := has_table_privilege"), f2: f2, migration: migration), ['f1_no_ddl']),
      ('a COMMIT in FILE 1', () => (f1: _replaceOnce(f1, '  v_anon_priv := has_table_privilege', '  COMMIT;\n  v_anon_priv := has_table_privilege'), f2: f2, migration: migration), ['no_txn_control']),
      ('the FILE 1 verdict expects authenticated 0', () => (f1: _replaceOnce(f1, "AND v_auth = '1'", "AND v_auth = '0'"), f2: f2, migration: migration), ['f1_verdict']),
      ('a probe marker removed from FILE 1', () => (f1: _replaceOnce(f1, '  -- PROBE-END', '  -- PROBE-FIN'), f2: f2, migration: migration), ['markers']),
      ('the bucket leg dropped from the FILE 1 verdict', () => (f1: _replaceOnce(f1, " AND v_write_bucket = '0'", ''), f2: f2, migration: migration), ['f1_verdict']),
      ('an expected catalog string changed in FILE 2', () => (f1: f1, f2: _replaceOnce(f2, "'ALL|{authenticated}|true|true|none|none'", "'SELECT|{authenticated}|true|true|none|none'"), migration: migration), ['f2_expected']),
      ('the grant-dependent expectation of variant 5 removed', () => (f1: f1, f2: _replaceOnce(f2, "  IF v_bucket_upd_priv THEN v_expected_w[6] := 'refused/0/0/open'; END IF;\n", ''), migration: migration), ['f2_flow']),
      ('the grant-dependent expectation of variant 5 goes back to a row count', () => (f1: f1, f2: _replaceOnce(f2, "v_expected_w[6] := 'refused/0/0/open'", "v_expected_w[6] := 'refused/0/0/1'"), migration: migration), ['f2_flow']),
      ('the bucket leg takes a WHERE on id again in FILE 1 AND FILE 2 together', () => (f1: _replaceOnce(f1, 'UPDATE storage.buckets SET public = true;', "UPDATE storage.buckets SET public = true WHERE id = 'exercise-media';"), f2: _replaceOnce(f2, 'UPDATE storage.buckets SET public = true;', "UPDATE storage.buckets SET public = true WHERE id = 'exercise-media';"), migration: migration), ['bucket_leg_where', 'messages']),
      ('the bucket leg reads a row count again in FILE 1 AND FILE 2 together', () => (f1: _replaceOnce(f1, "v_write_bucket := CASE WHEN v_n = 0 THEN '0' ELSE 'open' END;", 'v_write_bucket := v_n::text;'), f2: _replaceOnce(f2, "v_write_bucket := CASE WHEN v_n = 0 THEN '0' ELSE 'open' END;", 'v_write_bucket := v_n::text;'), migration: migration), ['messages']),
      ('the unscoped-write check forgets a policy that names exercise-media, in both files', () => (f1: _replaceOnce(f1, "          OR strpos(coalesce(qual, '') || coalesce(with_check, ''), 'exercise-media') > 0\n", ''), f2: _replaceOnce(f2, "              OR strpos(coalesce(qual, '') || coalesce(with_check, ''), 'exercise-media') > 0\n", ''), migration: migration), ['messages']),
      ('the unscoped-write check forgets a negated bucket test, in both files', () => (f1: _replaceOnce(f1, "\n          OR (coalesce(qual, '') || coalesce(with_check, '')) ~ '(<>|!=|NOT )')", ')'), f2: _replaceOnce(f2, "\n              OR (coalesce(qual, '') || coalesce(with_check, '')) ~ '(<>|!=|NOT )')", ')'), migration: migration), ['messages']),
      ('the FILE 2 flags ignore the catalog reading', () => (f1: f1, f2: _replaceOnce(f2, " AND v_cat = v_expected_c[v_i]\n                       THEN 'RED'", "\n                       THEN 'RED'"), migration: migration), ['f2_flow']),
      ('the catalog reading is composed without the unscoped writes', () => (f1: f1, f2: _replaceOnce(f2, "        || v_anon_public || '|' || v_unscoped_write;", "        || v_anon_public;"), migration: migration), ['f2_flow']),
      ('variant 6 (the buckets policy) changed', () => (f1: f1, f2: _replaceOnce(f2, 'FOR UPDATE TO authenticated', 'FOR SELECT TO authenticated'), migration: migration), ['f2_variants']),
      ('the catalog block differs in FILE 2', () => (f1: f1, f2: _replaceOnce(f2, "tablename IN ('objects', 'buckets')", "tablename IN ('objects')"), migration: migration), ['catalog_equal']),
      ('the catalog block loses the buckets table in FILE 1 AND FILE 2 together', () => (f1: _replaceOnce(f1, "tablename IN ('objects', 'buckets')", "tablename IN ('objects')"), f2: _replaceOnce(f2, "tablename IN ('objects', 'buckets')", "tablename IN ('objects')"), migration: migration), ['messages']),
      ('the probe messages are widened in FILE 1 AND FILE 2 together', () => (f1: _replaceOnce(f1, "LIKE 'permission denied for table objects%'", "LIKE 'permission denied for table%'"), f2: _replaceOnce(f2, "LIKE 'permission denied for table objects%'", "LIKE 'permission denied for table%'"), migration: migration), ['messages']),
      ('the insert refusal is matched loosely in both files', () => (f1: _replaceOnce(f1, 'row-level security policy for table "objects"%', 'row-level security policy%'), f2: _replaceOnce(f2, 'row-level security policy for table "objects"%', 'row-level security policy%'), migration: migration), ['messages']),
      ('the catalog reads is_anonymous with a LIKE underscore in both files', () => (f1: _replaceOnce(f1, "(strpos(qual, 'is_anonymous') > 0)::text", "(qual LIKE '%is_anonymous%')::text"), f2: _replaceOnce(f2, "(strpos(qual, 'is_anonymous') > 0)::text", "(qual LIKE '%is_anonymous%')::text"), migration: migration), ['messages', 'no_underscore_like']),
      ('the bucket scope of the unscoped-write check is a LIKE in both files', () => (f1: _replaceOnce(f1, "strpos(coalesce(qual, '') || coalesce(with_check, ''), 'bucket_id') = 0", "(coalesce(qual, '') || coalesce(with_check, '')) NOT LIKE '%bucket_id%'"), f2: _replaceOnce(f2, "strpos(coalesce(qual, '') || coalesce(with_check, ''), 'bucket_id') = 0", "(coalesce(qual, '') || coalesce(with_check, '')) NOT LIKE '%bucket_id%'"), migration: migration), ['no_underscore_like']),
      ('a catalog marker removed from FILE 1', () => (f1: _replaceOnce(f1, '  -- CATALOG-END', '  -- CATALOG-FIN'), f2: f2, migration: migration), ['markers']),
      ('the bucket leg changed in the FILE 2 probe copy', () => (f1: f1, f2: _replaceOnce(f2, 'UPDATE storage.buckets SET public = true;', "UPDATE storage.buckets SET public = true WHERE id = 'exercise-media-x';"), migration: migration), ['probe_equal']),
      ('the self-check reads is_anonymous with a LIKE underscore again', () => (f1: f1, f2: f2, migration: _replaceOnce(migration, "strpos(qual, 'is_anonymous') > 0", "qual LIKE '%is_anonymous%'")), ['prelude_equal']),
      ('the final RAISE removed from FILE 2', () => (f1: f1, f2: _replaceOnce(f2, "RAISE EXCEPTION 'VERIFY_RESULTS%'", "RAISE NOTICE 'VERIFY_RESULTS%'"), migration: migration), ['verify_results_once']),
    ];
    for (final (name, build, ids) in mutants) {
      test(name, () {
        final m = build();
        final got = sqlFilesViolations(f1: m.f1, f2: m.f2, migration: m.migration);
        for (final id in ids) {
          expect(got, contains(id), reason: 'mutant "$name" must trip $id, got $got');
        }
      });
    }
  });

  group('7 the blind spot is stated where a reader looks', () {
    test('the migration header, this file and the operations document name it', () {
      expect(migration, contains('BLIND SPOT OF THE TEXT PINS'));
      expect(File('test/contracts/exercise_media_bucket_private_test.dart').readAsStringSync(), contains('ITS BLIND SPOT'));
      final doc = File(_docPath);
      expect(doc.existsSync(), isTrue, reason: '$_docPath is written in Task 6.1');
      expect(doc.readAsStringSync().toLowerCase(), contains('blind spot'));
    });
  });
}
