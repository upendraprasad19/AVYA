// scripts/check_gate_source_literal_whitespace_brittleness.dart
//
// WARN-ONLY advisory: flags a NEW `.contains('...')` / `== '...'` literal
// comparison, added to gate-authoring code (`scripts/check_*.dart` or
// `scripts/*_lib.dart`), whose literal is multi-word (contains an internal
// space) and is NOT already regex-based on that line.
//
// WHY (feedback_mistake_guard_without_its_mirror.md #7/#8, 2026-08-11): a
// gate matched `'flutter analyze'` as an exact literal against captured
// shell-command text and was defeated by `'flutter  analyze'` — one extra
// space. `RegExp(r'flutter\s+analyze')` would not have this blind spot.
//
// This gate NEVER hard-fails — the underlying judgment ("is this literal
// really comparing against untrusted/variable-whitespace source text, or
// just an ordinary string constant") is inherently fuzzy, and false
// positives here have real cost. It always exits 0; a hit prints a loud
// WARN so a reviewer can judge it, same trust model as several other
// self-attested residues in this repo (rule 21's presence_only:, rule 24's
// ledger, §4.12.4's ship_dark_build tier).
//
// Detection logic lives in scripts/gate_source_literal_brittleness_lib.dart
// (pure, git-free, unit-tested, mutation-proven). This file only gathers
// the staged diff and prints the verdict.
//
// Exit: ALWAYS 0. `--warn-only` accepted and ignored (interface consistency
// with this batch's other gates — this one is warn-only unconditionally).

import 'dart:convert';
import 'dart:io';

import 'gate_source_literal_brittleness_lib.dart';

const _tag = '[gate-literal-whitespace-brittle]';

void main(List<String> args) {
  // Staged additions only, zero context lines, scoped to gate-authoring
  // files. stdoutEncoding: utf8 is load-bearing on Windows — see
  // check_no_deferral_euphemism.dart's header for the mojibake incident
  // this convention exists to avoid.
  final result = Process.runSync(
    'git',
    [
      'diff',
      '--cached',
      '--unified=0',
      '--no-color',
      '--',
      'scripts/check_*.dart',
      'scripts/*_lib.dart',
    ],
    stdoutEncoding: utf8,
  );

  if (result.exitCode != 0) {
    stdout.writeln(
        '$_tag NOTE: git diff --cached unavailable — the staged-diff scan '
        'did not run. This gate never fails; nothing to report.');
    exit(0);
  }

  final hits = findBrittleLiteralComparisons(result.stdout as String);

  if (hits.isEmpty) {
    stdout.writeln('$_tag PASS: no brittle literal comparisons added to '
        'gate-authoring code.');
    exit(0);
  }

  stderr.writeln('$_tag WARN: ${hits.length} brittle literal comparison(s) '
      'added — review before trusting them against real source text:');
  for (final h in hits) {
    stderr.writeln('  $h');
  }
  // Always 0 — this gate is advisory only.
  exit(0);
}
