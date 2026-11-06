// OI-199 + OI-471 (diagnose b3e7d2, migration 172): cleanup_cron_call_log() keeps, for EVERY function_name, its newest
// success row and its newest row of any status; the orphan pruner cron_call_log_cleanup_7d() is dropped and never named again.
//
// SCOPE, stated plainly: this is a SOURCE-SHAPE pin (presence), no database. The behaviour (what the function really deletes,
// what alert_cron_function_dead does with it over nine nights, the live security envelope) is proved by
// test/sql/cleanup_cron_call_log_per_function_verify.sql, run by test/sql/cleanup_cron_call_log_per_function_local.sh in a
// local container (no CI gate runs that container; it is a rehearsal, like the other *_local.sh harnesses).
// What this file pins:
//  * the LATEST definition: the keep-set shape (inside the balanced NOT IN list, too narrow AND too wide), the security envelope
//    and the grants, and the WHOLE function text (whitespace-insensitive, comments stripped) equal to migration 172's, so any
//    change to a catastrophic-tier function is a deliberate edit of this pin;
//  * no later migration may run DDL on the function in a form the resolver cannot read (a quoted name, a DO-block EXECUTE, a
//    DROP, a COMMENT, a GRANT or a schema-wide GRANT/REVOKE); a later migration that only CALLS it (job 41) is fine;
//  * the orphan's DROP form and that nothing names it afterwards; rollback block 1 equals the 169 function (header and body);
//  * the md5 and byte length of the raw function text, the value the live apply asserts.
// The mutation fixtures are frozen on migration 172's own text, so they keep proving each check after a legitimate 173.
@TestOn('vm')
library;

import 'dart:convert' show utf8;
import 'dart:io';

import 'package:crypto/crypto.dart' show md5;
import 'package:test/test.dart';

import '../helpers/cron_call_log_windows.dart' show readRetentionDays;
import '../helpers/cron_job_body_reader.dart'
    show numberedMigrations, stripSqlLineComments;
import '../helpers/migration_cap_reader.dart'
    show latestMigrationDefining, migrationNumber;

const _m172 = 'supabase/migrations/172_cron_call_log_per_function_keep.sql';
const _m169 = 'supabase/migrations/169_cron_call_log_retention_10d.sql';
const _harness = 'test/sql/cleanup_cron_call_log_per_function_local.sh';
const _plan = 'docs/plans/cron-log-retention-oi199-oi471.md';

/// md5 and byte length of the raw text between the two `$fn$` tags of migration 172 (leading and trailing newline included).
/// The live apply asserts `md5(prosrc)` and `length(prosrc)` against exactly these.
const _bodyMd5 = '6597e3e24f91126b6268b3d54aa7ea57';
const _bodyLen = 460;

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

String _lf(String s) => s.replaceAll('\r\n', '\n');

/// The text between the name and the closing `$fn$;` of the LAST `CREATE OR REPLACE FUNCTION cleanup_cron_call_log` in
/// [stripped] (comments already removed), or null.
String? _lastDefinition(String stripped) {
  final all = RegExp(
    r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public\.)?cleanup_cron_call_log\b(.*?)\$fn\$;',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(stripped).toList();
  return all.isEmpty ? null : all.last.group(1);
}

/// The raw text between the real (non-comment) `AS $fn$` line and the `$fn$;` line, leading and trailing newline included.
String? _rawFnBody(String sql) {
  final m = RegExp(
    r'^AS \$fn\$\n(.*?\n)\$fn\$;',
    multiLine: true,
    dotAll: true,
  ).firstMatch(_lf(sql));
  return m == null ? null : '\n${m.group(1)}';
}

/// The text inside the parentheses that open at [open] (the index of a `(`), or null when they never close.
String? _balanced(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') {
      depth--;
      if (depth == 0) return s.substring(open + 1, i);
    }
  }
  return null;
}

final _arm = RegExp(
  r"\(\s*SELECT\s+DISTINCT\s+ON\s*\(\s*function_name\s*\)\s+id\s+FROM\s+public\.cron_call_log\s+"
  r"(WHERE\s+status\s*=\s*'success'\s+)?"
  r"ORDER\s+BY\s+function_name\s*,\s*started_at\s+DESC\s*,\s*id\s+DESC\s*\)",
  caseSensitive: false,
);

/// Problems with the keep-set of the `cleanup_cron_call_log` definition in [migrationSql]; empty means the shape is right.
/// Too NARROW (an arm lost, a filter dropped) and too WIDE (an extra arm, UNION ALL, a whole-table SELECT in the list) both fail.
/// This looks INSIDE the `NOT IN (...)` list only; [bodyDriftProblems] pins everything around it.
List<String> keepSetProblems(String migrationSql) {
  final problems = <String>[];
  final sql = stripSqlLineComments(_lf(migrationSql));
  final body = _lastDefinition(sql);
  if (body == null) {
    return [
      'no CREATE OR REPLACE FUNCTION cleanup_cron_call_log ... \$fn\$; block',
    ];
  }
  final retention = readRetentionDays(migrationSql);
  if (retention != 10.0) {
    problems.add('retention is $retention days, expected 10');
  }
  final notIn = RegExp(
    r'AND\s+id\s+NOT\s+IN\s*\(',
    caseSensitive: false,
  ).firstMatch(body);
  if (notIn == null) {
    problems.add('the keep-set is not an `AND id NOT IN (` filter');
    return problems;
  }
  final inner = _balanced(body, notIn.end - 1);
  if (inner == null) {
    problems.add('the parentheses of the NOT IN list never close');
    return problems;
  }
  final arms = _arm.allMatches(inner).toList();
  if (arms.length != 2) {
    problems.add(
      'expected exactly 2 `DISTINCT ON (function_name)` arms inside the NOT IN list, ordered '
      '`function_name, started_at DESC, id DESC`, found ${arms.length}',
    );
    return problems;
  }
  final filtered = arms.where((m) => m.group(1) != null).toList();
  // The regex is case-insensitive for identifiers; the status LITERAL must still be exactly lower-case 'success'.
  final exact = filtered.where((m) => m.group(1)!.contains("'success'")).length;
  if (filtered.length != exact) {
    problems.add("the status literal must be exactly 'success' in lower case");
  }
  if (exact != 1) {
    problems.add(
      "exactly one arm must filter `status = 'success'`, found $exact",
    );
  }
  var rest = inner;
  for (final m in arms.reversed) {
    rest = rest.replaceRange(m.start, m.end, '');
  }
  if (_flat(rest).toUpperCase() != 'SELECT ID FROM ( UNION ) AS KEEP_ROWS') {
    problems.add(
      'besides the two arms the NOT IN list must be exactly '
      '`SELECT id FROM ( <arm> UNION <arm> ) AS keep_rows`, found `${_flat(rest)}`',
    );
  }
  return problems;
}

