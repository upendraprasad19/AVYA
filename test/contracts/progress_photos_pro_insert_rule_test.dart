// test/contracts/progress_photos_pro_insert_rule_test.dart
//
// Pins for the progress-photo PRO INSERT rule (migration 154; unit B1 of the 2026-10-06
// progress-photos batch; plan docs/plans/progress-photos-pro-server-rule.md; diagnose d8f2a6).
//
// WHAT THIS IS, honestly (CLAUDE.md §4.4 rule 21): a SOURCE-LEVEL test over SQL. It proves the
// migration TEXT is the frozen text, and that no other migration can silently weaken it. It cannot
// prove the live database refuses a free user or accepts a payer; that is
// test/sql/progress_photos_pro_insert_rule_live_verify.sql, run live with the founder's go. The SoT
// registry entry for the concept is therefore `presence_only: true` with that file named.
//
// HOW THE PINS ARE BUILT (round 2 of the plan review):
//  * WHOLE-expression equality, not clauses (D3a). A "contains each conjunct" pin passes when an AND
//    becomes an OR, and `(bucket AND own-folder) OR EXISTS (active subscription)` lets any PRO user
//    write into ANY bucket under any folder. The expected literals below are written by hand, not
//    generated from the migration; the helper's normaliser is pinned separately.
//  * `ruleFileViolations(sql)` is a PURE function returning the ids of the pins a text violates. The
//    real file must return none; every mutant in `_ruleMutants` (one per hole the reviews found) is
//    applied to the real text in-process and must return the ids it is expected to trip. So the pins
//    are mutation-proven on every run, and a loosened normaliser or a deleted pin reddens the mutant
//    tests, not only the real-file test.
//  * A TRIPWIRE over every LATER migration (D3b) instead of an effective-state resolver: any file
//    newer than the rule that touches the protected set at all fails until it is acknowledged in
//    `_tripwireAllow` (empty today), and acknowledging forces a human to re-verify the rule. An
//    acknowledgement records the file's content hash, so editing the file brings the violation back.
//
// Files read: `supabase/migrations/*.sql` UNION `docs/drafts/*.sql` through one loader, so this test is
// green while the migration is still a reviewed draft and after it is moved into supabase/migrations/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/migration_cap_reader.dart';
import '../helpers/progress_photo_rule_sql.dart';

// ── the expected literals (written by hand; whole statements) ───────────────────────────────────────

const String _policyExpr = '''
bucket_id = 'progress-photos'
AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
AND EXISTS (
  SELECT 1 FROM public.subscriptions s
  WHERE s.user_id = (SELECT auth.uid())
    AND s.status = 'active'
    AND s.end_date > now()
)''';

const String _fnStmt = r'''
CREATE OR REPLACE FUNCTION public.enforce_progress_photo_pro()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.subscriptions
    WHERE user_id = NEW.user_id
      AND status = 'active'
      AND end_date > now()
  ) THEN
    RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$fn$;''';

const String _trigStmt = '''
CREATE TRIGGER trg_progress_photo_pro
BEFORE INSERT ON public.progress_photos
FOR EACH ROW EXECUTE FUNCTION public.enforce_progress_photo_pro();''';

/// The whole migration, comment-stripped and normalised: the lock budget, the existence test that
/// picks ALTER or CREATE, both policy branches, the function, the trigger, the self-grant drop, in
/// this order.
final String _expectedWhole = normalizeSql('''
DO \$mig\$
BEGIN
  PERFORM set_config('lock_timeout', '5s', true);
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'progress_photos_insert_own'
  ) THEN
    ALTER POLICY "progress_photos_insert_own" ON storage.objects WITH CHECK ($_policyExpr);
  ELSE
    CREATE POLICY "progress_photos_insert_own" ON storage.objects FOR INSERT TO authenticated WITH CHECK ($_policyExpr);
  END IF;
  $_fnStmt
  DROP TRIGGER IF EXISTS trg_progress_photo_pro ON public.progress_photos;
  $_trigStmt
  DROP POLICY IF EXISTS "users_own_subscriptions" ON public.subscriptions;
END
\$mig\$;
''');

final String _normPolicyExpr = normalizeSql(_policyExpr);
final String _normFn = normalizeSql(_fnStmt);
final String _normTrig = normalizeSql(_trigStmt);

const List<String> _expectedInventory = <String>[
  'PERFORM set_config',
  'ALTER POLICY progress_photos_insert_own ON storage.objects',
  'CREATE POLICY progress_photos_insert_own ON storage.objects',
  'CREATE OR REPLACE FUNCTION public.enforce_progress_photo_pro',
  'DROP TRIGGER IF EXISTS trg_progress_photo_pro ON public.progress_photos',
  'CREATE TRIGGER trg_progress_photo_pro ON public.progress_photos',
  'DROP POLICY IF EXISTS users_own_subscriptions ON public.subscriptions',
];

/// The inline rollback block, uncommented: the policy back to the live pre-rule text (E1), the
/// trigger dropped, then its function. It does NOT re-create users_own_subscriptions.
final String _expectedRollback = normalizeSql(r'''
DO $rb$
BEGIN
  PERFORM set_config('lock_timeout', '5s', true);
  ALTER POLICY "progress_photos_insert_own" ON storage.objects
    WITH CHECK (
      bucket_id = 'progress-photos'
      AND (storage.foldername(name))[1] = (auth.uid())::text
    );
  DROP TRIGGER IF EXISTS trg_progress_photo_pro ON public.progress_photos;
  DROP FUNCTION IF EXISTS public.enforce_progress_photo_pro();
END
$rb$;
''');

/// `ALTER` / `CREATE` of the rule's policy -> the normalised text between `ON storage.objects` and
/// `WITH CHECK (`: a changed role list, `AS RESTRICTIVE`, or a dropped `FOR INSERT` shows up here.
const Map<String, String> _expectedPolicyMiddle = <String, String>{
  'ALTER': '',
  'CREATE': 'FOR INSERT TO authenticated',
};

// ── the pins as ONE pure function ──────────────────────────────────────────────────────────────────

Map<String, String> _policyMiddles(String sql) {
  final src = stripSqlAllComments(sql);
  final out = <String, String>{};
  final re = RegExp(
      r'(ALTER|CREATE)\s+POLICY\s+"?progress_photos_insert_own"?\s+ON\s+storage\.objects\b([^;]*?)\bWITH\s+CHECK\s*\(',
      caseSensitive: false);
  for (final m in re.allMatches(src)) {
    out[m.group(1)!.toUpperCase()] = normalizeSql(m.group(2)!);
  }
  return out;
}

String? _rollbackBlock(String sql) {
  final lines = sql.split('\n');
  final start = lines.indexWhere((l) => RegExp(r'^--\s*DO \$rb\$').hasMatch(l));
  final end = lines.indexWhere((l) => RegExp(r'^--\s*\$rb\$;').hasMatch(l));
  if (start < 0 || end < start) return null;
  return normalizeSql(lines.sublist(start, end + 1).map((l) => l.replaceFirst(RegExp(r'^--\s?'), '')).join('\n'));
}

/// The ids of the pins that [sql] (the rule's migration text) violates; empty = the frozen text.
List<String> ruleFileViolations(String sql) {
  final v = <String>[];
  if (normalizeSql(sql) != _expectedWhole) v.add('whole-file');

  final checks = storagePolicyWithChecks(sql, 'progress_photos_insert_own');
  if (checks.length != 2) {
    v.add('policy-check-count');
  } else {
    if (checks[0] != _normPolicyExpr) v.add('policy-check-alter');
    if (checks[1] != _normPolicyExpr) v.add('policy-check-create');
  }
  final mid = _policyMiddles(sql);
  for (final e in _expectedPolicyMiddle.entries) {
    if (mid[e.key] != e.value) v.add('policy-header-${e.key.toLowerCase()}');
  }
  if (functionStatement(sql, 'enforce_progress_photo_pro') != _normFn) v.add('function');
  if (triggerStatement(sql, 'trg_progress_photo_pro') != _normTrig) v.add('trigger');
  if (ddlInventory(sql).join('\n') != _expectedInventory.join('\n')) v.add('inventory');
  if (sql.contains('dry_run_rollback')) v.add('dry-run-line');
  if (nonAsciiInExecutableText(sql).isNotEmpty) v.add('non-ascii-in-code');
  if (_rollbackBlock(sql) != _expectedRollback) v.add('rollback-block');
  if (RegExp(r'CREATE\s+POLICY\s+"?users_own_subscriptions', caseSensitive: false).hasMatch(sql)) {
    v.add('recreates-self-grant');
  }
  return v;
}

// ── other pure pins ────────────────────────────────────────────────────────────────────────────────

final RegExp _ruleFileName = RegExp(r'^(\d{3})[a-z]?_progress_photos_pro_insert_rls_rule\.sql$');

/// Where the rule is defined across migrations + drafts: exactly one file by name AND by content.
List<String> ruleDefinitionViolations(Map<String, String> files) {
  final v = <String>[];
  final byName = files.keys.where((p) => _ruleFileName.hasMatch(baseName(p))).toList();
  if (byName.isEmpty) v.add('no file named NNN_progress_photos_pro_insert_rls_rule.sql in supabase/migrations/ or docs/drafts/');
  if (byName.length > 1) v.add('defined by name more than once: ${byName.join(', ')}');
  final byContent = files.entries
      .where((e) => RegExp(r'CREATE\s+TRIGGER\s+trg_progress_photo_pro\b', caseSensitive: false).hasMatch(stripSqlAllComments(e.value)))
      .map((e) => e.key)
      .toList();
  if (byContent.length != 1) v.add('CREATE TRIGGER trg_progress_photo_pro appears in ${byContent.length} files: ${byContent.join(', ')}');
  return v;
}

/// The server predicate as `verify-subscription` reads it, pinned as WHOLE statements (Hermes L1 F1): a
/// substring pin passes `expiresAt.getTime() > Date.now() - GRACE_MS` (the old text survives inside it), an
/// `is_pro: true` that ignores the comparison, and a dropped `.eq("user_id", userId)`.
List<String> verifySubscriptionPredicateViolations(String ts) {
  final src = ts.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').replaceAllMapped(RegExp(r'(^|\s)//[^\n]*'), (m) => m.group(1)!);
  final n = src.replaceAll(RegExp(r'\s+'), ' ');
  final v = <String>[];
  // the whole query chain, in order: the user filter, the status filter, the latest end date first
  if (!n.contains('.from("subscriptions") .select("plan, status, end_date") .eq("user_id", userId) '
      '.eq("status", "active") .order("end_date", { ascending: false }) .limit(1) .maybeSingle();')) {
    v.add('the subscriptions query chain (user filter, status literal, end_date selected and ordered)');
  }
  // the whole comparison statement, with no offset on either side
  if (!n.contains('const expiresAt = new Date(endDate); const isActive = expiresAt.getTime() > Date.now();')) {
    v.add('end-date comparison');
  }
  // the response carries the comparison's result, not a constant
  if (!n.contains('is_pro: isActive,')) v.add('is_pro is not the comparison result');
  return v;
}

