// scripts/check_cqrs_query_naming.dart
//
// Gate (OI-44 / L26) — a method whose NAME promises a query must not MUTATE.
//
// Thin CLI over `scripts/cqrs_query_naming_lib.dart`, which holds the
// detection logic and the exemption ledger, and which
// `test/contracts/cqrs_query_naming_gate_test.dart` imports directly. Read
// that file for the full rationale (why catch blocks are stripped, why the
// writer-verb layer exists, why delegation is resolved transitively).
//
// Usage:
//   dart run scripts/check_cqrs_query_naming.dart              # hard-fail
//   dart run scripts/check_cqrs_query_naming.dart --warn-only  # report only
//   dart run scripts/check_cqrs_query_naming.dart --no-getters # methods only
//   dart run scripts/check_cqrs_query_naming.dart --root=<dir> # scan elsewhere

import 'dart:io';

import 'cqrs_query_naming_lib.dart';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  // Getters are scanned BY DEFAULT (round-1 P2-7). pre-commit.sh and CI invoke
  // every gate with NO arguments, so an opt-in --getters flag meant the wired
  // configuration never scanned them — while lib/CLAUDE.md and
  // lib/core/services/CLAUDE.md both advertise that the gate covers any
  // query-named MEMBER. `bool get isX => ...mutates...` is exactly the shape
  // that reads pure at the callsite. --no-getters remains for debugging.
  final includeGetters = !args.contains('--no-getters');
  final rootPath = args
      .firstWhere((a) => a.startsWith('--root='), orElse: () => '--root=lib')
      .substring('--root='.length);

  final CqrsScanResult result;
  try {
    result = scanRoot(rootPath, includeGetters: includeGetters);
  } on ArgumentError catch (e) {
    stderr.writeln('[cqrs-query-naming] FAIL: ${e.message}');
    exit(1);
  }

  // The ledger is keyed on lib/ paths, so it neither applies nor can be judged
  // stale when scanning a fixture root.
  final defaultRoot = rootPath == 'lib';
  final stale = defaultRoot ? staleExemptions(result) : const <String>[];
  final unexempted = result.unexempted(applyExemptions: defaultRoot);

  var failed = false;

  if (stale.isNotEmpty) {
    failed = true;
    stderr.writeln('[cqrs-query-naming] FAIL: ${stale.length} STALE '
        'exemption(s) — the member no longer mutates, so delete the entry '
        'from cqrsExemptions (that deletion IS the record that it closed):');
    for (final k in stale) {
      stderr.writeln('  - $k');
    }
  }

  if (unexempted.isNotEmpty) {
    failed = true;
    stderr.writeln('[cqrs-query-naming] ${warnOnly ? 'WARN' : 'FAIL'}: '
        '${unexempted.length} query-named member(s) mutate on the success '
        'path:');
    for (final v in unexempted) {
      stderr.writeln('  - $v');
    }
    stderr.writeln('');
    stderr.writeln('  A get*/is*/has*/calculate* name promises no side effect '
        'at every callsite. Either:');
    stderr.writeln('    (a) split it — pure reader + an explicitly-named '
        'mutator (the C-14 currentStreak() / '
        'consumeMissedDayIfFreezeAvailable() precedent), or');
    stderr.writeln('    (b) rename it to a verb that admits the write, or');
    stderr.writeln('    (c) add a cqrsExemptions entry WITH the reason, if the '
        'mutation is deliberate and load-bearing.');
    stderr.writeln('  Telemetry inside a catch block is NOT a violation and is '
        'already excluded.');
  }

  stdout.writeln('[cqrs-query-naming] '
      '${failed ? (warnOnly ? 'WARN-ONLY' : 'FAIL') : 'OK'}: '
      '${result.membersScanned} query-named member(s) scanned across '
      '${result.filesScanned} file(s) under $rootPath/; '
      '${result.violations.length} mutate '
      '(${defaultRoot ? cqrsExemptions.length : 0} exempted, '
      '${unexempted.length} unexempted).');

  if (failed && !warnOnly) exit(1);
}
