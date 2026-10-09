// test/scripts/check_unbounded_cron_reads_tools_scope_e2e_test.dart
//
// END-TO-END for scripts/check_unbounded_cron_reads.dart's coach-tools scope (L1b plan B8). The
// coach tools under `_shared/tools/**` are scanned RECURSIVELY and a violation there FAILS the gate
// (exit 1), like any other. History: the first L1b commit shipped this as WARN-only (§4.11
// baseline: pre-commit and CI discard output, so a whole-gate --warn-only could not carry it);
// the flip commit deleted the scoped branch after the 24 h baseline with a zero WARN list.
//
// Mutation proof (gate_test_ledger.yaml, diagnose e5abc7): re-adding a scope that exempts the tools
// path from the exit code reddens the tools-violation cases below.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _dartBin() {
  final override = Platform.environment['DART_BIN_OVERRIDE'];
  if (override != null && File(override).existsSync()) return override;
  final which = Process.runSync(Platform.isWindows ? 'where' : 'which', ['dart'], stdoutEncoding: utf8);
  if (which.exitCode == 0) {
    final first = (which.stdout as String).split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (first.isNotEmpty) {
      final dir = File(first).parent.path.replaceAll(r'\', '/');
      for (final c in ['$dir/cache/dart-sdk/bin/dart.exe', '$dir/cache/dart-sdk/bin/dart']) {
        if (File(c).existsSync()) return c;
      }
    }
  }
  return 'dart';
}

const _registry = '''
| # | job | cron | IST | Function | Auth | Notes |
|---|---|---|---|---|---|---|
| 031 | `job_a` (1) | `0 * * * *` | hourly | `fn-a` | `cron_secret` | fixture |
''';

const _unbounded = 'export const x = async (sb: any) => {\n'
    '  const r = await sb.from("some_table").select("id").eq("user_id", "u");\n'
    '  return r;\n'
    '};\n';

const _bounded = 'export const x = async (sb: any) => {\n'
    '  const r = await sb.from("some_table").select("id").eq("user_id", "u").limit(5);\n'
    '  return r;\n'
    '};\n';

const _pagedBounded = 'export const x = async (sb: any) => {\n'
    '  return await fetchPagesBounded<{ id: string }>(\n'
    '    (withCount) => sb.from("some_table").select("id", withCount ? { count: "exact" } : undefined),\n'
    '    { orderBy: [{ column: "id" }], maxPages: 3, label: "t" },\n'
    '  );\n'
    '};\n';

void main() {
  late Directory tmp;
  final repoRoot = Directory.current.path;
  final dart = _dartBin();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gate_unbounded_');
    Directory('${tmp.path}/scripts').createSync(recursive: true);
    File('$repoRoot/scripts/check_unbounded_cron_reads.dart')
        .copySync('${tmp.path}/scripts/check_unbounded_cron_reads.dart');
    Directory('${tmp.path}/docs/operations').createSync(recursive: true);
    File('${tmp.path}/docs/operations/CRON_REGISTRY.md').writeAsStringSync(_registry);
    Directory('${tmp.path}/supabase/functions/fn-a').createSync(recursive: true);
    File('${tmp.path}/supabase/functions/fn-a/index.ts').writeAsStringSync(_bounded);
    Directory('${tmp.path}/supabase/functions/_shared/tools/nutrition').createSync(recursive: true);
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  ProcessResult run() {
    final env = Map<String, String>.from(Platform.environment)..removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
    return Process.runSync(dart, ['scripts/check_unbounded_cron_reads.dart'],
        workingDirectory: tmp.path, environment: env, includeParentEnvironment: false);
  }

  void tool(String rel, String body) =>
      File('${tmp.path}/supabase/functions/_shared/tools/$rel')
        ..createSync(recursive: true)
        ..writeAsStringSync(body);

  test('a coach-tool violation (nested dir) FAILS the gate and names the file', () {
    tool('nutrition/t.ts', _unbounded);
    final r = run();
    expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stderr}', contains('_shared/tools/nutrition/t.ts'));
  });

  test('a NON-tools violation still exits 1', () {
    File('${tmp.path}/supabase/functions/fn-a/index.ts').writeAsStringSync(_unbounded);
    final r = run();
    expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
  });

  test('both in ONE run: exit 1 and BOTH files are reported', () {
    tool('nutrition/t.ts', _unbounded);
    File('${tmp.path}/supabase/functions/fn-a/index.ts').writeAsStringSync(_unbounded);
    final r = run();
    expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stderr}', contains('_shared/tools/nutrition/t.ts'));
    expect('${r.stderr}', contains('fn-a/index.ts'));
  });

  test('a tool read routed through fetchPagesBounded is recognised as bounded (exit 0)', () {
    tool('nutrition/t.ts', _pagedBounded);
    final r = run();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stderr}', isNot(contains('unbounded read')));
  });

  test('test files under tools/ (__tests__) are not scanned', () {
    tool('__tests__/x_test.ts', _unbounded);
    final r = run();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stderr}', isNot(contains('unbounded read')));
  });
}