/// Case 16 of the live arbiter script inserts a progress_photos row as `postgres`; the trigger fires for
/// postgres too, so the case must seed an active subscription first and remove it right after.
List<String> arbiterCase16Violations(String sql) {
  final start = sql.indexOf('----- 16. progress_photos (id)');
  final end = sql.indexOf('----- 17. daily_steps');
  if (start < 0 || end < start) return <String>['case 16 block not found'];
  final block = stripSqlAllComments(sql.substring(start, end));
  final v = <String>[];
  final open = block.indexOf('BEGIN');
  final handler = block.indexOf('EXCEPTION WHEN OTHERS THEN');
  final seed = block.indexOf('INSERT INTO public.subscriptions');
  final photo = block.indexOf('INSERT INTO public.progress_photos');
  final del = block.indexOf('DELETE FROM public.subscriptions');
  if (seed < 0) {
    v.add('the seed INSERT is missing');
  } else {
    if (photo >= 0 && seed > photo) v.add('the seed comes after the photo INSERT');
    if (open < 0 || handler < 0 || seed < open || seed > handler) v.add('the seed is outside the case-16 block');
    final stmt = RegExp(r'INSERT\s+INTO\s+public\.subscriptions[^;]*;').firstMatch(block.substring(seed))?.group(0);
    final expectedSeed = normalizeSql(
        "INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date) VALUES (v_user, 'monthly', 'active', v_now, v_now + interval '30 days');");
    if (stmt == null || normalizeSql(stmt) != expectedSeed) v.add('the seed row is not an active monthly row ending in 30 days');
  }
  if (photo < 0) {
    v.add('the photo INSERT is missing');
  } else {
    // the case exists to prove the (id) arbiter resolves: a photo INSERT that dropped its ON CONFLICT clause
    // stays green and tests nothing (Hermes L14 F3)
    final stmt = RegExp(r'INSERT\s+INTO\s+public\.progress_photos[^;]*;').firstMatch(block.substring(photo))?.group(0);
    // compared through normalizeSql on BOTH sides (it removes the space before a parenthesis)
    if (stmt == null || !normalizeSql(stmt).contains(normalizeSql('ON CONFLICT (id) DO UPDATE SET storage_path = EXCLUDED.storage_path'))) {
      v.add('the photo INSERT no longer names its arbiter (ON CONFLICT (id) DO UPDATE ...)');
    }
  }
  if (del < 0) {
    v.add('the seed DELETE is missing');
  } else {
    if (photo >= 0 && del < photo) v.add('the seed DELETE comes before the photo INSERT');
    if (open < 0 || handler < 0 || del < open || del > handler) v.add('the seed DELETE is outside the case-16 block');
    final stmt = RegExp(r'DELETE\s+FROM\s+public\.subscriptions[^;]*;').firstMatch(block.substring(del))?.group(0);
    if (stmt == null || normalizeSql(stmt) != normalizeSql('DELETE FROM public.subscriptions WHERE user_id = v_user;')) {
      v.add('the seed DELETE is not scoped to v_user');
    }
  }
  return v;
}

/// Structural pins for the live-verify file: ONE always-aborting DO block, no DDL, no commit.
List<String> liveVerifyViolations(String sql) {
  final src = stripSqlAllComments(sql);
  final v = <String>[];
  if (RegExp(r'\bDO\s+\$').allMatches(src).length != 1) v.add('not exactly one DO block');
  if (!src.contains("RAISE EXCEPTION 'VERIFY_RESULTS")) v.add('does not end in the always-aborting RAISE EXCEPTION');
  // the abort must be the LAST statement of the one DO block, not inside an IF / inner block, with no outer
  // EXCEPTION clause after it, no early RETURN before it, and no statement after the block
  if (!RegExp(r"RAISE\s+EXCEPTION\s+'VERIFY_RESULTS[^;]*;\s*END\s*\$v\$;\s*$").hasMatch(src)) {
    v.add('the always-aborting RAISE is not the last statement of the DO block');
  }
  if (RegExp(r'\bRETURN\b', caseSensitive: false).hasMatch(src)) v.add('contains RETURN (an exit before the abort)');
  if (RegExp(r'\b(CREATE|DROP|ALTER|GRANT|REVOKE|TRUNCATE|COMMIT|ROLLBACK|SAVEPOINT)\b', caseSensitive: false).hasMatch(src)) {
    v.add('contains DDL, COMMIT, ROLLBACK or SAVEPOINT (the file must be one DO block with no DDL)');
  }
  if (RegExp(r'\bBEGIN\s*;', caseSensitive: false).hasMatch(src)) v.add('opens an explicit transaction');
  // V8c must look at the check applied to the NEW row, not only the visible rows (Hermes L2 F3)
  if (!RegExp(r"cmd\s+IN\s+\('UPDATE',\s*'ALL'\)[^;]*coalesce\(with_check,\s*qual,\s*''\)").hasMatch(src)) {
    v.add('V8c does not check the new-row WITH CHECK of UPDATE/ALL policies');
  }
  final windows = RegExp(r'SET LOCAL ROLE authenticated').allMatches(src).length;
  final resets = RegExp(r'RESET ROLE;').allMatches(src).length;
  if (windows == 0 || windows != resets) v.add('role windows ($windows) and RESET ROLE ($resets) differ');
  if (RegExp(r'ROW_COUNT').allMatches(src).length < 6) v.add('fewer than six ROW_COUNT assertions (V3a, V3b, V3e, V4e, V7a, V7b)');
  if (nonAsciiInExecutableText(sql).isNotEmpty) v.add('non-ascii-in-code');
  for (final id in [
    'V0', 'V1', 'V2', 'V3a', 'V3b', 'V3c', 'V3d', 'V3e', 'V3f', 'V4a', 'V4b', 'V4c', 'V4d', 'V4e', 'V4f', 'V5a', 'V5b', 'V6a', 'V6b', 'V6c', 'V6d',
    'V7a', 'V7b', 'V8a', 'V8b', 'V8c', 'V8d', 'V8e', 'V8f', 'V9'
  ]) {
    if (!src.contains("'$id=ok") && !src.contains("E'$id=ok")) v.add('case $id has no ok line');
  }
  if (!src.contains("'42501'") || !src.contains("'P0001'")) v.add('a refusal case does not name its SQLSTATE');
  return v;
}

/// Everything the tripwire says about the tree: problems with the allow-list itself plus the violations.
List<String> _tripwireStateViolations(Map<String, String> files, String b1Path, Map<String, TripwireAllow> allow) => <String>[
      ...allowListIssues(files, allow, b1Path: b1Path),
      ...tripwireViolations(files, b1Path: b1Path, allow: allow),
    ];

// ── in-process mutation helper ─────────────────────────────────────────────────────────────────────

class _Edit {
  const _Edit(this.from, this.to, {this.nth = 0, this.count = 1});
  final String from;
  final String to;

  /// Which occurrence is replaced (0-based) when [from] occurs [count] times.
  final int nth;

  /// How many times [from] must occur in the text (the "mutation APPLIED" check).
  final int count;
}

String _mutate(String src, List<_Edit> edits) {
  var s = src;
  for (final e in edits) {
    final n = e.from.allMatches(s).length;
    expect(n, e.count, reason: 'mutant edit must find its text exactly ${e.count} time(s), found $n: ${e.from.replaceAll('\n', r'\n')}');
    var idx = -1;
    var from = 0;
    for (var k = 0; k <= e.nth; k++) {
      idx = s.indexOf(e.from, from);
      from = idx + 1;
    }
    s = s.substring(0, idx) + e.to + s.substring(idx + e.from.length);
  }
  expect(s, isNot(src), reason: 'a mutant must change the text');
  return s;
}

class _RuleMutant {
  const _RuleMutant(this.id, this.what, this.edits, this.pins, {this.wholeFile = true});
  final String id;
  final String what;
  final List<_Edit> edits;

  /// False only for a mutant inside the commented rollback block: comments are stripped, so the
  /// whole-file pin (which reads the executable text) cannot see it and `rollback-block` must.
  final bool wholeFile;

  /// Pin ids that MUST be among the violations (besides `whole-file`, which every mutant trips).
  final Set<String> pins;
}

const String _unlessEnd = "        AND end_date > now()\n    ) THEN";
const String _bucketLine = "        bucket_id = 'progress-photos'\n";
const String _folderLine = '        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text\n';
const String _statusLine = "            AND s.status = 'active'\n";
const String _endLine = '            AND s.end_date > now()\n';
const String _existsBlock = "        AND EXISTS (\n"
    "          SELECT 1 FROM public.subscriptions s\n"
    "          WHERE s.user_id = (SELECT auth.uid())\n"
    "            AND s.status = 'active'\n"
    "            AND s.end_date > now()\n"
    "        )\n";

