// OI-473 edge 3 + OI-472 (diagnose f7b3d1): `alert_cron_function_dead` pages on
// any function whose newest cron_call_log success is 8+ days old, except the
// names in its `function_name NOT IN (...)` list. That list was one hard-coded
// name with nothing tying it to reality, so a function that logs runs but is
// not on the cron schedule (weekly-recalc, OI-472) paged CRITICAL 8 days after
// a single manual run.
//
// Three sets, all read from the repo:
//   A  every function that calls logCronStart (writes cron_call_log rows),
//   B  the functions on the CRON_REGISTRY.md schedule table (the `| Function |`
//      column),
//   C  the exclusion list in the LATEST alert body.
// Invariants: A is a subset of B + C (a new writer is either scheduled and
// registered, or consciously excluded); C is a subset of A (a removed function
// leaves the list); B and C are disjoint (a function later scheduled and
// registered must stop being excluded, else it is silently unwatched).
//
// Live deriving C from cron.job text was rejected: two live functions
// (compute-admin-metrics-daily, compute-coach-signals) are reached through
// helper functions, so no cron.job command names them.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/cron_job_body_reader.dart';

/// Names passed to `logCronStart(` in [src], plus the count of call sites that
/// did NOT pass a plain string literal (a variable or constant would be
/// invisible to a literal-only parse).
({List<String> names, int callSites}) parseLogCronStartCallers(String src) {
  final code = src
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('*'))
      .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
      .join('\n');
  final callSites = RegExp(r'\blogCronStart\(').allMatches(code).length;
  final literal = RegExp(r'''\blogCronStart\(\s*(["'])([a-z0-9-]+)\1\s*[,)]''')
      .allMatches(code)
      .map((m) => m.group(2)!)
      .toList();
  return (names: literal, callSites: callSites);
}

/// Backticked slugs in the `Function` cell of the schedule table whose header
/// contains `| Function |`. Other tables (the Deprecated one) are ignored.
Set<String> parseRegistryFunctions(String md) {
  final lines = md.split('\n');
  final h = lines.indexWhere((l) => l.contains('| Function |'));
  if (h < 0) return {};
  final split = RegExp(r'(?<!\\)\|');
  final header = lines[h].split(split).map((c) => c.trim()).toList();
  final col = header.indexOf('Function');
  final out = <String>{};
  for (var i = h + 2; i < lines.length && lines[i].trimLeft().startsWith('|'); i++) {
    final cells = lines[i].split(split);
    if (col >= cells.length) continue;
    for (final m in RegExp(r'`([a-z0-9-]+)`').allMatches(cells[col])) {
      out.add(m.group(1)!);
    }
  }
  return out;
}

/// The names in `function_name NOT IN ( ... )` of a comment-stripped body.
Set<String> parseExclusions(String body) {
  final m =
      RegExp(r'function_name\s+NOT\s+IN\s*\(([^)]*)\)', caseSensitive: false)
          .firstMatch(body);
  if (m == null) return {};
  return RegExp(r"'([a-z0-9-]+)'")
      .allMatches(m.group(1)!)
      .map((x) => x.group(1)!)
      .toSet();
}

({Set<String> a, int nonLiteral}) _readA(String functionsDir) {
  final a = <String>{};
  var nonLiteral = 0;
  for (final d in Directory(functionsDir).listSync().whereType<Directory>()) {
    final f = File('${d.path}/index.ts');
    if (!f.existsSync()) continue;
    final r = parseLogCronStartCallers(f.readAsStringSync());
    a.addAll(r.names);
    nonLiteral += r.callSites - r.names.length;
  }
  return (a: a, nonLiteral: nonLiteral);
}