/// The whole function text (header and body: every statement in it, e.g. the DELETE target and anything after the NOT IN list),
/// whitespace-collapsed and comment-free, must equal [canonicalSql]'s. A deliberate change to this catastrophic-tier function
/// therefore has to edit this pin on purpose.
List<String> bodyDriftProblems(String migrationSql, String canonicalSql) {
  String? flatDef(String s) {
    final d = _lastDefinition(stripSqlLineComments(_lf(s)));
    return d == null ? null : _flat(d);
  }

  final a = flatDef(migrationSql);
  final b = flatDef(canonicalSql);
  if (a == null) return ['no cleanup_cron_call_log definition'];
  if (b == null)
    return ['the canonical text has no cleanup_cron_call_log definition'];
  return a == b
      ? []
      : [
          'the function text differs from migration 172 (header, DELETE target, predicate or a statement around the keep-set)',
        ];
}

/// Problems with the security envelope of the latest definition: SECURITY DEFINER, the search_path pinned to public alone, the
/// REVOKEs of PUBLIC / anon / authenticated and exactly one grantee (postgres). Every GRANT/REVOKE statement is read, whatever
/// the spelling of the name (schema-qualified or not, quoted, spaces before the parentheses), and a schema-wide
/// `ON ALL FUNCTIONS IN SCHEMA` GRANT/REVOKE is refused here because it changes this function's ACL invisibly.
List<String> attributeProblems(String migrationSql) {
  final sql = stripSqlLineComments(_lf(migrationSql));
  final heads = RegExp(
    r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public\.)?cleanup_cron_call_log\b(.*?)AS\s+\$fn\$',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(sql).toList();
  if (heads.isEmpty) return ['no cleanup_cron_call_log definition header'];
  final problems = <String>[];
  final header = _flat(heads.last.group(1)!);
  if (!RegExp(r'\bSECURITY DEFINER\b', caseSensitive: false).hasMatch(header)) {
    problems.add('the function is not SECURITY DEFINER');
  }
  final sp = RegExp(
    r"SET search_path (?:TO|=) ((?:'[^']*'|\w+)(?: ?, ?(?:'[^']*'|\w+))*)",
    caseSensitive: false,
  ).firstMatch(header);
  final path = sp
      ?.group(1)
      ?.replaceAll("'", '')
      .replaceAll(RegExp(r'\s+'), '')
      .toLowerCase();
  if (path != 'public') {
    problems.add(
      "the header must pin SET search_path TO 'public' and nothing else (found ${path ?? 'none'})",
    );
  }
  final fnName = RegExp(
    r'(?:"?public"?\s*\.\s*)?"?cleanup_cron_call_log"?\s*\(\s*\)',
    caseSensitive: false,
  );
  final revoked = <String>{};
  final granted = <String>{};
  for (final raw in sql.split(';')) {
    final st = _flat(raw);
    final isGrant = RegExp(r'^GRANT\b', caseSensitive: false).hasMatch(st);
    final isRevoke = RegExp(r'^REVOKE\b', caseSensitive: false).hasMatch(st);
    if (!isGrant && !isRevoke) continue;
    if (RegExp(
      r'\bALL FUNCTIONS IN SCHEMA\b',
      caseSensitive: false,
    ).hasMatch(st)) {
      problems.add(
        'a schema-wide GRANT/REVOKE on functions changes this ACL invisibly: `$st`',
      );
      continue;
    }
    if (!fnName.hasMatch(st)) continue;
    final m = RegExp(
      isGrant ? r'\bTO\s+(.+)$' : r'\bFROM\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(st);
    if (m == null) {
      problems.add('cannot read the role list of `$st`');
      continue;
    }
    (isGrant ? granted : revoked).addAll(
      m
          .group(1)!
          .split(',')
          .map((r) => r.trim().replaceAll('"', '').toLowerCase())
          .where((r) => r.isNotEmpty),
    );
  }
  for (final role in ['public', 'anon', 'authenticated']) {
    if (!revoked.contains(role))
      problems.add('missing REVOKE ALL ... FROM $role');
  }
  if (revoked.contains('postgres'))
    problems.add('postgres (the cron owner) must keep EXECUTE');
  if (granted.length != 1 || !granted.contains('postgres')) {
    problems.add(
      'the only grantee on the function must be postgres, found $granted',
    );
  }
  return problems;
}

/// Problems with the DROP of the orphan pruner in [migrationSql].
List<String> dropFormProblems(String migrationSql) {
  final sql = stripSqlLineComments(migrationSql);
  final problems = <String>[];
  if (!RegExp(
    r'DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.cron_call_log_cleanup_7d\s*\(\s*\)\s*;',
    caseSensitive: false,
  ).hasMatch(sql)) {
    problems.add(
      'the form must be DROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d();',
    );
  }
  if (RegExp(r'\bCASCADE\b', caseSensitive: false).hasMatch(sql)) {
    problems.add(
      'no CASCADE: an unseen dependent must make the migration fail closed',
    );
  }
  return problems;
}

/// Problems with the commented rollback block 1 of [sql172]: with the `-- ` prefix removed its HEADER (name, language, security
/// mode, search_path) and its BODY must both equal migration 169's, so a rollback restores the 169 function exactly and
/// md5(prosrc) afterwards equals the 169 value.
List<String> rollbackProblems(String sql172, String sql169) {
  final lines = _lf(sql172).split('\n');
  final from = lines.indexWhere((l) => l.startsWith('-- 1. Restore the 169'));
  if (from < 0) return ['no `-- 1. Restore the 169` rollback block'];
  final head = lines.indexWhere(
    (l) => l.startsWith('-- CREATE OR REPLACE FUNCTION'),
    from,
  );
  final open = lines.indexWhere((l) => l == '-- AS \$fn\$', from);
  if (head < 0 || open < 0 || head > open)
    return ['the rollback block has no `-- CREATE ... -- AS \$fn\$` header'];
  final close = lines.indexWhere((l) => l == '-- \$fn\$;', open);
  if (close < 0) return ['the rollback block has no closing `-- \$fn\$;` line'];
  String? strip(String l) =>
      l.startsWith('-- ') ? l.substring(3) : (l == '--' ? '' : null);
  final restoredHead = <String>[];
  for (final l in lines.sublist(head, open + 1)) {
    final s = strip(l);
    if (s == null)
      return ['a rollback header line is not a `--` comment line: `$l`'];
    restoredHead.add(s);
  }
  final restored = <String>[];
  for (final l in lines.sublist(open + 1, close)) {
    final s = strip(l);
    if (s == null) return ['a rollback line is not a `--` comment line: `$l`'];
    restored.add(s);
  }
  final s169 = _lf(sql169);
  final h = RegExp(
    r'^(CREATE OR REPLACE FUNCTION public\.cleanup_cron_call_log\(\).*?\nAS \$fn\$)\n',
    multiLine: true,
    dotAll: true,
  ).firstMatch(s169);
  final b = RegExp(
    r'^AS \$fn\$\n(.*?)\n\$fn\$;',
    multiLine: true,
    dotAll: true,
  ).firstMatch(s169);
  if (h == null || b == null)
    return ['no function header or body found in migration 169'];
  final problems = <String>[];
  if (_flat(restoredHead.join('\n')) != _flat(h.group(1)!)) {
    problems.add(
      'the rollback HEADER differs from the 169 header (security mode, search_path or language)',
    );
  }
  if (restored.join('\n') != b.group(1)) {
    problems.add('the rollback body differs from the 169 body');
  }
  return problems;
}

/// Names of the [files] (name -> sql) that run DDL on `cleanup_cron_call_log` outside a comment: CREATE / ALTER / DROP /
/// COMMENT ON FUNCTION with the name directly after FUNCTION (schema-qualified or quoted or not, also inside a DO block's
/// EXECUTE string), a GRANT / REVOKE ON FUNCTION for it, or a schema-wide GRANT/REVOKE ON ALL FUNCTIONS IN SCHEMA public.
/// A file that only CALLS the function (cron job 41's command) is not DDL and is not listed.
List<String> functionDdlMentions(Map<String, String> files) {
  final ddl = RegExp(
    r'(?:CREATE(?:\s+OR\s+REPLACE)?|ALTER|DROP|COMMENT\s+ON)\s+FUNCTION\s+(?:IF\s+EXISTS\s+)?(?:"?\w+"?\s*\.\s*)?"?cleanup_cron_call_log"?(?!\w)'
    r'|\b(?:GRANT|REVOKE)\b[^;]*?\bON\s+FUNCTION\s+(?:"?\w+"?\s*\.\s*)?"?cleanup_cron_call_log"?(?!\w)'
    r'|\b(?:GRANT|REVOKE)\b[^;]*?\bON\s+ALL\s+FUNCTIONS\s+IN\s+SCHEMA\s+"?public"?',
    caseSensitive: false,
    dotAll: true,
  );
  return [
    for (final e in files.entries)
      if (ddl.hasMatch(stripSqlLineComments(_lf(e.value)))) e.key,
  ];
}

int _order(File a, File b) {
  final an = a.uri.pathSegments.last;
  final bn = b.uri.pathSegments.last;
  final c = migrationNumber(an).compareTo(migrationNumber(bn));
  return c != 0 ? c : an.compareTo(bn);
}

void main() {
  late final File latest;
  late final String latestSql;
  late final String
  baseSql; // migration 172 itself: the frozen text every mutation fixture starts from
  late final String sql169;

  setUpAll(() {
    final f = latestMigrationDefining('cleanup_cron_call_log');
    expect(f, isNotNull, reason: 'no migration defines cleanup_cron_call_log');
    latest = f!;
    latestSql = _lf(latest.readAsStringSync());
    baseSql = _lf(File(_m172).readAsStringSync());
    sql169 = _lf(File(_m169).readAsStringSync());
  });

  group('live definition', () {
    test(
      'the LATEST cleanup_cron_call_log keeps a per-function newest success and newest row',
      () {
        expect(
          migrationNumber(latest.uri.pathSegments.last),
          greaterThanOrEqualTo(172),
          reason:
              'migration 172 (OI-199) introduced the per-function keep-set; an older '
              'definition would be the 169 two-row body',
        );
        expect(keepSetProblems(latestSql), isEmpty, reason: latest.path);
      },
    );

    test(
      'the LATEST definition keeps the SECURITY DEFINER envelope and the grants',
      () {
        expect(attributeProblems(latestSql), isEmpty, reason: latest.path);
      },
    );

    test(
      'the LATEST function text equals migration 172\'s (a change must edit this pin on purpose)',
      () {
        expect(
          bodyDriftProblems(latestSql, baseSql),
          isEmpty,
          reason: latest.path,
        );
      },
    );

    test(
      'no migration NEWER than the resolved latest definition runs DDL on the function',
      () {
        // A quoted identifier, a DO block that EXECUTEs a redefinition, a DROP, a COMMENT or a GRANT would leave the resolver on
        // an older file and keep every check above green while the live function changed. A later CALL (job 41) is fine.
        final newer = {
          for (final f in numberedMigrations())
            if (_order(f, latest) > 0)
              f.uri.pathSegments.last: f.readAsStringSync(),
        };
        expect(
          functionDdlMentions(newer),
          isEmpty,
          reason:
              'extend latestMigrationDefining / keepSetProblems to read these files, then re-point this test',
        );
      },
    );

    test(
      'the migration that drops the orphan pruner does so without CASCADE',
      () {
        final droppers = <File>[];
        for (final f in numberedMigrations()) {
          if (RegExp(
            r'DROP\s+FUNCTION[^;]*cron_call_log_cleanup_7d',
            caseSensitive: false,
          ).hasMatch(stripSqlLineComments(f.readAsStringSync()))) {
            droppers.add(f);
          }
        }
        expect(
          droppers,
          hasLength(1),
          reason: 'exactly one migration drops cron_call_log_cleanup_7d',
        );
        expect(dropFormProblems(droppers.single.readAsStringSync()), isEmpty);
      },
    );

    test(
      'no other migration at or after the drop mentions the orphan pruner outside a comment',
      () {
        File? dropper;
        for (final f in numberedMigrations()) {
          if (RegExp(
            r'DROP\s+FUNCTION[^;]*cron_call_log_cleanup_7d',
            caseSensitive: false,
          ).hasMatch(stripSqlLineComments(f.readAsStringSync()))) {
            dropper = f;
          }
        }
        expect(dropper, isNotNull);
        final drop = dropper!;
        // >= (not >): a suffixed sibling such as 172b numbers the same as 172.
        final later = numberedMigrations()
            .where((f) => _order(f, drop) >= 0 && f.path != drop.path)
            .where(
              (f) => stripSqlLineComments(
                f.readAsStringSync(),
              ).contains('cron_call_log_cleanup_7d'),
            )
            .map((f) => f.uri.pathSegments.last)
            .toList();
        expect(
          later,
          isEmpty,
          reason:
              'a migration after the drop re-creates or calls the dropped function',
        );
      },
    );

    test(
      'rollback block 1 restores the 169 function (header and body) byte for byte',
      () {
        expect(rollbackProblems(baseSql, sql169), isEmpty);
      },
    );

    test(
      'the raw function text of migration 172 has the md5 and byte length the live apply asserts',
      () {
        final raw = _rawFnBody(baseSql);
        expect(raw, isNotNull);
        expect(utf8.encode(raw!).length, _bodyLen);
        expect(
          md5.convert(utf8.encode(raw)).toString(),
          _bodyMd5,
          reason:
              'update the harness EXPECT_MD5, the plan and the migration post-apply comment together',
        );
      },
    );
  });

  group('DDL detection on later migrations (pure fixtures)', () {
    test('a call from a cron job body is not DDL', () {
      expect(
        functionDdlMentions({'a': 'SELECT public.cleanup_cron_call_log();'}),
        isEmpty,
      );
    });

    test('a function that merely CALLS it inside its own body is not DDL', () {
      expect(
        functionDdlMentions({
          'a':
              'CREATE OR REPLACE FUNCTION public.other() RETURNS void LANGUAGE sql AS \$\$ SELECT public.cleanup_cron_call_log(); \$\$;',
        }),
        isEmpty,
      );
    });

    test('DROP with a quoted, qualified name is DDL', () {
      expect(
        functionDdlMentions({
          'a': 'DROP FUNCTION IF EXISTS "public"."cleanup_cron_call_log"();',
        }),
        ['a'],
      );
    });

    test('a CREATE inside a DO block EXECUTE string is DDL', () {
      expect(
        functionDdlMentions({
          'a':
              "DO \$\$ BEGIN EXECUTE 'CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log() RETURNS void AS ...'; END \$\$;",
        }),
        ['a'],
      );
    });

    test(
      'COMMENT ON FUNCTION, ALTER FUNCTION, GRANT and REVOKE ON FUNCTION are DDL',
      () {
        for (final s in [
          "COMMENT ON FUNCTION public.cleanup_cron_call_log() IS 'x';",
          'ALTER FUNCTION cleanup_cron_call_log() SET search_path TO x;',
          'GRANT EXECUTE ON FUNCTION cleanup_cron_call_log() TO anon;',
          'REVOKE ALL ON FUNCTION public.cleanup_cron_call_log ( ) FROM postgres;',
        ]) {
          expect(functionDdlMentions({'a': s}), ['a'], reason: s);
        }
      },
    );

    test(
      'a schema-wide GRANT or REVOKE on all functions is DDL for this function too',
      () {
        expect(
          functionDdlMentions({
            'a': 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon;',
          }),
          ['a'],
        );
      },
    );

    test(
      'a commented-out DDL line is ignored, and the real 172 text IS detected (positive control)',
      () {
        expect(
          functionDdlMentions({
            'a': '-- DROP FUNCTION public.cleanup_cron_call_log();',
          }),
          isEmpty,
        );
        expect(functionDdlMentions({'172': baseSql}), ['172']);
      },
    );
  });

  group('mutation proof: each check rejects the broken text it exists to reject', () {
    String mutate(String from, String to, {bool all = false}) {
      expect(
        baseSql.contains(from),
        isTrue,
        reason: 'mutation anchor not found in migration 172: $from',
      );
      final out = all
          ? baseSql.replaceAll(from, to)
          : baseSql.replaceFirst(from, to);
      expect(out, isNot(baseSql), reason: 'mutation did not change the file');
      return out;
    }

    test(
      'baseline: the unmutated file is clean under every check (non-vacuity)',
      () {
        expect(keepSetProblems(baseSql), isEmpty);
        expect(attributeProblems(baseSql), isEmpty);
        expect(bodyDriftProblems(baseSql, baseSql), isEmpty);
        expect(rollbackProblems(baseSql, sql169), isEmpty);
        expect(dropFormProblems(baseSql), isEmpty);
      },
    );

    // ---- keep-set: too narrow
    test('M1 arm 1 loses its status = success filter', () {
      expect(
        keepSetProblems(
          mutate(
            "          WHERE status = 'success' ORDER BY function_name",
            '          ORDER BY function_name',
          ),
        ),
        anyElement(contains('exactly one arm must filter')),
      );
    });

    test('M2 the newest-row arm is removed', () {
      final re = RegExp(
        r'        UNION\n        \(SELECT DISTINCT ON \(function_name\) id FROM public\.cron_call_log\n'
        r'          ORDER BY function_name, started_at DESC, id DESC\)\n',
      );
      expect(re.hasMatch(baseSql), isTrue, reason: 'mutation anchor not found');
      expect(
        keepSetProblems(baseSql.replaceFirst(re, '')),
        anyElement(contains('expected exactly 2')),
      );
    });

    test(
      'M3 DISTINCT ON (function_name) is removed from both arms (keeps every row)',
      () {
        expect(
          keepSetProblems(
            mutate(
              '(SELECT DISTINCT ON (function_name) id FROM',
              '(SELECT id FROM',
              all: true,
            ),
          ),
          anyElement(contains('expected exactly 2')),
        );
      },
    );

    test(
      'M3b both arms go global, the 169 shape (ORDER BY started_at DESC LIMIT 1)',
      () {
        var s = mutate(
          '(SELECT DISTINCT ON (function_name) id FROM',
          '(SELECT id FROM',
          all: true,
        );
        s = s.replaceAll(
          'ORDER BY function_name, started_at DESC, id DESC)',
          'ORDER BY started_at DESC LIMIT 1)',
        );
        expect(keepSetProblems(s), anyElement(contains('expected exactly 2')));
      },
    );

    test(
      'M4 started_at DESC becomes ASC (keeps the OLDEST row per function)',
      () {
        expect(
          keepSetProblems(
            mutate(
              'started_at DESC, id DESC)',
              'started_at ASC, id DESC)',
              all: true,
            ),
          ),
          anyElement(contains('expected exactly 2')),
        );
      },
    );

    test('M5 UNION becomes INTERSECT', () {
      expect(
        keepSetProblems(mutate('        UNION\n', '        INTERSECT\n')),
        anyElement(contains('besides the two arms')),
      );
    });

    test('M6 the retention interval becomes 7 days', () {
      expect(
        keepSetProblems(
          mutate(
            "WHERE started_at < now() - interval '10 days'",
            "WHERE started_at < now() - interval '7 days'",
          ),
        ),
        anyElement(contains('retention is 7.0')),
      );
    });

    test('M7 NOT IN becomes IN', () {
      expect(
        keepSetProblems(mutate('    AND id NOT IN (', '    AND id IN (')),
        anyElement(contains('not an `AND id NOT IN (` filter')),
      );
    });

    test('M8 the retention guard is deleted', () {
      expect(
        keepSetProblems(
          mutate(
            "  WHERE started_at < now() - interval '10 days'\n    AND id NOT IN (",
            '  WHERE id NOT IN (',
          ),
        ),
        anyElement(contains('retention is null')),
      );
    });

    test('M10 arm 2 gets a status <> started filter', () {
      expect(
        keepSetProblems(
          mutate(
            '          ORDER BY function_name, started_at DESC, id DESC)\n      ) AS keep_rows',
            "          WHERE status <> 'started' ORDER BY function_name, started_at DESC, id DESC)\n      ) AS keep_rows",
          ),
        ),
        anyElement(contains('expected exactly 2')),
      );
    });

    test('M11 the cut becomes <= (readRetentionDays then cannot read it)', () {
      expect(
        keepSetProblems(
          mutate(
            "WHERE started_at < now() - interval '10 days'",
            "WHERE started_at <= now() - interval '10 days'",
          ),
        ),
        anyElement(contains('retention is null')),
      );
    });

    test('M12 the id DESC tie-break is dropped', () {
      expect(
        keepSetProblems(
          mutate('started_at DESC, id DESC)', 'started_at DESC)', all: true),
        ),
        anyElement(contains('expected exactly 2')),
      );
    });

    // ---- keep-set: too WIDE
    test(
      'W1 a third arm that selects every id is unioned in (keeps every row, prunes nothing)',
      () {
        expect(
          keepSetProblems(
            mutate(
              '      ) AS keep_rows\n    );',
              '        UNION\n        (SELECT id FROM public.cron_call_log)\n      ) AS keep_rows\n    );',
            ),
          ),
          anyElement(contains('besides the two arms')),
        );
      },
    );

    test('W2 UNION becomes UNION ALL', () {
      expect(
        keepSetProblems(mutate('        UNION\n', '        UNION ALL\n')),
        anyElement(contains('besides the two arms')),
      );
    });

    test('W3 a whole-table SELECT is unioned in front of the arms', () {
      expect(
        keepSetProblems(
          mutate(
            '    AND id NOT IN (\n',
            '    AND id NOT IN (\n      SELECT id FROM public.cron_call_log UNION\n',
          ),
        ),
        anyElement(contains('besides the two arms')),
      );
    });

    test(
      'W4 BOTH arms filter on success (the mirror of M1: a failed-only newest row is lost)',
      () {
        expect(
          keepSetProblems(
            mutate(
              '          ORDER BY function_name, started_at DESC, id DESC)\n      ) AS keep_rows',
              "          WHERE status = 'success' ORDER BY function_name, started_at DESC, id DESC)\n      ) AS keep_rows",
            ),
          ),
          anyElement(contains('exactly one arm must filter')),
        );
      },
    );

    test(
      "W5 the status literal is 'SUCCESS' (matches no row; the regex is case-insensitive for identifiers only)",
      () {
        expect(
          keepSetProblems(
            mutate(
              "          WHERE status = 'success' ORDER BY function_name",
              "          WHERE status = 'SUCCESS' ORDER BY function_name",
            ),
          ),
          anyElement(contains('status literal must be exactly')),
        );
      },
    );

    // ---- the text AROUND the keep-set (the NOT IN list check does not see it)
    test(
      'B1 an OR predicate with a 30-day cap is appended after the NOT IN list (the hard cap the header refuses)',
      () {
        final m = mutate(
          '    );\n\$fn\$;',
          "    ) OR started_at < now() - interval '30 days';\n\$fn\$;",
        );
        expect(
          keepSetProblems(m),
          isEmpty,
          reason:
              'documents WHY the whole-text pin exists: the list check is blind to this',
        );
        expect(
          bodyDriftProblems(m, baseSql),
          anyElement(contains('differs from migration 172')),
        );
      },
    );

    test('B2 a second DELETE statement is added to the body', () {
      expect(
        bodyDriftProblems(
          mutate(
            '    );\n\$fn\$;',
            "    );\n  DELETE FROM public.cron_call_log WHERE started_at < now() - interval '7 days';\n\$fn\$;",
          ),
          baseSql,
        ),
        anyElement(contains('differs from migration 172')),
      );
    });

    test('B3 the DELETE target is another table', () {
      expect(
        bodyDriftProblems(
          mutate(
            'DELETE FROM public.cron_call_log\n  WHERE',
            'DELETE FROM public.cron_call_log_x\n  WHERE',
          ),
          baseSql,
        ),
        anyElement(contains('differs from migration 172')),
      );
    });

    test(
      'B4 a comment-only or whitespace-only edit does NOT trip the pin (no false red)',
      () {
        final m = mutate(
          'DELETE FROM public.cron_call_log\n  WHERE',
          '-- a new comment line\n  DELETE   FROM public.cron_call_log\n    WHERE',
        );
        expect(bodyDriftProblems(m, baseSql), isEmpty);
      },
    );

    // ---- security envelope and grants
    test('A1 SECURITY DEFINER becomes SECURITY INVOKER', () {
      expect(
        attributeProblems(
          mutate(
            'LANGUAGE sql\nSECURITY DEFINER\n',
            'LANGUAGE sql\nSECURITY INVOKER\n',
          ),
        ),
        anyElement(contains('not SECURITY DEFINER')),
      );
    });

    test('A2 the SET search_path clause is deleted', () {
      expect(
        attributeProblems(
          mutate("SET search_path TO 'public'\nAS \$fn\$", 'AS \$fn\$'),
        ),
        anyElement(contains('search_path')),
      );
    });

    test('A3 REVOKE ... FROM PUBLIC is deleted', () {
      expect(
        attributeProblems(
          mutate(
            'REVOKE ALL ON FUNCTION public.cleanup_cron_call_log() FROM PUBLIC;\n',
            '',
          ),
        ),
        anyElement(contains('FROM public')),
      );
    });

    test('A4 the GRANT also names anon', () {
      expect(
        attributeProblems(
          mutate(
            'GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;',
            'GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres, anon;',
          ),
        ),
        anyElement(contains('only grantee')),
      );
    });

    test('A5 REVOKE ... FROM anon, authenticated is deleted', () {
      expect(
        attributeProblems(
          mutate(
            'REVOKE ALL ON FUNCTION public.cleanup_cron_call_log() FROM anon, authenticated;\n',
            '',
          ),
        ),
        anyElement(contains('FROM anon')),
      );
    });

    test('A6 the search_path is widened to public, extensions', () {
      expect(
        attributeProblems(
          mutate(
            "SET search_path TO 'public'\nAS \$fn\$",
            "SET search_path TO 'public', 'extensions'\nAS \$fn\$",
          ),
        ),
        anyElement(contains('search_path')),
      );
    });

    test(
      'A7 a second GRANT with an UNQUALIFIED name gives anon EXECUTE (the exact spelling is not required)',
      () {
        expect(
          attributeProblems(
            mutate(
              'GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;',
              'GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;\nGRANT EXECUTE ON FUNCTION cleanup_cron_call_log() TO anon;',
            ),
          ),
          anyElement(contains('only grantee')),
        );
      },
    );

    test(
      'A8 a GRANT with spaces inside the parentheses gives authenticated EXECUTE',
      () {
        expect(
          attributeProblems(
            mutate(
              'GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;',
              'GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;\nGRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log ( ) TO authenticated;',
            ),
          ),
          anyElement(contains('only grantee')),
        );
      },
    );

    test('A9 a schema-wide GRANT on all functions is refused', () {
      expect(
        attributeProblems(
          mutate(
            'GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;',
            'GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;\nGRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon;',
          ),
        ),
        anyElement(contains('schema-wide')),
      );
    });

    test(
      'A10 REVOKE EXECUTE FROM postgres is refused (the cron owner keeps EXECUTE)',
      () {
        expect(
          attributeProblems(
            mutate(
              'GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;',
              'GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;\nREVOKE EXECUTE ON FUNCTION public.cleanup_cron_call_log() FROM postgres;',
            ),
          ),
          anyElement(contains('keep EXECUTE')),
        );
      },
    );

    test(
      'P1 (no false red) one REVOKE statement for PUBLIC, anon and authenticated is accepted',
      () {
        var m = mutate(
          'REVOKE ALL ON FUNCTION public.cleanup_cron_call_log() FROM PUBLIC;\n',
          'REVOKE ALL ON FUNCTION cleanup_cron_call_log() FROM PUBLIC, anon, authenticated;\n',
        );
        m = m.replaceFirst(
          'REVOKE ALL ON FUNCTION public.cleanup_cron_call_log() FROM anon, authenticated;\n',
          '',
        );
        expect(attributeProblems(m), isEmpty);
      },
    );

    test(
      'P2 (no false red) SET search_path before SECURITY DEFINER, plus another SET clause, is accepted',
      () {
        final m = mutate(
          "LANGUAGE sql\nSECURITY DEFINER\nSET search_path TO 'public'\nAS \$fn\$",
          "LANGUAGE sql\nSET search_path TO 'public'\nSET lock_timeout TO '5s'\nSECURITY DEFINER\nAS \$fn\$",
        );
        expect(attributeProblems(m), isEmpty);
      },
    );

    // ---- rollback block 1
    test('R1 one token of the rollback body differs from 169 (LIMIT 2)', () {
      expect(
        rollbackProblems(
          mutate(
            "--           WHERE status = 'success' ORDER BY started_at DESC LIMIT 1)",
            "--           WHERE status = 'success' ORDER BY started_at DESC LIMIT 2)",
          ),
          sql169,
        ),
        anyElement(contains('differs from the 169 body')),
      );
    });

    test('R2 a rollback line is missing', () {
      expect(
        rollbackProblems(mutate('--     );\n-- \$fn\$;', '-- \$fn\$;'), sql169),
        anyElement(contains('differs from the 169 body')),
      );
    });

    test('R3 a rollback line lost its `--` prefix', () {
      expect(
        rollbackProblems(
          mutate('--     );\n-- \$fn\$;', '    );\n-- \$fn\$;'),
          sql169,
        ),
        anyElement(contains('not a `--` comment line')),
      );
    });

    test(
      'R4 the rollback header says SECURITY INVOKER (a rollback would silently drop the definer)',
      () {
        expect(
          rollbackProblems(
            mutate(
              "-- RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'\n-- AS \$fn\$",
              "-- RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path TO 'public'\n-- AS \$fn\$",
            ),
            sql169,
          ),
          anyElement(contains('HEADER differs')),
        );
      },
    );

    // ---- the DROP
    test('D1 the DROP gets CASCADE', () {
      expect(
        dropFormProblems(
          mutate(
            '\nDROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d();',
            '\nDROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d() CASCADE;',
          ),
        ),
        anyElement(contains('CASCADE')),
      );
    });

    test('D2 the DROP loses IF EXISTS', () {
      expect(
        dropFormProblems(
          mutate(
            '\nDROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d();',
            '\nDROP FUNCTION public.cron_call_log_cleanup_7d();',
          ),
        ),
        anyElement(contains('the form must be')),
      );
    });

    test('D3 the DROP is deleted', () {
      expect(
        dropFormProblems(
          mutate(
            '\nDROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d();',
            '\n',
          ),
        ),
        anyElement(contains('the form must be')),
      );
    });

    test('a commented-out copy of a broken body does not fool the check', () {
      // The header and rollback blocks of the real file carry the 169 two-row body as `--` lines; they must be ignored.
      final withDecoy =
          '-- CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log() ... \$fn\$;\n$baseSql';
      expect(keepSetProblems(withDecoy), isEmpty);
      expect(attributeProblems(withDecoy), isEmpty);
    });
  });

  group('the files that prove the behaviour', () {
    test(
      'the harness applies the REAL migration files and carries no embedded copy of the body',
      () {
        final sh = File(_harness).readAsStringSync();
        for (final needle in [
          'supabase/migrations',
          '169_cron_call_log_retention_10d.sql',
          '170_oi473_cron_dead_alert_edges.sql',
          '172_cron_call_log_per_function_keep.sql',
          'cleanup_cron_call_log_per_function_verify.sql',
        ]) {
          expect(
            sh.contains(needle),
            isTrue,
            reason: 'harness must reference $needle',
          );
        }
        expect(
          _flat(sh).contains(
            'DISTINCT ON (function_name) id FROM public.cron_call_log WHERE status',
          ),
          isFalse,
          reason:
              'an embedded copy of the keep-set would drift from the migration (checked whitespace-insensitively)',
        );
      },
    );

    test(
      'the harness is documented as run with bash (dash lacks pipefail) and runs mutants M1 to M18',
      () {
        final sh = File(_harness).readAsStringSync();
        expect(sh.contains('# Usage: bash test/sql/'), isTrue);
        expect(
          sh.contains('sh/bash'),
          isFalse,
          reason: '`sh` dies on `set -o pipefail` under dash',
        );
        expect(
          sh.contains('M13 M14 M15 M16 M17 M18; do'),
          isTrue,
          reason: 'the security-envelope mutants must be in the run list',
        );
      },
    );

    test(
      'the harness proves the verify file REFUSES to run without the scaffold',
      () {
        final sh = File(_harness).readAsStringSync();
        expect(
          sh.contains('verify file refuses to run without the scaffold'),
          isTrue,
        );
      },
    );

    test(
      'the md5 and length the live apply asserts are the same literals in the harness, the plan and the migration',
      () {
        final sh = File(_harness).readAsStringSync();
        expect(sh.contains('EXPECT_MD5=$_bodyMd5'), isTrue);
        expect(sh.contains('EXPECT_LEN=$_bodyLen'), isTrue);
        expect(
          File(_plan).readAsStringSync().contains(_bodyMd5),
          isTrue,
          reason: 'the plan\'s apply request asserts it',
        );
        expect(
          baseSql.contains(_bodyMd5),
          isTrue,
          reason: 'the post-apply block of the migration names it',
        );
      },
    );

    test(
      'the harness runs the exact live apply request, which the plan quotes (880-byte statements block, same wrapper)',
      () {
        final sh = File(_harness).readAsStringSync();
        final plan = File(_plan).readAsStringSync();
        expect(sh.contains('2b. The live APPLY REQUEST'), isTrue);
        expect(
          sh.contains('a wrong md5 aborts the request'),
          isTrue,
          reason: 'the negative: CREATE and DROP roll back together',
        );
        expect(
          sh.contains('a catalog dependent makes the request fail closed'),
          isTrue,
        );
        for (final needle in [
          "SET LOCAL lock_timeout = '3s';",
          "SET LOCAL statement_timeout = '60s';",
          "RAISE EXCEPTION 'migration 172 post-condition failed';",
          "to_regprocedure('public.cron_call_log_cleanup_7d()') IS NOT NULL",
          r'DO $a$ BEGIN',
        ]) {
          expect(
            sh.contains(needle) ||
                sh.contains(needle.replaceAll(r'$a$', r'\$a\$')),
            isTrue,
            reason: 'harness lacks `$needle`',
          );
          expect(plan.contains(needle), isTrue, reason: 'plan lacks `$needle`');
        }
        // The statements block the plan sends is exactly the file's CREATE..DROP lines: 880 bytes, as the harness asserts.
        final lines = baseSql.split('\n');
        final i = lines.indexWhere(
          (l) => l.startsWith(
            'CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()',
          ),
        );
        final j = lines.indexWhere(
          (l) =>
              l == 'DROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d();',
        );
        expect(i, greaterThan(0));
        expect(j, greaterThan(i));
        expect(
          utf8.encode('${lines.sublist(i, j + 1).join('\n')}\n').length,
          880,
        );
        expect(sh.contains('"\$REQ_BYTES" = 880'), isTrue);
      },
    );

    test(
      'the harness orphan function equals rollback block 2 (one live read, two copies)',
      () {
        final sh = _lf(File(_harness).readAsStringSync());
        final h = RegExp(
          r'SET search_path TO ([^\n]*?) AS \$o\$\n(.*?)\n\$o\$;',
          dotAll: true,
        ).firstMatch(sh);
        final lines = baseSql.split('\n');
        final start = lines.indexWhere(
          (l) =>
              l ==
              '-- CREATE OR REPLACE FUNCTION public.cron_call_log_cleanup_7d()',
        );
        expect(h, isNotNull);
        expect(start, greaterThan(0));
        final end = lines.indexWhere((l) => l == '-- \$fn\$;', start);
        final block = lines
            .sublist(start, end + 1)
            .map((l) => l.startsWith('-- ') ? l.substring(3) : '')
            .join('\n');
        final r =
            RegExp(
              r"SET search_path TO ([^\n]*?)\nAS \$fn\$\n(.*?)\n\$fn\$;",
              dotAll: true,
            ).firstMatch(
              block.replaceFirst(
                'SECURITY DEFINER SET search_path',
                'SECURITY DEFINER\nSET search_path',
              ),
            );
        expect(r, isNotNull);
        expect(
          _flat(h!.group(1)!),
          _flat(r!.group(1)!),
          reason: 'search_path of the orphan',
        );
        expect(
          _flat(h.group(2)!),
          _flat(r.group(2)!),
          reason: 'body of the orphan',
        );
      },
    );

    test(
      'the verify file carries every case label the harness expects, and its local-only guard',
      () {
        final sql = File(
          'test/sql/cleanup_cron_call_log_per_function_verify.sql',
        ).readAsStringSync();
        for (final label in [
          'A_1h_kept',
          'A_10d_exact_kept',
          'B_dead_keeps_exactly_two',
          'C_each_silent_function_keeps_its_newest',
          'D_no_success_function_keeps_newest_row',
          'E_recent_rows_untouched',
          'F_empty_table_no_error',
          'F2_tie_keeps_one_the_higher_id',
          'G_second_run_deletes_nothing',
          'H_survivors_equal_oracle',
          'H_old_keep_set_is_subset_of_survivors',
          'H2_fixture_old_keep_set_is_two_old_rows',
          'H2_dead_fleet_old_keep_rows_survive',
          'H2_dead_fleet_survivors_equal_oracle',
          'I_orphan_pruner_dropped',
          'J_exact_pages_loops_1_and_4',
          'J_jitter_pages_loops_1_and_5',
          'J3_beyond_lookback_zero_pages',
          'J3_beyond_lookback_row_kept',
          'K_security_definer',
          'K_search_path_pinned',
          'K_no_public_execute',
          'K_anon_cannot_execute',
          'K_authenticated_cannot_execute',
          'K_postgres_has_acl_execute',
        ]) {
          expect(
            sql.contains("'$label'"),
            isTrue,
            reason: 'verify file lacks case $label',
          );
        }
        expect(
          sql.contains('local harness only'),
          isTrue,
          reason:
              'the file empties cron_call_log and must refuse to run outside the scaffold',
        );
        expect(
          sql.contains("'K_postgres_can_execute'"),
          isFalse,
          reason:
              'postgres is a superuser in the docker image, so has_function_privilege(postgres) can never fail (vacuous); '
              'K_postgres_has_acl_execute reads the ACL entry instead',
        );
      },
    );

    test(
      'the 169-era pin test seeds the rows it compares under ONE function name per scenario',
      () {
        final sql = File(
          'test/sql/cleanup_cron_call_log_retention_live_verify.sql',
        ).readAsStringSync();
        for (final stale in [
          "'c9e2a7_9d'",
          "'c9e2a7_11d'",
          "'c9e2a7_s0'",
          "'c9e2a7_1h'",
        ]) {
          expect(
            sql.contains(stale),
            isFalse,
            reason:
                'distinct names make every row the newest of its own function, which survives the per-function keep-set',
          );
        }
      },
    );
  });
}