final List<_RuleMutant> _ruleMutants = <_RuleMutant>[
  // the trigger function and the trigger
  const _RuleMutant('T1', 'drop end_date > now() from the function', [_Edit(_unlessEnd, '    ) THEN')], {'function'}),
  const _RuleMutant('T2', "status = 'active' -> IN ('active','cancelled')", [
    _Edit("        AND status = 'active'\n        AND end_date > now()\n    ) THEN",
        "        AND status IN ('active', 'cancelled')\n        AND end_date > now()\n    ) THEN")
  ], {'function'}),
  const _RuleMutant('T3', 'IF NOT EXISTS -> IF EXISTS', [_Edit('    IF NOT EXISTS (', '    IF EXISTS (')], {'function'}),
  const _RuleMutant('T4', 'RETURN NEW -> RETURN NULL', [_Edit('    RETURN NEW;', '    RETURN NULL;')], {'function'}),
  const _RuleMutant('T5', 'RAISE EXCEPTION -> RAISE NOTICE', [
    _Edit("      RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = 'P0001';",
        "      RAISE NOTICE 'progress_photo_pro_required';")
  ], {'function'}),
  const _RuleMutant('T6', 'P0001 -> 42501', [_Edit("required' USING ERRCODE = 'P0001'", "required' USING ERRCODE = '42501'")], {'function'}),
  const _RuleMutant('T7', 'NEW.user_id -> auth.uid()', [_Edit('WHERE user_id = NEW.user_id', 'WHERE user_id = auth.uid()')], {'function'}),
  const _RuleMutant('T8', 'BEFORE INSERT -> BEFORE INSERT OR UPDATE', [
    _Edit('    BEFORE INSERT ON public.progress_photos', '    BEFORE INSERT OR UPDATE ON public.progress_photos')
  ], {'trigger'}),
  const _RuleMutant('T9', 'the EXISTS block commented out with /* */', [
    _Edit('    IF NOT EXISTS (\n', '    /* IF NOT EXISTS (\n'),
    _Edit('    END IF;\n    RETURN NEW;', '    END IF; */\n    RETURN NEW;'),
  ], {'function'}),
  const _RuleMutant('T10', 'the CREATE TRIGGER commented out with /* */', [
    _Edit('  CREATE TRIGGER trg_progress_photo_pro\n', '  /* CREATE TRIGGER trg_progress_photo_pro\n'),
    _Edit('enforce_progress_photo_pro();\n\n  -- (4)', 'enforce_progress_photo_pro(); */\n\n  -- (4)'),
  ], {'trigger', 'inventory'}),
  const _RuleMutant('T11', 'SET search_path removed', [
    _Edit('LANGUAGE plpgsql SET search_path = public, pg_temp AS', 'LANGUAGE plpgsql AS')
  ], {'function'}),
  const _RuleMutant('T12', 'end_date > now() -> end_date >= now()', [
    _Edit(_unlessEnd, '        AND end_date >= now()\n    ) THEN')
  ], {'function'}),
  const _RuleMutant('T13', 'the RAISE swallowed by an inner EXCEPTION WHEN OTHERS', [
    _Edit("      RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = 'P0001';",
        "      BEGIN RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = 'P0001'; EXCEPTION WHEN OTHERS THEN NULL; END;")
  ], {'function'}),
  const _RuleMutant('T14', 'an early RETURN NEW before the IF', [_Edit('    IF NOT EXISTS (', '    RETURN NEW;\n    IF NOT EXISTS (')], {'function'}),
  const _RuleMutant('T15', 'THEN guarded by AND false', [_Edit('    ) THEN\n      RAISE', '    ) AND false THEN\n      RAISE')], {'function'}),
  const _RuleMutant('T16', 'AND end_date -> OR end_date', [_Edit(_unlessEnd, '        OR end_date > now()\n    ) THEN')], {'function'}),
  const _RuleMutant('T17', 'AND status -> OR status', [
    _Edit("        AND status = 'active'\n        AND end_date > now()\n    ) THEN",
        "        OR status = 'active'\n        AND end_date > now()\n    ) THEN")
  ], {'function'}),
  // the Storage policy
  _RuleMutant('P1', 'drop end_date from the ALTER branch only', [_Edit(_endLine, '', count: 2, nth: 0)], {'policy-check-alter'}),
  _RuleMutant('P2', 'widen status in the CREATE branch only', [
    _Edit(_statusLine, "            AND s.status IN ('active', 'cancelled')\n", count: 2, nth: 1)
  ], {'policy-check-create'}),
  _RuleMutant('P3', 'the PRO EXISTS removed from the ALTER branch', [_Edit(_existsBlock, '', count: 2, nth: 0)], {'policy-check-alter'}),
  _RuleMutant('P4', 'the own-folder conjunct removed from the ALTER branch', [_Edit(_folderLine, '', count: 2, nth: 0)], {'policy-check-alter'}),
  _RuleMutant('P5', "bucket literal 'progress_photos' in the CREATE branch", [
    _Edit(_bucketLine, "        bucket_id = 'progress_photos'\n", count: 2, nth: 1)
  ], {'policy-check-create'}),
  const _RuleMutant('P6', 'AS RESTRICTIVE added to the CREATE branch', [
    _Edit('ON storage.objects\n      FOR INSERT TO authenticated', 'ON storage.objects\n      AS RESTRICTIVE FOR INSERT TO authenticated')
  ], {'policy-header-create'}),
  _RuleMutant('P7', 'the user filter removed from the subscription read (live RLS would mask it)', [
    _Edit("          WHERE s.user_id = (SELECT auth.uid())\n            AND s.status = 'active'\n",
        "          WHERE s.status = 'active'\n", count: 2, nth: 0)
  ], {'policy-check-alter'}),
  const _RuleMutant('P8', 'an extra DROP POLICY on the table', [
    _Edit('  DROP POLICY IF EXISTS "users_own_subscriptions" ON public.subscriptions;\nEND',
        '  DROP POLICY IF EXISTS "users_own_subscriptions" ON public.subscriptions;\n  DROP POLICY "progress_photos_insert_own" ON public.progress_photos;\nEND')
  ], {'inventory'}),
  const _RuleMutant('P9', 'an added FOR DELETE policy with a PRO condition', [
    _Edit('  DROP POLICY IF EXISTS "users_own_subscriptions" ON public.subscriptions;\nEND',
        '  DROP POLICY IF EXISTS "users_own_subscriptions" ON public.subscriptions;\n'
            "  CREATE POLICY \"pp_del\" ON public.progress_photos FOR DELETE USING (EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.user_id = auth.uid() AND s.status = 'active'));\nEND")
  ], {'inventory'}),
  _RuleMutant('P10', 'the second AND -> OR in the ALTER branch', [
    _Edit('$_folderLine        AND EXISTS (\n', '$_folderLine        OR EXISTS (\n', count: 2, nth: 0)
  ], {'policy-check-alter'}),
  _RuleMutant('P11', 'the first AND -> OR in the ALTER branch', [
    _Edit("$_bucketLine        AND (storage.foldername", "$_bucketLine        OR (storage.foldername", count: 2, nth: 0)
  ], {'policy-check-alter'}),
  const _RuleMutant('P12', 'FOR INSERT removed from the CREATE branch (default ALL)', [
    _Edit('      FOR INSERT TO authenticated\n', '      TO authenticated\n')
  ], {'policy-header-create'}),
  const _RuleMutant('P13', 'the ALTER branch gains a role list', [
    _Edit('ALTER POLICY "progress_photos_insert_own" ON storage.objects\n', 'ALTER POLICY "progress_photos_insert_own" ON storage.objects TO public\n', count: 2)
  ], {'policy-header-alter'}),
  // step (4) and the lock budget and the existence test
  const _RuleMutant('S2', 'the self-grant policy drop removed', [
    _Edit('  DROP POLICY IF EXISTS "users_own_subscriptions" ON public.subscriptions;\n', '')
  ], {'inventory'}),
  const _RuleMutant('S3', 'the drop targets the live SELECT policy instead', [
    _Edit('DROP POLICY IF EXISTS "users_own_subscriptions" ON public.subscriptions;', 'DROP POLICY IF EXISTS "subscriptions_select_own" ON public.subscriptions;')
  ], {'inventory'}),
  const _RuleMutant('Q1', 'the lock_timeout line removed', [_Edit("  PERFORM set_config('lock_timeout', '5s', true);\n\n  -- (1)", '\n  -- (1)')], {'inventory'}),
  const _RuleMutant('Q2', 'the existence test looks for another policy name', [
    _Edit("      AND policyname = 'progress_photos_insert_own'\n  ) THEN", "      AND policyname = 'progress_photos_other'\n  ) THEN")
  ], {}),
  const _RuleMutant('Q3', 'lock_timeout 5s -> 60s', [_Edit("'5s', true", "'60s', true", count: 2)], {}),
  const _RuleMutant('Q4', 'the trigger drop removed (a re-run would fail)', [
    _Edit('  DROP TRIGGER IF EXISTS trg_progress_photo_pro ON public.progress_photos;\n', '', count: 2)
  ], {'inventory'}),
  const _RuleMutant('Q5', 'FOR EACH ROW -> FOR EACH STATEMENT', [_Edit('FOR EACH ROW', 'FOR EACH STATEMENT')], {'trigger'}),
  // the dry-run line must never ship, and the rollback block is pinned
  const _RuleMutant('D1', 'the always-aborting dry-run line left in', [
    _Edit('  DROP POLICY IF EXISTS "users_own_subscriptions" ON public.subscriptions;\nEND',
        "  DROP POLICY IF EXISTS \"users_own_subscriptions\" ON public.subscriptions;\n  RAISE EXCEPTION 'dry_run_rollback';\nEND")
  ], {'dry-run-line', 'inventory'}),
  const _RuleMutant('R1', 'the rollback block restores a different policy text', [
    _Edit('--       AND (storage.foldername(name))[1] = (auth.uid())::text', '--       AND (storage.foldername(name))[1] = (SELECT auth.uid())::text')
  ], {'rollback-block'}, wholeFile: false),
  const _RuleMutant('R2', 'the rollback block no longer drops the trigger', [
    _Edit('--   DROP TRIGGER IF EXISTS trg_progress_photo_pro ON public.progress_photos;\n', '')
  ], {'rollback-block'}, wholeFile: false),
  const _RuleMutant('N1', 'a non-breaking space inside end_date > now() (Postgres reads `end_date\u00A0` as one identifier)', [
    _Edit(_unlessEnd, '        AND end_date\u00A0> now()\n    ) THEN')
  ], {'non-ascii-in-code', 'function'}),
  const _RuleMutant('N2', 'a -- comment line carrying the DO tag after END smuggles in an extra statement', [
    _Edit('END\n\$mig\$;', 'END\n-- \$mig\$; CREATE TEMP TABLE b1_marker(x int); SELECT \$mig\$\n\$mig\$;')
  ], {'inventory'}),
  const _RuleMutant('N3', 'a non-breaking space between ALTER and POLICY (Postgres refuses the file; the pins must not call it the frozen text)', [
    _Edit('    ALTER POLICY "progress_photos_insert_own" ON storage.objects\n', '    ALTER\u00A0POLICY "progress_photos_insert_own" ON storage.objects\n')
  ], {'non-ascii-in-code'}),
  const _RuleMutant('R3', 'the rollback block re-creates the self-grant policy', [
    _Edit('--   DROP FUNCTION IF EXISTS public.enforce_progress_photo_pro();\n',
        '--   DROP FUNCTION IF EXISTS public.enforce_progress_photo_pro();\n--   CREATE POLICY "users_own_subscriptions" ON public.subscriptions FOR ALL USING (auth.uid() = user_id);\n')
  ], {'rollback-block', 'recreates-self-grant'}, wholeFile: false),
];

// ── the tripwire's synthetic later migrations ─────────────────────────────────────────────────────

/// Later migrations, one per way the plan's round 2 found to remove the rule or its `subscriptions`
/// read. Each must trip the tripwire (and, where it names them, the other cross-file pins).
const Map<String, String> _laterMigrations = <String, String>{
  'L1 re-creates the storage policy without the PRO conjunct':
      '''ALTER POLICY "progress_photos_insert_own" ON storage.objects WITH CHECK (bucket_id = 'progress-photos' AND (storage.foldername(name))[1] = (auth.uid())::text);''',
  'L2 a second permissive INSERT policy for the bucket':
      '''CREATE POLICY "pp_extra" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'progress-photos');''',
  'L3 a later DROP TRIGGER': 'DROP TRIGGER trg_progress_photo_pro ON public.progress_photos;',
  'L4 a later ALTER TABLE ... DISABLE TRIGGER': 'ALTER TABLE public.progress_photos DISABLE TRIGGER trg_progress_photo_pro;',
  'L5 REVOKE SELECT on subscriptions': 'REVOKE SELECT ON public.subscriptions FROM authenticated;',
  'L6 DROP POLICY subscriptions_select_own': 'DROP POLICY subscriptions_select_own ON public.subscriptions;',
  'L7 an unscoped INSERT policy on storage.objects': 'CREATE POLICY u ON storage.objects FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);',
  'L8 a policy on storage.objects with no FOR (default ALL)': 'CREATE POLICY x ON storage.objects TO authenticated WITH CHECK (true);',
  'L9 DROP FUNCTION ... CASCADE': 'DROP FUNCTION public.enforce_progress_photo_pro() CASCADE;',
  'L10 ALTER TRIGGER ... RENAME then a drop of the new name':
      'ALTER TRIGGER trg_progress_photo_pro ON public.progress_photos RENAME TO t2; DROP TRIGGER t2 ON public.progress_photos;',
  'L11 ALTER POLICY ... RENAME': 'ALTER POLICY "progress_photos_insert_own" ON storage.objects RENAME TO y;',
  'L12 REVOKE ALL on subscriptions': 'REVOKE ALL ON public.subscriptions FROM authenticated;',
  'L13a narrowing the subscriptions SELECT policy': 'ALTER POLICY subscriptions_select_own ON public.subscriptions USING (false);',
  'L13b retargeting the subscriptions SELECT policy': 'ALTER POLICY subscriptions_select_own ON public.subscriptions TO service_role;',
  'L14 a RESTRICTIVE USING (false) policy on subscriptions': 'CREATE POLICY r ON public.subscriptions AS RESTRICTIVE FOR SELECT USING (false);',
  'L15 narrowing the table SELECT policy': 'ALTER POLICY progress_photos_select_own ON public.progress_photos USING (false);',
  'L17 DROP COLUMN ... CASCADE on subscriptions': 'ALTER TABLE public.subscriptions DROP COLUMN end_date CASCADE;',
  'L18 ALTER TABLE storage.objects': 'ALTER TABLE storage.objects DISABLE ROW LEVEL SECURITY;',
  'L19 DROP SCHEMA ... CASCADE': 'DROP SCHEMA storage CASCADE;',
  'L20 RLS switched off on the table': 'ALTER TABLE public.progress_photos DISABLE ROW LEVEL SECURITY;',
  'L21 a real statement beside a harmless block comment':
      '/* harmless */ DROP TRIGGER IF EXISTS trg_progress_photo_pro ON public.progress_photos;',
  'L22 the quoted style `supabase db diff` emits: ALTER POLICY ... ON "storage"."objects"':
      '''alter policy "progress_photos_insert_own" on "storage"."objects" with check (((bucket_id = 'progress-photos'::text)));''',
  'L23 a quoted DROP TRIGGER on "public"."progress_photos"': 'drop trigger "trg_progress_photo_pro" on "public"."progress_photos";',
  'L24 REVOKE INSERT on progress_photos': 'REVOKE INSERT ON public.progress_photos FROM authenticated;',
  'L25 GRANT ALL on storage.objects': 'GRANT ALL ON storage.objects TO anon;',
  'L26 a quoted ALTER TABLE ... DISABLE TRIGGER': 'alter table "public"."progress_photos" disable trigger all;',
  'L36 a second subcommand after a literal holding a semicolon': "ALTER TABLE public.progress_photos ADD COLUMN c text DEFAULT ';', DISABLE TRIGGER ALL;",
  'L28 a BEFORE INSERT trigger on progress_photos named to sort first': 'CREATE TRIGGER aaa_first BEFORE INSERT ON public.progress_photos FOR EACH ROW EXECUTE FUNCTION public.f();',
  'L29 a rule on progress_photos': 'CREATE RULE r AS ON INSERT TO public.progress_photos DO INSTEAD NOTHING;',
  'L30 DROP OWNED': 'DROP OWNED BY authenticator;',
  'L31 a role granted BYPASSRLS': 'ALTER ROLE authenticated BYPASSRLS;',
  'L32 blanks around the dot and a block comment between keywords': 'ALTER TABLE public .progress_photos/**/DISABLE TRIGGER ALL;',
  'L33 a block comment between ALTER and POLICY': "ALTER/**/POLICY progress_photos_insert_own ON storage.objects WITH CHECK (true);",
  'L34 a statement after a double-quoted alias holding a comment marker': 'SELECT 1 AS "x--"; DROP TRIGGER trg_progress_photo_pro ON public.progress_photos;',
  'L35 a statement after an E-string whose backslash-quote hides a comment marker': "SELECT E'\\' -- '; DROP TRIGGER trg_progress_photo_pro ON public.progress_photos;",
  'L37 REVOKE on a multi-table list that names subscriptions': 'REVOKE SELECT ON public.users, public.subscriptions FROM authenticated;',
  'L38 REVOKE on every table of the public schema': 'REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM authenticated;',
  'L39 an INSERT policy on an unqualified objects after SET search_path': 'SET search_path = storage; CREATE POLICY e ON objects FOR INSERT TO authenticated WITH CHECK (true);',
  'L40 session_replication_role set on a role': 'ALTER ROLE authenticator SET session_replication_role = replica;',
  'L27 a quoted policy statement on "public"."subscriptions"':
      '''create policy "Users manage own subs" on "public"."subscriptions" for all to authenticated using (true);''',
};