void main() {
  group('parsers (fixtures)', () {
    test('callers: double quote, single quote and telemetry. prefix are read', () {
      final r = parseLogCronStartCallers('''
        const a = await logCronStart("x-one");
        const b = await logCronStart('x-two');
        const c = await telemetry.logCronStart("x-three");
      ''');
      expect(r.names, ['x-one', 'x-two', 'x-three']);
      expect(r.callSites, 3);
    });

    test('callers: a variable or constant argument is counted as non-literal', () {
      final r = parseLogCronStartCallers('''
        const a = await logCronStart(FN_NAME);
        const b = await logCronStart("x-one");
      ''');
      expect(r.names, ['x-one']);
      expect(r.callSites - r.names.length, 1);
    });

    test('callers: block comments and JSDoc lines are not call sites', () {
      final r = parseLogCronStartCallers('''
        /* old: logCronStart("ghost-one") */
        /**
         * const id = await logCronStart(slug);
         * logCronStart("ghost-two")
         */
        const a = await logCronStart("x-one");
      ''');
      expect(r.names, ['x-one']);
      expect(r.callSites, 1);
    });

    test('callers: comments and a typed parameter declaration are not call sites', () {
      final r = parseLogCronStartCallers('''
        // calls logCronStart("ghost") in a comment
        telemetry: { logCronStart: typeof logCronStart; },
        const a = await logCronStart("x-one");
      ''');
      expect(r.names, ['x-one']);
      expect(r.callSites, 1);
    });

    test('registry: only the Function table, backticked slugs only', () {
      final s = parseRegistryFunctions('''
## Active jobs

| Migration | Job name (jobid) | Cadence UTC | Cadence IST | Function | Vault dep | Notes |
|---|---|---|---|---|---|---|
| 015 | `a` (5) | `0 1 * * *` | 06:30 | `morning-alert` (generate) | `cron_secret` | n |
| 016 | `b` (6) | `0 2 * * *` | 07:30 | (intra-DB) `private.process_referral_conversions()` | n/a | has \\| pipe |
| 017 | `c` (7) | `0 3 * * *` | 08:30 | `founder-digest` | `cron_secret` | x |

## Deprecated

| Migration | Job name | Why removed |
|---|---|---|
| 001 | `rolling-context-nightly` | gone |
''');
      expect(s, {'morning-alert', 'founder-digest'});
    });

    test('exclusions: names inside NOT IN (...), none when absent', () {
      expect(
          parseExclusions(
              "AND function_name NOT IN ('alert-critical-notify', 'weekly-recalc')"),
          {'alert-critical-notify', 'weekly-recalc'});
      expect(parseExclusions("AND function_name <> 'alert-critical-notify'"),
          isEmpty);
    });
  });

  group('the real tree', () {
    final read = _readA('supabase/functions');
    final a = read.a;
    final b = parseRegistryFunctions(
        File('docs/operations/CRON_REGISTRY.md').readAsStringSync());
    final c = parseExclusions(
        latestCronJobBody('alert_cron_function_dead').body);

    test('non-vacuity: every set is parsed, and no caller hides behind a variable',
        () {
      expect(a.length, greaterThanOrEqualTo(19));
      expect(a,
          containsAll(['alert-critical-notify', 'weekly-recalc', 'clean-orphan-media']));
      expect(read.nonLiteral, 0,
          reason: 'a logCronStart caller passing a constant or variable is '
              'invisible to this roster: pass a string literal');
      expect(b.length, greaterThanOrEqualTo(17));
      expect(b, containsAll(['founder-digest', 'morning-alert']));
      expect(c, containsAll(['alert-critical-notify', 'weekly-recalc']));
    });

    test('every cron_call_log writer is scheduled and registered, or excluded', () {
      final orphans = a.difference(b.union(c)).toList()..sort();
      expect(orphans, isEmpty,
          reason: 'these functions call logCronStart but are neither on the '
              'CRON_REGISTRY.md schedule table nor in the exclusion list of '
              'alert_cron_function_dead: a single manual run would page '
              'CRITICAL 8 days later (OI-472). Register the schedule, or add '
              'the name to the NOT IN (...) list in a new migration.');
    });

    test('every exclusion still names a function that writes cron_call_log', () {
      final stale = c.difference(a).toList()..sort();
      expect(stale, isEmpty,
          reason: 'excluded names with no logCronStart caller: the function '
              'was removed, so drop it from the NOT IN (...) list');
    });

    test('no scheduled function is excluded (it would be silently unwatched)', () {
      final both = b.intersection(c).toList()..sort();
      expect(both, isEmpty,
          reason: 'on the schedule table AND in the exclusion list: a dead '
              'scheduled function would never page');
    });

    test('the trigger-dispatched roster is a subset of the exclusion list', () {
      final roster = File('test/contracts/cron_auth_adoption_test.dart')
          .readAsStringSync();
      final block = RegExp(
              r'_triggerDispatchedFunctions = <String>\[(.*?)\];',
              dotAll: true)
          .firstMatch(roster)!
          .group(1)!;
      final names = RegExp(r"'([a-z0-9-]+)'")
          .allMatches(stripSqlLineComments(block.replaceAll('//', '--')))
          .map((m) => m.group(1)!)
          .toSet();
      expect(names, contains('alert-critical-notify'));
      for (final fn in names.where(a.contains)) {
        expect(c, contains(fn),
            reason: '$fn is trigger-dispatched and writes cron_call_log: '
                'silence is healthy, and a critical about it would dispatch it');
      }
    });
  });
}
