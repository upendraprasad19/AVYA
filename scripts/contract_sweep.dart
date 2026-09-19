// scripts/contract_sweep.dart
//
// Pre-push targeted SoT contract sweep (OI-220). NOT a check_* gate: the
// pre-commit + CI loops enumerate check_*.dart and would spawn flutter test
// at every commit. Wired ONLY in scripts/pre-push.sh, above the full suite,
// for every tier (pinned by test/contracts/contract_sweep_wired_test.dart).
// Mutation-proven per rule 21 (plan-review record docs/plan-reviews/
// gate-integrity.md) — rule 24's ledger enumerates check_* only
// (gate_test_ledger_lib.dart:135-139) and would reject this key.
//
// Usage:
//   dart run scripts/contract_sweep.dart [--warn-only] [--dry-run]
//       [--range <spec>] [--flutter-bin <path>]
// Env guards (checked FIRST): CONTRACT_SWEEP_SKIP=1 -> exit 0 untouched;
//   CONTRACT_SWEEP_NESTED=1 -> exit 0 (set by this runner on the flutter it
//   spawns, so a test that runs the real pre-push hook cannot recurse).
// Exit: 0 when the selected tests pass (or --warn-only / --dry-run / nothing
// selected / flutter exit 79 "No tests ran"); otherwise flutter test's exit
// code. Any internal error selects the FULL test/contracts/ subset (fail-safe
// to more testing, never none).

import 'dart:io';
import 'contract_sweep_lib.dart';

const _tag = '[contract-sweep]';
const _defaultRange = 'origin/main...HEAD';

Map<String, String> _spawnEnv() => Map<String, String>.from(Platform.environment)
  ..removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'))
  ..['TZ'] = 'Asia/Kolkata'
  ..['CONTRACT_SWEEP_NESTED'] = '1';

String? _arg(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

/// null => git failed (fallback). `git grep` exit 1 means NO MATCH (it is also
/// what a nonexistent pathspec dir returns — harmless here: cwd is the repo root
/// and `test/` exists); exit >= 2 or 128 is a real failure.
List<String>? _gitLines(List<String> a, {bool noMatchIsEmpty = false}) {
  final r = Process.runSync('git', a, runInShell: true);
  if (r.exitCode == 0) {
    return (r.stdout as String).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }
  if (noMatchIsEmpty && r.exitCode == 1) return const [];
  return null;
}

int _spawn(List<String> files, String flutterBin) {
  final r = Process.runSync(flutterBin, ['test', ...files, '--exclude-tags', 'golden'],
      environment: _spawnEnv(), includeParentEnvironment: false, runInShell: true);
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode == 79) {
    stdout.writeln('$_tag flutter reported "No tests ran" (exit 79) -- treated as nothing to run.');
    return 0;
  }
  return r.exitCode;
}

void main(List<String> args) {
  final env = Platform.environment;
  if (env['CONTRACT_SWEEP_SKIP'] == '1') {
    stdout.writeln('$_tag skipped (CONTRACT_SWEEP_SKIP=1).');
    exit(0);
  }
  if (env['CONTRACT_SWEEP_NESTED'] == '1') {
    stdout.writeln('$_tag skipped -- nested inside a sweep-spawned flutter test (recursion guard).');
    exit(0);
  }
  final warnOnly = args.contains('--warn-only');
  final flutterBin = _arg(args, '--flutter-bin') ?? 'flutter';
  try {
    exit(_run(args, warnOnly: warnOnly, flutterBin: flutterBin));
  } catch (e, st) {
    stderr.writeln('$_tag internal error: $e\n$st');
    stderr.writeln('$_tag fallback: running ${SweepSelection.fallbackTarget} (fail-safe to MORE testing).');
    final code = _spawn(const [SweepSelection.fallbackTarget], flutterBin);
    exit(warnOnly ? 0 : code);
  }
}

int _run(List<String> args, {required bool warnOnly, required String flutterBin}) {
  final dryRun = args.contains('--dry-run');
  final range = _arg(args, '--range') ?? _defaultRange;

  final changed = _gitLines(['-c', 'core.quotePath=false', 'diff', '--no-renames', '--name-only', range]);
  final registryFile = File('docs/sot_registry.yaml');
  final registry = registryFile.existsSync() ? registryFile.readAsStringSync() : null;

  final SweepSelection sel;
  if (changed == null) {
    sel = buildSelection(changedPaths: const [], registryYaml: null, grepResults: const {}, exists: (_) => true);
    stdout.writeln('$_tag fallback: `git diff --name-only $range` failed (origin/main unresolvable?) -> ${SweepSelection.fallbackTarget}');
  } else {
    final keys = contentReferenceKeys(changed);
    final grep = <String, List<String>?>{
      for (final k in keys) k: _gitLines(['grep', '-l', '-F', k, '--', 'test/'], noMatchIsEmpty: true),
    };
    sel = buildSelection(changedPaths: changed, registryYaml: registry, grepResults: grep, exists: (p) => File(p).existsSync());
    if (sel.fallbackReason != null) stdout.writeln('$_tag fallback: ${sel.fallbackReason} -> ${SweepSelection.fallbackTarget}');
  }

  stdout.writeln('$_tag range=$range changed=${changed?.length ?? '?'} selected=${sel.tests.length}');
  for (final t in sel.tests) {
    stdout.writeln('$_tag   run  $t');
  }
  for (final s in sel.skipped) {
    stdout.writeln('$_tag   skip $s (not a dart test, or a golden)');
  }
  for (final d in sel.droppedMissing) {
    stdout.writeln('$_tag   dropped $d (selected but absent on disk)');
  }
  for (final u in sel.unmappedChanged) {
    stdout.writeln('$_tag   unmapped $u (no registry concept and no test references its basename)');
  }

  if (sel.tests.isEmpty) {
    stdout.writeln('$_tag nothing selected -- OK');
    return 0;
  }
  if (dryRun) {
    stdout.writeln('$_tag dry-run -- not spawning flutter');
    return 0;
  }
  final code = _spawn(sel.tests, flutterBin);
  if (code == 0) {
    stdout.writeln('$_tag OK -- ${sel.tests.length} file(s) green.');
    return 0;
  }
  stderr.writeln('$_tag ${warnOnly ? 'WARN' : 'FAIL'}: flutter test exit $code on ${sel.tests.length} selected file(s).');
  return warnOnly ? 0 : code;
}