/// One statement per ALTERNATIVE of the protected set that no other category also matches, so
/// removing one alternative from the helper reddens exactly one entry here (the mutation round that
/// found the first gaps: ALTER TRIGGER, a structural ALTER TABLE on subscriptions and a file that
/// shares the rule's number were each caught only by a neighbouring category).
const Map<String, String> _laterMigrationsIsolated = <String, String>{
  'C2a progress_photos_select_own dropped': 'DROP POLICY progress_photos_select_own ON public.progress_photos;',
  'C2a progress_photos_delete_own altered': 'ALTER POLICY progress_photos_delete_own ON public.progress_photos USING (false);',
  'C2a progress_photos_update_own altered': 'ALTER POLICY progress_photos_update_own ON public.progress_photos USING (false);',
  'C2a progress_photos_insert_own on the table dropped': 'DROP POLICY IF EXISTS progress_photos_insert_own ON public.progress_photos;',
  'C1b the function alone redefined with a weaker body': r'CREATE OR REPLACE FUNCTION public.enforce_progress_photo_pro() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RETURN NEW; END; $f$;',
  'C1c the trigger alone dropped': 'DROP TRIGGER trg_progress_photo_pro ON public.progress_photos;',
  'C2b any policy statement on storage.objects': "CREATE POLICY elsewhere ON storage.objects FOR SELECT USING (bucket_id = 'x');",
  'C2b a DROP of an unrelated policy on storage.objects': 'DROP POLICY "Allow authenticated uploads to avatars" ON storage.objects;',
  'C2b an ALTER of an unrelated policy on storage.objects': 'ALTER POLICY "Users can upload own avatar" ON storage.objects WITH CHECK (true);',
  'C3a ALTER TABLE storage.objects owner': 'ALTER TABLE storage.objects OWNER TO postgres;',
  'C3b progress_photos RENAME': 'ALTER TABLE public.progress_photos RENAME TO pp2;',
  'C3b progress_photos DISABLE TRIGGER ALL': 'ALTER TABLE public.progress_photos DISABLE TRIGGER ALL;',
  'C3b progress_photos ENABLE REPLICA TRIGGER ALL': 'ALTER TABLE public.progress_photos ENABLE REPLICA TRIGGER ALL;',
  'C3b progress_photos ENABLE ALWAYS TRIGGER ALL': 'ALTER TABLE public.progress_photos ENABLE ALWAYS TRIGGER ALL;',
  'C3b progress_photos ENABLE TRIGGER ALL': 'ALTER TABLE public.progress_photos ENABLE TRIGGER ALL;',
  'C3b progress_photos DISABLE ROW LEVEL SECURITY': 'ALTER TABLE public.progress_photos DISABLE ROW LEVEL SECURITY;',
  'C3b progress_photos ENABLE ROW LEVEL SECURITY': 'ALTER TABLE public.progress_photos ENABLE ROW LEVEL SECURITY;',
  'C3b progress_photos FORCE ROW LEVEL SECURITY': 'ALTER TABLE public.progress_photos FORCE ROW LEVEL SECURITY;',
  'C3b progress_photos NO FORCE ROW LEVEL SECURITY': 'ALTER TABLE public.progress_photos NO FORCE ROW LEVEL SECURITY;',
  'C3b progress_photos DROP COLUMN': 'ALTER TABLE public.progress_photos DROP COLUMN notes;',
  'C3b progress_photos ALTER COLUMN': 'ALTER TABLE public.progress_photos ALTER COLUMN user_id DROP NOT NULL;',
  'C3b progress_photos OWNER': 'ALTER TABLE public.progress_photos OWNER TO postgres;',
  'C3b progress_photos SET SCHEMA': 'ALTER TABLE public.progress_photos SET SCHEMA other;',
  'C3b DROP TABLE progress_photos': 'DROP TABLE public.progress_photos;',
  'C3c ALTER TRIGGER on an unrelated trigger': 'ALTER TRIGGER some_other_trigger ON public.some_table RENAME TO renamed;',
  'C4a CREATE POLICY on subscriptions': 'CREATE POLICY extra ON public.subscriptions FOR SELECT USING (true);',
  'C4b GRANT on subscriptions': 'GRANT SELECT ON public.subscriptions TO anon;',
  'C4b REVOKE on subscriptions (no CASCADE)': 'REVOKE SELECT ON public.subscriptions FROM authenticated;',
  'C4c DROP TABLE subscriptions': 'DROP TABLE public.subscriptions;',
  'C4c subscriptions RENAME': 'ALTER TABLE public.subscriptions RENAME TO s2;',
  'C4c subscriptions DROP COLUMN': 'ALTER TABLE public.subscriptions DROP COLUMN plan;',
  'C4c subscriptions ALTER COLUMN': 'ALTER TABLE public.subscriptions ALTER COLUMN end_date TYPE text;',
  'C4c subscriptions DISABLE ROW LEVEL SECURITY': 'ALTER TABLE public.subscriptions DISABLE ROW LEVEL SECURITY;',
  'C4c subscriptions SET SCHEMA': 'ALTER TABLE public.subscriptions SET SCHEMA other;',
  'C4c subscriptions OWNER': 'ALTER TABLE public.subscriptions OWNER TO postgres;',
  'C5 DROP FUNCTION unrelated CASCADE': 'DROP FUNCTION public.unrelated() CASCADE;',
  'C5 DROP TABLE unrelated CASCADE': 'DROP TABLE public.unrelated CASCADE;',
  'C5 DROP TRIGGER unrelated CASCADE': 'DROP TRIGGER unrelated_t ON public.unrelated CASCADE;',
  'C5 DROP POLICY unrelated CASCADE': 'DROP POLICY unrelated_p ON public.unrelated CASCADE;',
  'C5 ALTER TABLE unrelated DROP COLUMN CASCADE': 'ALTER TABLE public.unrelated DROP COLUMN c CASCADE;',
  'C3f CREATE TRIGGER on progress_photos': 'CREATE TRIGGER t BEFORE INSERT ON public.progress_photos FOR EACH ROW EXECUTE FUNCTION public.f();',
  'C3f CREATE CONSTRAINT TRIGGER on storage.objects': 'CREATE CONSTRAINT TRIGGER t AFTER INSERT ON storage.objects FOR EACH ROW EXECUTE FUNCTION public.f();',
  'C3f CREATE TRIGGER on subscriptions': 'CREATE OR REPLACE TRIGGER t BEFORE UPDATE ON public.subscriptions FOR EACH ROW EXECUTE FUNCTION public.f();',
  'C3g CREATE RULE on progress_photos': 'CREATE RULE r AS ON INSERT TO progress_photos DO INSTEAD NOTHING;',
  'C3g CREATE OR REPLACE RULE on subscriptions': 'CREATE OR REPLACE RULE r AS ON UPDATE TO public.subscriptions DO INSTEAD NOTHING;',
  'C3h DROP OWNED': 'DROP OWNED BY some_role CASCADE;',
  'C3i ALTER ROLE BYPASSRLS': 'ALTER ROLE some_role WITH BYPASSRLS;',
  'C3i CREATE USER BYPASSRLS': 'CREATE USER u WITH PASSWORD \'x\' BYPASSRLS;',
  'C3d GRANT on public.progress_photos': 'GRANT SELECT ON public.progress_photos TO anon;',
  'C3d REVOKE on public.progress_photos (TABLE keyword)': 'REVOKE ALL ON TABLE public.progress_photos FROM authenticated;',
  'C3d GRANT on storage.objects': 'GRANT INSERT ON storage.objects TO anon;',
  'C3d REVOKE on storage.objects': 'REVOKE INSERT ON storage.objects FROM authenticated;',
  'C3d REVOKE on a multi-table list that names progress_photos': 'REVOKE INSERT ON public.users, public.progress_photos FROM authenticated;',
  'C3d REVOKE on every table of the storage schema': 'REVOKE INSERT ON ALL TABLES IN SCHEMA storage FROM authenticated;',
  'C3d GRANT on an unqualified objects': 'GRANT INSERT ON objects TO anon;',
  'C3a ALTER TABLE an unqualified objects': 'ALTER TABLE objects DISABLE ROW LEVEL SECURITY;',
  'C2b an unqualified policy statement on objects': "DROP POLICY q ON objects;",
  'C3k SET LOCAL session_replication_role': "SET LOCAL session_replication_role = 'replica';",
  'C4b REVOKE on a multi-table list that names subscriptions': 'REVOKE SELECT ON public.users, public.subscriptions FROM authenticated;',
  'C2c quoted schema and table in an ALTER POLICY': 'alter policy "Allow all" on "storage"."objects" with check (true);',
  'C3e quoted ALTER TABLE on progress_photos': 'alter table "public"."progress_photos" rename to "pp2";',
  'C4d quoted GRANT on subscriptions': 'grant select on "public"."subscriptions" to anon;',
};

/// Later migrations the tripwire has been told to accept: file base name -> why the rule is still
/// intact after it AND the file's content hash (`ruleSqlHash`, printed by the failing test). EMPTY at B1
/// (nothing newer exists). Adding an entry is the human re-verification the tripwire exists to force;
/// the reason must say what was re-checked, and editing the file afterwards makes the entry stale.
const Map<String, TripwireAllow> _tripwireAllow = <String, TripwireAllow>{};

Map<String, String> _filesWith(Map<String, String> base, Map<String, String> extra) => <String, String>{...base, ...extra};

/// True when [text] holds [frag] NOT continued by an arithmetic tail or an OR (B-pass P2): a bare
/// `contains` accepts `end_date > now() - interval '30 days'` (a grace window) and `... OR true`.
bool _predicateAnchored(String text, String frag) =>
    RegExp(RegExp.escape(frag) + r'(?!\s*(?:[-+*/:]|OR\b))').hasMatch(text);

void main() {
  late Map<String, String> files;
  late String b1Path;
  late String ruleSql;
  late String arbiterSql;
  late String liveVerifySql;
  late String verifySubscriptionTs;

  setUpAll(() {
    files = loadRuleSqlSources();
    final located = files.keys.where((p) => _ruleFileName.hasMatch(baseName(p))).toList();
    b1Path = located.isEmpty ? '' : located.first;
    ruleSql = b1Path.isEmpty ? '' : files[b1Path]!;
    arbiterSql = File('test/sql/onconflict_live_arbiter.sql').readAsStringSync();
    liveVerifySql = File('test/sql/progress_photos_pro_insert_rule_live_verify.sql').readAsStringSync();
    verifySubscriptionTs = File('supabase/functions/verify-subscription/index.ts').readAsStringSync();
  });

  group('the SQL readers (the pins are only as good as these)', () {
    test('stripSqlAllComments removes -- and nested /* */ comments and leaves string literals alone', () {
      expect(stripSqlAllComments("a -- b\nc"), 'a \nc');
      expect(stripSqlAllComments('a /* b /* c */ d */ e'), 'a   e'); // the comment becomes ONE space
      expect(stripSqlAllComments('ALTER/**/POLICY p'), 'ALTER POLICY p'); // whitespace to Postgres, not nothing
      expect(stripSqlAllComments("x = '-- not a comment' -- real\ny"), "x = '-- not a comment' \ny");
      expect(stripSqlAllComments("x = '/* not */' /* real */ y"), "x = '/* not */'   y");
      expect(stripSqlAllComments("x = 'it''s -- fine' -- c"), "x = 'it''s -- fine' ");
    });

    test('normalizeSql collapses layout, squeezes parentheses and keeps string literals byte-for-byte', () {
      expect(normalizeSql('a  (  b ,\n c )  ;'), 'a(b,c);');
      expect(normalizeSql("x   =  'a  ( b ,  c'  AND  y"), "x = 'a  ( b ,  c' AND y");
      expect(normalizeSql('a -- c\n b /* d */ e'), 'a b e');
      expect(normalizeSql("  x = 'a' ,  y = 'b'  "), "x = 'a',y = 'b'");
    });

    test('normalizeSql collapses ASCII whitespace only: a non-breaking space is NOT whitespace to Postgres', () {
      expect(normalizeSql('a\u00A0b'), 'a\u00A0b');
      expect(normalizeSql('a \t\r\n\f\v b'), 'a b');
      expect(normalizeSql('end_date\u00A0> now()'), isNot(normalizeSql('end_date > now()')));
      expect(normalizeSql('f\u00A0(x)'), 'f\u00A0(x)');
      expect(normalizeSql('f(x)\u00A0;'), 'f(x)\u00A0;');
    });

    test('stripSqlAllComments reads dollar quoting the way Postgres does: a -- line inside a body does NOT hide a closing tag', () {
      // `-- $m$` inside the body CLOSES it (the lexer has no comments inside a dollar-quoted string), so the
      // statement after it is real and must survive stripping.
      const injected = 'DO \$m\$ BEGIN NULL; END\n-- \$m\$; CREATE TEMP TABLE marker(x int); SELECT \$m\$\n\$m\$;';
      final out = stripSqlAllComments(injected);
      expect(out, contains('CREATE TEMP TABLE marker'));
      // an ordinary comment inside a body is still a comment, a comment OUTSIDE bodies mentioning a tag is ignored
      expect(stripSqlAllComments('DO \$m\$ BEGIN -- note\n NULL; END \$m\$;'), 'DO \$m\$ BEGIN \n NULL; END \$m\$;');
      expect(stripSqlAllComments('-- \$m\$ outside\nSELECT 1;'), '\nSELECT 1;');
      // nested tags: the inner body is stripped on its own
      expect(stripSqlAllComments('DO \$a\$ BEGIN EXECUTE \$b\$ SELECT 1 -- c\n \$b\$; END \$a\$;'), 'DO \$a\$ BEGIN EXECUTE \$b\$ SELECT 1 \n \$b\$; END \$a\$;');
      // an identifier ending in `$x$` is not a tag opener, so a later `-- $x$` stays an ordinary comment
      expect(stripSqlAllComments('SELECT a\$x\$ -- \$x\$\n, 2'), 'SELECT a\$x\$ \n, 2');
      // `\$1` and an identifier that ends in a dollar sign are not tags
      expect(stripSqlAllComments('SELECT \$1 -- c\nFROM a\$b -- d\n'), 'SELECT \$1 \nFROM a\$b \n');
      // an unterminated tag leaves the rest as it is (Postgres would refuse the file)
      expect(stripSqlAllComments('SELECT \$x\$ abc -- c'), 'SELECT \$x\$ abc ');
    });

    test('stripSqlAllComments: a double-quoted identifier and an E-string are opaque, so a marker inside them hides nothing', () {
      expect(stripSqlAllComments('SELECT 1 AS "x--"; DROP TRIGGER t ON public.p;'), 'SELECT 1 AS "x--"; DROP TRIGGER t ON public.p;');
      expect(stripSqlAllComments('SELECT 1 AS "x/*"; DROP TRIGGER t ON public.p; -- c'), 'SELECT 1 AS "x/*"; DROP TRIGGER t ON public.p; ');
      expect(stripSqlAllComments('SELECT 1 AS "it\'s"; DROP TRIGGER t ON public.p; -- c'), 'SELECT 1 AS "it\'s"; DROP TRIGGER t ON public.p; ');
      expect(stripSqlAllComments('SELECT 1 AS "a""--b"; DROP TRIGGER t ON public.p;'), 'SELECT 1 AS "a""--b"; DROP TRIGGER t ON public.p;');
      // E'...': a backslash escapes the quote, so the literal runs on and the `--` inside is not a comment
      expect(stripSqlAllComments("SELECT E'\\' -- '; DROP TRIGGER t ON public.p;"), "SELECT E'\\' -- '; DROP TRIGGER t ON public.p;");
      expect(stripSqlAllComments("SELECT e'a\\'b -- c'; SELECT 2;"), "SELECT e'a\\'b -- c'; SELECT 2;");
      // a plain string ends at the quote: the backslash means nothing there, and the comment after it IS a comment
      expect(stripSqlAllComments("SELECT '\\' -- c\nSELECT 2;"), "SELECT '\\' \nSELECT 2;");
      // an identifier ending in E is not an E-string opener
      expect(stripSqlAllComments("SELECT somE'\\' -- c\nSELECT 2;"), "SELECT somE'\\' \nSELECT 2;");
    });

    test('statementText masks a semicolon inside a literal and keeps the rest', () {
      expect(statementText("CREATE POLICY p ON storage.objects WITH CHECK (n = ';' AND b = 'x');"), "CREATE POLICY p ON storage.objects WITH CHECK (n = '\u0001' AND b = 'x');");
      expect(statementText('select 1; select 2;'), 'select 1; select 2;');
    });

    test('executableText unquotes plain identifiers (the style supabase db diff emits) and leaves odd names and literals alone', () {
      expect(executableText('alter policy "p_1" on "storage"."objects" with check (true);'), 'alter policy p_1 on storage.objects with check (true);');
      expect(executableText('create policy "Allow all uploads" on "storage"."objects";'), 'create policy "Allow all uploads" on storage.objects;');
      expect(executableText('select \'"storage"."objects"\';'), 'select \'"storage"."objects"\';');
      expect(executableText('select 1 -- "storage"."objects"\n'), 'select 1 \n');
      expect(executableText('alter table public . progress_photos disable trigger all;'), 'alter table public.progress_photos disable trigger all;');
      expect(executableText('alter table public .progress_photos/**/disable trigger all;'), 'alter table public.progress_photos disable trigger all;');
      expect(executableText('drop policy "a""b" on "public"."t";'), 'drop policy "a""b" on public.t;');
      // an apostrophe inside a quoted identifier does not open a literal that would swallow the statement after it
      expect(executableText('select 1 as "it\'s"; alter table "public"."progress_photos" disable trigger all;'),
          'select 1 as "it\'s"; alter table public.progress_photos disable trigger all;');
    });

    test('nonAsciiInExecutableText finds a code point above U+007F in code and ignores one inside a comment', () {
      expect(nonAsciiInExecutableText('select 1;'), isEmpty);
      expect(nonAsciiInExecutableText('select end_date\u00A0> now();'), ['U+00A0']);
      expect(nonAsciiInExecutableText('select 1; -- \u2500\u2500 a box-drawing comment\n/* \u00A7 */'), isEmpty);
      expect(nonAsciiInExecutableText("select '\u00E9';"), ['U+00E9']);
    });

    test('balancedAfter finds the matching parenthesis through nested parens and parens inside strings', () {
      expect(balancedAfter('f(a, (b), \'x)\') tail', 1), "a, (b), 'x)'");
      expect(balancedAfter('f(a', 1), isNull);
      expect(balancedAfter('f(a, ")" b) tail', 1), 'a, ")" b', reason: 'a parenthesis inside a double-quoted identifier is not structure');
      expect(balancedAfter("f(a, E'\\')' b) tail", 1), "a, E'\\')' b", reason: 'a backslash-escaped quote inside E-string does not end it');
      expect(balancedAfter('f(a)', 0), isNull);
    });

    test('storagePolicyWithChecks reads the WHOLE expression of an ALTER and a CREATE, in order', () {
      const sql = '''
ALTER POLICY "p" ON storage.objects WITH CHECK (a = 1 AND (b = (SELECT 2)));
CREATE POLICY "p" ON storage.objects FOR INSERT TO authenticated WITH CHECK (c = ')' AND d);
CREATE POLICY "other" ON storage.objects FOR INSERT WITH CHECK (zzz);
''';
      expect(storagePolicyWithChecks(sql, 'p'), ['a = 1 AND(b =(SELECT 2))', "c = ')' AND d"]);
    });

    test('functionStatement and triggerStatement return the whole normalised statement', () {
      expect(functionStatement(_fnStmt, 'enforce_progress_photo_pro'), _normFn);
      expect(functionStatement('SELECT 1;', 'enforce_progress_photo_pro'), isNull);
      expect(triggerStatement(_trigStmt, 'trg_progress_photo_pro'), _normTrig);
      expect(triggerStatement('SELECT 1;', 'trg_progress_photo_pro'), isNull);
    });

    test('ddlInventory masks function bodies, skips DO control words and counts any added statement', () {
      expect(ddlInventory(_expectedWhole).join('|'), _expectedInventory.join('|'));
      // a statement INSIDE a function body is not an inventory item
      expect(ddlInventory('SELECT 1 AS "a;b";'), hasLength(1), reason: 'a semicolon inside a quoted identifier does not split the statement');
      expect(ddlInventory(r"CREATE FUNCTION f() RETURNS trigger LANGUAGE plpgsql AS $x$ BEGIN DROP TABLE t; RETURN NEW; END; $x$;"), ['CREATE FUNCTION f']);
      // an added data statement of any kind is an item
      expect(ddlInventory(r'DO $m$ BEGIN INSERT INTO t VALUES (1); END $m$;'), ['INSERT INTO']);
      expect(ddlInventory(r'DO $m$ BEGIN GRANT ALL ON t TO u; END $m$;'), ['GRANT ALL']);
    });

    test('numberedInOrder breaks ties by name (two files share a number) and skips unnumbered files', () {
      expect(numberedInOrder(['a/146b_x.sql', 'a/146_y.sql', 'a/20260328000001_v.sql', 'a/145_z.sql']),
          ['a/145_z.sql', 'a/146_y.sql', 'a/146b_x.sql']);
    });
  });

  group('the rule file (migration 154, draft or applied)', () {
    test('it is defined exactly once across supabase/migrations/ and docs/drafts/ (E7)', () {
      expect(ruleDefinitionViolations(files), isEmpty);
    });

    test('every pin holds on the real text: whole file, both policy branches, function, trigger, inventory, rollback', () {
      expect(b1Path, isNotEmpty);
      final v = ruleFileViolations(ruleSql);
      expect(v, isEmpty, reason: 'violated pins for $b1Path: $v');
    });

    test('the rule file and the live-verify file hold no code point above U+007F outside comments', () {
      expect(nonAsciiInExecutableText(ruleSql), isEmpty);
      expect(nonAsciiInExecutableText(liveVerifySql), isEmpty);
    });

    test('the expected whole-file literal is internally consistent (the pieces are the whole)', () {
      expect(_expectedWhole, contains(_normFn));
      expect(_expectedWhole, contains(_normTrig));
      expect(_expectedWhole, contains(_normPolicyExpr));
      expect(_normPolicyExpr, contains("s.status = 'active'"));
      expect(_normPolicyExpr, contains('s.end_date > now()'));
    });

    test('S1: the rule defined twice (draft AND real file) or by two files is refused', () {
      final both = _filesWith(files, <String, String>{
        'supabase/migrations/154_progress_photos_pro_insert_rls_rule.sql': ruleSql,
        'docs/drafts/154_progress_photos_pro_insert_rls_rule.sql': ruleSql,
      });
      expect(ruleDefinitionViolations(both), isNotEmpty);
      final twice = _filesWith(files, <String, String>{'supabase/migrations/155_progress_photos_pro_insert_rls_rule.sql': ruleSql});
      expect(ruleDefinitionViolations(twice), isNotEmpty);
      final none = <String, String>{...files}..removeWhere((k, _) => _ruleFileName.hasMatch(baseName(k)));
      expect(ruleDefinitionViolations(none), isNotEmpty);
    });

    test('E7 isolated: the trigger defined by a file that does NOT carry the rule\'s name is refused (by content alone)', () {
      final sets = _filesWith(files, <String, String>{'docs/drafts/zzz_copy.sql': 'CREATE TRIGGER trg_progress_photo_pro BEFORE INSERT ON public.progress_photos FOR EACH ROW EXECUTE FUNCTION public.f();'});
      expect(ruleDefinitionViolations(sets), isNotEmpty);
    });

    test('E7 isolated: a SECOND file carrying the rule\'s name but not its text is refused (by name alone)', () {
      final sets = _filesWith(files, <String, String>{'docs/drafts/155_progress_photos_pro_insert_rls_rule.sql': 'SELECT 1;'});
      expect(ruleDefinitionViolations(sets), isNotEmpty);
    });

    test('E7 isolated: the rule defined only under another name (no file by the rule\'s name) is refused (by name alone)', () {
      final sets = <String, String>{...files}..removeWhere((k, _) => _ruleFileName.hasMatch(baseName(k)));
      sets['docs/drafts/zzz_other_name.sql'] = ruleSql;
      expect(ruleDefinitionViolations(sets), isNotEmpty);
    });

    for (final m in _ruleMutants) {
      test('mutant ${m.id}: ${m.what}', () {
        final mutated = _mutate(ruleSql, m.edits);
        final v = ruleFileViolations(mutated);
        if (m.wholeFile) expect(v, contains('whole-file'), reason: 'mutant ${m.id} slipped past the whole-file pin');
        expect(v, isNotEmpty, reason: 'mutant ${m.id} slipped past every pin');
        for (final pin in m.pins) {
          expect(v, contains(pin), reason: 'mutant ${m.id} did not trip the specific pin "$pin"; tripped $v');
        }
      });
    }

    test('the mutants reach every statement of the migration (a guard against a mutant list that rots)', () {
      expect(_ruleMutants.length, greaterThanOrEqualTo(40));
      final ids = _ruleMutants.map((m) => m.id).toSet();
      for (final id in ['T1', 'T9', 'T10', 'T13', 'T15', 'P1', 'P6', 'P10', 'P11', 'P12', 'S2', 'D1', 'R1', 'R3', 'N1', 'N2', 'N3']) {
        expect(ids, contains(id));
      }
    });
  });

  group('later migrations cannot weaken the rule (D3b tripwire, E5 no second door, E6 subscriptions policies)', () {
    test('nothing newer than the rule touches the protected set without a current, reasoned acknowledgement', () {
      expect(_tripwireStateViolations(files, b1Path, _tripwireAllow), isEmpty,
          reason: 'every _tripwireAllow entry must name an existing file newer than the rule, say what was re-verified and carry its current hash');
    });

    test('the state check reports a bad allow-list entry even when no migration touches the rule (a stale entry cannot sit there silently)', () {
      final stale = <String, TripwireAllow>{
        '999_gone.sql': const TripwireAllow(reason: 'verified by hand: this file used to exist, test only', contentHash: '0000000000000000'),
      };
      expect(_tripwireStateViolations(files, b1Path, stale).join(), contains('no such file'));
    });

    test('every unnumbered .sql file is in the known baseline (a new timestamp-named file cannot dodge "newer")', () {
      final unnumbered = files.keys.map(baseName).where((n) => migrationNumberOf(n) == null).toSet();
      expect(unnumbered.difference(unnumberedSqlBaseline), isEmpty);
    });

    for (final e in _laterMigrations.entries) {
      test('tripwire: ${e.key}', () {
        final sets = _filesWith(files, <String, String>{'supabase/migrations/155_later.sql': e.value});
        final v = tripwireViolations(sets, b1Path: b1Path);
        expect(v, isNotEmpty, reason: 'a later migration "${e.key}" did not trip the tripwire');
      });
    }

    for (final e in _laterMigrationsIsolated.entries) {
      test('tripwire (isolated alternative): ${e.key}', () {
        final sets = _filesWith(files, <String, String>{'supabase/migrations/155_later.sql': e.value});
        expect(tripwireViolations(sets, b1Path: b1Path), isNotEmpty, reason: '"${e.key}" did not trip the tripwire');
      });
    }

    test('tripwire: a file that SHARES the rule\'s number (a letter suffix, or a second file) is "newer or equal", not exempt', () {
      final number = baseName(b1Path).substring(0, 3);
      final sets = _filesWith(files, <String, String>{
        'supabase/migrations/${number}b_shares_the_number.sql': 'DROP TRIGGER trg_progress_photo_pro ON public.progress_photos;',
      });
      expect(tripwireViolations(sets, b1Path: b1Path), isNotEmpty);
    });

    test('tripwire: a later migration that only MENTIONS the rule inside comments is clean', () {
      final sets = _filesWith(files, <String, String>{
        'supabase/migrations/155_later.sql': '-- DROP TRIGGER trg_progress_photo_pro ON public.progress_photos;\n/* DROP POLICY x ON storage.objects; */\nSELECT 1;',
      });
      expect(tripwireViolations(sets, b1Path: b1Path), isEmpty);
    });

    test('tripwire: an EARLIER migration is not flagged (only files newer than the rule are)', () {
      final sets = _filesWith(files, <String, String>{'supabase/migrations/100z_earlier.sql': "CREATE POLICY p ON storage.objects FOR SELECT USING (bucket_id = 'x');"});
      expect(tripwireViolations(sets, b1Path: b1Path), isEmpty);
    });

    test('tripwire: an allow-list entry acknowledges one file and nothing else', () {
      const ack = 'DROP TRIGGER trg_progress_photo_pro ON public.progress_photos;';
      final sets = _filesWith(files, <String, String>{
        'supabase/migrations/155_ack.sql': ack,
        'supabase/migrations/156_not_ack.sql': ack,
      });
      final allow = <String, TripwireAllow>{
        '155_ack.sql': TripwireAllow(reason: 'verified by hand: the trigger is re-created in the same file, test only', contentHash: ruleSqlHash(ack)),
      };
      final v = tripwireViolations(sets, b1Path: b1Path, allow: allow);
      expect(v.where((l) => l.startsWith('155_ack.sql')), isEmpty);
      expect(v.where((l) => l.startsWith('156_not_ack.sql')), isNotEmpty);
      expect(allowListIssues(sets, allow, b1Path: b1Path), isEmpty);
    });

    test('tripwire: an acknowledgement goes STALE when the acknowledged file is edited (the entry cannot outlive its verification)', () {
      const ack = 'DROP TRIGGER trg_progress_photo_pro ON public.progress_photos;';
      final allow = <String, TripwireAllow>{
        '155_ack.sql': TripwireAllow(reason: 'verified by hand: the trigger is re-created in the same file, test only', contentHash: ruleSqlHash(ack)),
      };
      final edited = _filesWith(files, <String, String>{'supabase/migrations/155_ack.sql': '$ack\nDROP FUNCTION public.enforce_progress_photo_pro();'});
      final v = tripwireViolations(edited, b1Path: b1Path, allow: allow);
      expect(v.where((l) => l.startsWith('155_ack.sql')), isNotEmpty, reason: 'an edited file must lose its acknowledgement');
      expect(v.join('\n'), contains('stale'));
      expect(allowListIssues(edited, allow, b1Path: b1Path).join('\n'), contains('changed since it was acknowledged'));
    });

    test('allowListIssues: a stale name, a reason that says nothing and a file older than the rule are each reported', () {
      const text = 'SELECT 1;';
      final sets = _filesWith(files, <String, String>{'supabase/migrations/155_ok.sql': text, 'supabase/migrations/100z_older.sql': text});
      final h = ruleSqlHash(text);
      const longReason = 'verified by hand: nothing in this file touches the rule, test only';
      expect(allowListIssues(sets, {'155_ok.sql': TripwireAllow(reason: longReason, contentHash: h)}, b1Path: b1Path), isEmpty);
      expect(allowListIssues(sets, {'999_missing.sql': TripwireAllow(reason: longReason, contentHash: h)}, b1Path: b1Path).join(), contains('no such file'));
      expect(allowListIssues(sets, {'155_ok.sql': TripwireAllow(reason: 'ok', contentHash: h)}, b1Path: b1Path).join(), contains('under 40 characters'));
      expect(allowListIssues(sets, {'100z_older.sql': TripwireAllow(reason: longReason, contentHash: h)}, b1Path: b1Path).join(), contains('not a file newer than the rule'));
    });

    test('ruleSqlHash is 16 hex digits, deterministic, and changes with any edit', () {
      expect(ruleSqlHash('abc'), matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(ruleSqlHash('abc'), ruleSqlHash('abc'));
      expect(ruleSqlHash('abc'), isNot(ruleSqlHash('abd')));
      expect(ruleSqlHash(''), 'cbf29ce484222325');
    });

    test('tripwire L16: a NEW unnumbered .sql file that is not in the baseline is refused', () {
      final sets = _filesWith(files, <String, String>{'supabase/migrations/zz_new.sql': 'SELECT 1;'});
      expect(tripwireViolations(sets, b1Path: b1Path), isNotEmpty);
    });

    test('E5 no second door: on the real tree every INSERT/ALL policy on storage.objects names a bucket and only the rule names progress-photos', () {
      expect(secondDoorViolations(files, b1Path: b1Path), isEmpty);
    });

    test('E5 mutants: an unscoped INSERT policy, a default-ALL policy and a second progress-photos door are refused', () {
      final unscoped = _filesWith(files, <String, String>{'supabase/migrations/155_x.sql': 'CREATE POLICY u ON storage.objects FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);'});
      expect(secondDoorViolations(unscoped, b1Path: b1Path), isNotEmpty);
      final unqualified = _filesWith(files, <String, String>{'supabase/migrations/155_x.sql': 'SET search_path = storage; CREATE POLICY u ON objects FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);'});
      expect(secondDoorViolations(unqualified, b1Path: b1Path), isNotEmpty, reason: 'B-pass: an unqualified objects after SET search_path is still storage.objects');
      final defaultAll = _filesWith(files, <String, String>{'supabase/migrations/155_x.sql': 'CREATE POLICY u ON storage.objects TO authenticated WITH CHECK (true);'});
      expect(secondDoorViolations(defaultAll, b1Path: b1Path), isNotEmpty);
      final second = _filesWith(files, <String, String>{
        'supabase/migrations/155_x.sql': "CREATE POLICY u ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'progress-photos');",
      });
      expect(secondDoorViolations(second, b1Path: b1Path), isNotEmpty);
      final scopedElsewhere = _filesWith(files, <String, String>{
        'supabase/migrations/155_x.sql': "CREATE POLICY u ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'some-other-bucket');",
      });
      expect(secondDoorViolations(scopedElsewhere, b1Path: b1Path), isEmpty);
      final selectOnly = _filesWith(files, <String, String>{'supabase/migrations/155_x.sql': 'CREATE POLICY u ON storage.objects FOR SELECT USING (true);'});
      expect(secondDoorViolations(selectOnly, b1Path: b1Path), isEmpty);
    });

    test('E5 spaced and quoted names (how the dashboard and `supabase db diff` write them) are read, not skipped', () {
      final unscoped = _filesWith(files, <String, String>{
        'supabase/migrations/155_x.sql': 'CREATE POLICY "Allow all inserts" ON storage.objects FOR INSERT TO authenticated WITH CHECK (true);'
      });
      expect(secondDoorViolations(unscoped, b1Path: b1Path).join(), contains('Allow all inserts'));
      final quoted = _filesWith(files, <String, String>{
        'supabase/migrations/155_x.sql': 'create policy "allow_all" on "storage"."objects" for insert to authenticated with check (true);'
      });
      expect(secondDoorViolations(quoted, b1Path: b1Path), isNotEmpty);
      final doorByName = _filesWith(files, <String, String>{
        'supabase/migrations/155_x.sql': 'CREATE POLICY "Let anyone upload progress photos" ON storage.objects FOR INSERT WITH CHECK (bucket_id = \'progress-photos\');'
      });
      expect(secondDoorViolations(doorByName, b1Path: b1Path).join(), contains('second door'));
      final scoped = _filesWith(files, <String, String>{
        'supabase/migrations/155_x.sql': 'CREATE POLICY "Allow uploads to avatars" ON storage.objects FOR INSERT WITH CHECK (bucket_id = \'avatars\');'
      });
      expect(secondDoorViolations(scoped, b1Path: b1Path), isEmpty);
    });

    test('E5/E6 readers do not skip a final statement with no semicolon, a "" name, or a statement with a semicolon in a string', () {
      final noSemi = _filesWith(files, <String, String>{'supabase/migrations/155_x.sql': 'CREATE POLICY u ON storage.objects FOR INSERT TO authenticated WITH CHECK (true)'});
      expect(secondDoorViolations(noSemi, b1Path: b1Path), isNotEmpty, reason: 'a last statement without a semicolon is still a statement');
      final quoteName = _filesWith(files, <String, String>{'supabase/migrations/155_x.sql': 'CREATE POLICY "x""y" ON storage.objects FOR INSERT TO authenticated WITH CHECK (true);'});
      expect(secondDoorViolations(quoteName, b1Path: b1Path), isNotEmpty);
      final semiInString = _filesWith(files, <String, String>{
        'supabase/migrations/155_x.sql': "CREATE POLICY u ON storage.objects FOR INSERT TO authenticated WITH CHECK (note <> ';' AND bucket_id = 'progress-photos');",
      });
      expect(secondDoorViolations(semiInString, b1Path: b1Path).join(), contains('second door'));
      expect(subscriptionsEffectivePolicies(<String, String>{'155_a.sql': 'CREATE POLICY "x""y" ON public.subscriptions FOR ALL TO authenticated USING (true)'}).values, ['ALL']);
    });

    test('E6 spaced and quoted subscriptions policy names are tracked through CREATE and DROP', () {
      const create = 'CREATE POLICY "Users manage own subs" ON "public"."subscriptions" FOR ALL TO authenticated USING (true);';
      const drop = 'DROP POLICY IF EXISTS "Users manage own subs" ON "public"."subscriptions";';
      expect(subscriptionsEffectivePolicies(<String, String>{'155_a.sql': create}), containsPair('Users manage own subs', 'ALL'));
      expect(subscriptionsEffectivePolicies(<String, String>{'155_a.sql': create, '156_b.sql': drop}), isEmpty);
    });

    test('E5 D2b: the SAME policy name re-created in ANOTHER file is a second door, not the rule', () {
      final sets = _filesWith(files, <String, String>{
        'supabase/migrations/155_x.sql': 'CREATE POLICY "progress_photos_insert_own" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = \'progress-photos\');',
      });
      expect(secondDoorViolations(sets, b1Path: b1Path), isNotEmpty);
    });

    test('E5 D6: an UNNUMBERED file (the never-applied combined dump) is not read by the second-door pin', () {
      final sets = _filesWith(files, <String, String>{
        'supabase/migrations/zz_unapplied.sql': 'CREATE POLICY u ON storage.objects FOR INSERT TO authenticated WITH CHECK (true);',
      });
      expect(secondDoorViolations(sets, b1Path: b1Path), isEmpty);
    });

    test('E6: public.subscriptions has exactly ONE policy, SELECT, after every migration plus the rule (no client write path)', () {
      expect(subscriptionsEffectivePolicies(files), <String, String>{'subscriptions_select_own': 'SELECT'});
    });

    test('S2/E6: without the rule\'s DROP of users_own_subscriptions the repo history leaves a FOR ALL self-grant policy', () {
      final mutated = _mutate(ruleSql, const [_Edit('  DROP POLICY IF EXISTS "users_own_subscriptions" ON public.subscriptions;\n', '')]);
      final sets = <String, String>{...files, b1Path: mutated};
      final eff = subscriptionsEffectivePolicies(sets);
      expect(eff['users_own_subscriptions'], 'ALL');
      expect(eff, isNot(<String, String>{'subscriptions_select_own': 'SELECT'}));
    });

    test('E6: the effective policy set follows (number, name) ORDER, not insertion order', () {
      final created = 'CREATE POLICY ordered ON public.subscriptions FOR INSERT WITH CHECK (true);';
      const dropped = 'DROP POLICY ordered ON public.subscriptions;';
      // created in 155, dropped in 156: the policy is gone, whichever order the map holds the files in
      expect(subscriptionsEffectivePolicies(<String, String>{'156_b.sql': dropped, '155_a.sql': created}), isEmpty);
      expect(subscriptionsEffectivePolicies(<String, String>{'155_a.sql': created, '156_b.sql': dropped}), isEmpty);
      // dropped in 155, created in 156: the policy is present
      expect(subscriptionsEffectivePolicies(<String, String>{'156_b.sql': created, '155_a.sql': dropped}), containsPair('ordered', 'INSERT'));
    });

    test('E6 mutants: a later write policy, a re-created self-grant and a missing SELECT policy are all visible', () {
      final write = _filesWith(files, <String, String>{'supabase/migrations/155_x.sql': 'CREATE POLICY w ON public.subscriptions FOR INSERT WITH CHECK (true);'});
      expect(subscriptionsEffectivePolicies(write), containsPair('w', 'INSERT'));
      final allPolicy = _filesWith(files, <String, String>{'supabase/migrations/155_x.sql': 'CREATE POLICY a ON public.subscriptions USING (true);'});
      expect(subscriptionsEffectivePolicies(allPolicy), containsPair('a', 'ALL'));
      final noSelect = _filesWith(files, <String, String>{'supabase/migrations/155_x.sql': 'DROP POLICY subscriptions_select_own ON public.subscriptions;'});
      expect(subscriptionsEffectivePolicies(noSelect), isEmpty);
      final serviceOnly = _filesWith(files, <String, String>{'supabase/migrations/155_x.sql': 'CREATE POLICY s ON public.subscriptions FOR ALL TO service_role USING (true);'});
      expect(subscriptionsEffectivePolicies(serviceOnly), <String, String>{'subscriptions_select_own': 'SELECT'});
    });
  });

  group('the predicate is the server\'s one definition of PRO (E3, X1)', () {
    test('B-pass P2 mutants: a grace window, a cast and an OR tail after the predicate are not the predicate', () {
      const frag = "status = 'active' AND end_date > now()";
      expect(_predicateAnchored("WHERE $frag)", frag), isTrue);
      expect(_predicateAnchored("WHERE $frag AND user_id = x", frag), isTrue);
      expect(_predicateAnchored("WHERE $frag - interval '30 days')", frag), isFalse);
      expect(_predicateAnchored("WHERE $frag::timestamptz)", frag), isFalse);
      expect(_predicateAnchored("WHERE $frag OR true)", frag), isFalse);
    });

    test('verify-subscription reads status = active and end_date > now, as the rule does', () {
      expect(verifySubscriptionPredicateViolations(verifySubscriptionTs), isEmpty);
    });

    test('the rule\'s predicate text is the one the LIVE definition of each cap function reads (the last CREATE OR REPLACE wins)', () {
      const frag = "status = 'active' AND end_date > now()";
      // the rule's own text, from the file under test (not from this test's hand-written literal)
      expect(_predicateAnchored(normalizeSql(functionStatement(ruleSql, 'enforce_progress_photo_pro') ?? ''), frag), isTrue);
      expect(normalizeSql(ruleSql), contains("s.status = 'active' AND s.end_date > now()"));
      // migration 111's cap functions were replaced by 113/114/127/129/132/153: read the highest-numbered
      // definer of each (test/helpers/migration_cap_reader.dart), never the first one that mentioned it
      for (final fn in const <String>[
        'enforce_chat_app_daily_limit',
        'enforce_vision_analysis_daily_limit',
        'enforce_food_text_daily_limit',
      ]) {
        final file = latestMigrationDefining(fn);
        expect(file, isNotNull, reason: '$fn has no defining migration');
        final block = functionBlock(file!.readAsStringSync(), fn);
        expect(block, isNotNull, reason: '$fn body not found in ${file.path}');
        expect(_predicateAnchored(normalizeSql(block!), frag), isTrue,
            reason: '$fn (live definition: ${file.path}) no longer reads the PRO predicate the rule uses');
      }
    });

    test('the server\'s other copies of the predicate agree: migration 111, the shared Edge helper, and the client readers (presence pins)', () {
      final m111 = normalizeSql(File('supabase/migrations/111_chat_vision_daily_cap_triggers.sql').readAsStringSync());
      expect(_predicateAnchored(m111, "status = 'active' AND end_date > now()"), isTrue);
      final shared = File('supabase/functions/_shared/subscription.ts').readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      // both PRO reads (fetchProUserIds, isProUser) filter status = active AND end_date strictly after now;
      // `fetchLatestActiveEndByUser` legitimately uses `.gte` (a window of expiries), so it is not counted
      // the ARGUMENT is pinned too (Hermes L1 F2): `.gt("end_date", <now minus a grace>)` must not pass
      expect(shared, contains('const cutoffIso = new Date().toISOString(); '), reason: 'fetchProUserIds pins its cutoff to the clock, with no offset');
      expect(shared, contains('.eq("status", "active") .gt("end_date", cutoffIso)'), reason: 'fetchProUserIds: status = active AND end_date > now');
      expect(shared, contains('.eq("status", "active") .gt("end_date", new Date().toISOString())'), reason: 'isProUser: status = active AND end_date > now');
      // The client reads `status = 'active'` and compares end_date with the clock itself (proStateSnapshot): a
      // different shape of the same predicate, so these two are PRESENCE pins that a status literal is still there.
      final client = File('lib/core/services/subscription_service.dart').readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      expect(client, contains(".eq('status', 'active') .order('end_date', ascending: false)"));
      final razorpay = File('lib/core/services/razorpay_service.dart').readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      expect(".eq('status', 'active')".allMatches(razorpay).length, greaterThanOrEqualTo(2));
    });

    test('X1: a changed status literal, a dropped end_date select or a changed comparison in verify-subscription is flagged', () {
      expect(verifySubscriptionPredicateViolations(verifySubscriptionTs.replaceFirst('.eq("status", "active")', '.eq("status", "trialing")')), isNotEmpty);
      expect(verifySubscriptionPredicateViolations(verifySubscriptionTs.replaceFirst('.select("plan, status, end_date")', '.select("plan, status")')), isNotEmpty);
      expect(verifySubscriptionPredicateViolations(verifySubscriptionTs.replaceFirst('expiresAt.getTime() > Date.now()', 'expiresAt.getTime() >= Date.now()')), isNotEmpty);
      expect(verifySubscriptionPredicateViolations(verifySubscriptionTs.replaceFirst('expiresAt.getTime() > Date.now()', '// expiresAt.getTime() > Date.now()\n    true')), isNotEmpty);
    });

    test('X1b Hermes L1 F1 mutants: a grace window, a constant is_pro and a dropped user filter are each flagged', () {
      String once(String from, String to) {
        expect(from.allMatches(verifySubscriptionTs).length, 1, reason: 'mutant anchor `$from` must match exactly once');
        return verifySubscriptionTs.replaceFirst(from, to);
      }
      expect(verifySubscriptionPredicateViolations(once('expiresAt.getTime() > Date.now()', 'expiresAt.getTime() > Date.now() - GRACE_MS')), isNotEmpty);
      expect(verifySubscriptionPredicateViolations(once('is_pro: isActive,', 'is_pro: true,')), isNotEmpty);
      expect(verifySubscriptionPredicateViolations(once('.eq("user_id", userId)\n', '')), isNotEmpty);
      expect(verifySubscriptionPredicateViolations(once('.limit(1)', '.limit(5)')), isNotEmpty);
    });
  });

  group('the live arbiter script survives the rule (D11, E9)', () {
    test('case 16 seeds an active subscription before its photo INSERT and removes it right after, inside its own block', () {
      expect(arbiterCase16Violations(arbiterSql), isEmpty);
    });

    test('A1 the seed removed', () {
      final m = _mutate(arbiterSql, const [
        _Edit("    INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date)\n      VALUES (v_user, 'monthly', 'active', v_now, v_now + interval '30 days');\n    INSERT INTO public.progress_photos", '    INSERT INTO public.progress_photos')
      ]);
      expect(arbiterCase16Violations(m), isNotEmpty);
    });

    test('A2 the seed after the photo INSERT', () {
      final m = _mutate(arbiterSql, const [
        _Edit("    INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date)\n      VALUES (v_user, 'monthly', 'active', v_now, v_now + interval '30 days');\n", ''),
        _Edit("    DELETE FROM public.subscriptions WHERE user_id = v_user;\n",
            "    INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date)\n      VALUES (v_user, 'monthly', 'active', v_now, v_now + interval '30 days');\n    DELETE FROM public.subscriptions WHERE user_id = v_user;\n"),
      ]);
      expect(arbiterCase16Violations(m), isNotEmpty);
    });

    test('A3b Hermes L14 F3: the photo INSERT without its ON CONFLICT arbiter, or with another arbiter, is flagged', () {
      final dropped = _mutate(arbiterSql, const [_Edit('      ON CONFLICT (id) DO UPDATE SET storage_path = EXCLUDED.storage_path;\n    DELETE FROM public.subscriptions WHERE user_id = v_user;', ';\n    DELETE FROM public.subscriptions WHERE user_id = v_user;')]);
      expect(arbiterCase16Violations(dropped), isNotEmpty);
      final wrong = _mutate(arbiterSql, const [_Edit('ON CONFLICT (id) DO UPDATE SET storage_path = EXCLUDED.storage_path;\n    DELETE FROM public.subscriptions', 'ON CONFLICT DO NOTHING;\n    DELETE FROM public.subscriptions')]);
      expect(arbiterCase16Violations(wrong), isNotEmpty);
    });

    test('A3 the seed DELETE removed', () {
      final m = _mutate(arbiterSql, const [_Edit('    DELETE FROM public.subscriptions WHERE user_id = v_user;\n', '')]);
      expect(arbiterCase16Violations(m), isNotEmpty);
    });

    test('A4 the seed is not an active row (expired)', () {
      final m = _mutate(arbiterSql, const [_Edit("VALUES (v_user, 'monthly', 'active', v_now, v_now + interval '30 days');", "VALUES (v_user, 'monthly', 'expired', v_now, v_now + interval '30 days');")]);
      expect(arbiterCase16Violations(m), isNotEmpty);
    });

    test('A5 the seed DELETE is not scoped to the seeded user', () {
      final m = _mutate(arbiterSql, const [_Edit('    DELETE FROM public.subscriptions WHERE user_id = v_user;\n', '    DELETE FROM public.subscriptions;\n')]);
      expect(arbiterCase16Violations(m), isNotEmpty);
    });

    test('A7 the seed placed BEFORE the case-16 block opens (it would run, but outside the block that rolls it back)', () {
      final seed = "    INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date)\n      VALUES (v_user, 'monthly', 'active', v_now, v_now + interval '30 days');\n";
      final m = _mutate(arbiterSql, [
        _Edit(seed, ''),
        _Edit('  BEGIN\n    INSERT INTO public.progress_photos', '$seed  BEGIN\n    INSERT INTO public.progress_photos'),
      ]);
      expect(arbiterCase16Violations(m), isNotEmpty);
    });

    test('A8 the seed DELETE placed AFTER the case-16 handler (an exception would leave the seed behind)', () {
      const del = '    DELETE FROM public.subscriptions WHERE user_id = v_user;\n';
      final m = _mutate(arbiterSql, [
        _Edit(del, ''),
        _Edit('  END;\n\n  ----- 17. daily_steps', '  END;\n$del\n  ----- 17. daily_steps'),
      ]);
      expect(arbiterCase16Violations(m), isNotEmpty);
    });

    test('A9 the seed DELETE placed BEFORE the photo INSERT (the photo would then meet a trigger with no subscription)', () {
      const del = '    DELETE FROM public.subscriptions WHERE user_id = v_user;\n';
      final m = _mutate(arbiterSql, [
        _Edit(del, ''),
        _Edit('    INSERT INTO public.progress_photos', '$del    INSERT INTO public.progress_photos'),
      ]);
      expect(arbiterCase16Violations(m), isNotEmpty);
    });

    test('A6 the seed moved out of the case-16 block (into the next case)', () {
      final seed = "    INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date)\n      VALUES (v_user, 'monthly', 'active', v_now, v_now + interval '30 days');\n";
      final m = _mutate(arbiterSql, [
        _Edit(seed, ''),
        _Edit('  ----- 17. daily_steps (user_id, date) ----------------------------------\n', '  ----- 17. daily_steps (user_id, date) ----------------------------------\n$seed'),
      ]);
      expect(arbiterCase16Violations(m), isNotEmpty);
    });
  });

  group('the live-verify SQL file is one always-aborting DO block with no DDL', () {
    test('the real file satisfies every structural pin', () {
      expect(liveVerifyViolations(liveVerifySql), isEmpty);
    });

    test('the always-abort property is pinned structurally: a conditional RAISE, an early RETURN, an outer EXCEPTION clause and a trailing statement are each flagged', () {
      const raise = "  RAISE EXCEPTION 'VERIFY_RESULTS (photos before=%)%', v_before_photos, E'\\n' || v_results;\nEND\n\$v\$;";
      expect(liveVerifySql, contains(raise), reason: 'sanity: the mutants below edit this text');
      final conditional = _mutate(liveVerifySql, [_Edit(raise, "  IF false THEN\n  RAISE EXCEPTION 'VERIFY_RESULTS (photos before=%)%', v_before_photos, E'\\n' || v_results;\n  END IF;\nEND\n\$v\$;")]);
      expect(liveVerifyViolations(conditional), contains('the always-aborting RAISE is not the last statement of the DO block'));
      final early = _mutate(liveVerifySql, [_Edit("  -- Always abort: nothing above commits.", "  RETURN;\n  -- Always abort: nothing above commits.")]);
      expect(liveVerifyViolations(early), contains('contains RETURN (an exit before the abort)'));
      final handler = _mutate(liveVerifySql, [_Edit(raise, "  RAISE EXCEPTION 'VERIFY_RESULTS (photos before=%)%', v_before_photos, E'\\n' || v_results;\nEXCEPTION WHEN OTHERS THEN NULL;\nEND\n\$v\$;")]);
      expect(liveVerifyViolations(handler), contains('the always-aborting RAISE is not the last statement of the DO block'));
      final trailing = _mutate(liveVerifySql, [_Edit(raise, '$raise\nSELECT 1;')]);
      expect(liveVerifyViolations(trailing), contains('the always-aborting RAISE is not the last statement of the DO block'));
    });

    test('mutants: a second DO block, a COMMIT, DDL, a missing abort, an unclosed role window and a missing case are flagged', () {
      expect(liveVerifyViolations('$liveVerifySql\nDO \$x\$ BEGIN NULL; END \$x\$;'), isNotEmpty);
      const upd = '  UPDATE public.subscriptions';
      expect(liveVerifyViolations(_mutate(liveVerifySql, const [_Edit(upd, '  COMMIT;\n$upd', count: 5)])), isNotEmpty);
      expect(liveVerifyViolations(_mutate(liveVerifySql, const [_Edit(upd, '  DROP POLICY progress_photos_insert_own ON storage.objects;\n$upd', count: 5)])), isNotEmpty);
      expect(liveVerifyViolations(_mutate(liveVerifySql, const [_Edit("RAISE EXCEPTION 'VERIFY_RESULTS (photos", "RAISE NOTICE 'VERIFY_RESULTS (photos")])), isNotEmpty);
      expect(liveVerifyViolations(_mutate(liveVerifySql, const [_Edit('    RESET ROLE;\n', '', count: 20)])), isNotEmpty);
      expect(liveVerifyViolations(_mutate(liveVerifySql, [const _Edit('ORDER BY u.id', 'ORDER BY\u00A0u.id')])), contains('non-ascii-in-code'));
      for (final id in ['V3e', 'V3f', 'V4f', 'V6c', 'V6d', 'V7b', 'V8f']) {
        expect(liveVerifyViolations(_mutate(liveVerifySql, [_Edit("E'$id=ok\\n'", "E'$id=skipped\\n'")])), isNotEmpty,
            reason: 'a live-verify file that lost case $id must be flagged');
      }
      expect(liveVerifyViolations(_mutate(liveVerifySql, const [_Edit('GET DIAGNOSTICS v_rows = ROW_COUNT;', 'v_rows := 1;', count: 6)])), isNotEmpty);
    });

    test('Hermes L2 F3 mutant: V8c reverted to the qual-only check is flagged', () {
      final qualOnly = _mutate(liveVerifySql, const [
        _Edit("     AND (coalesce(qual, '') !~ 'bucket_id = ''[^'']+'''\n          OR coalesce(with_check, qual, '') !~ 'bucket_id = ''[^'']+''');",
            "     AND coalesce(qual, '') !~ 'bucket_id = ''[^'']+''';")
      ]);
      expect(liveVerifyViolations(qualOnly), contains('V8c does not check the new-row WITH CHECK of UPDATE/ALL policies'));
      expect(liveVerifyViolations(liveVerifySql), isEmpty);
    });
  });
}
