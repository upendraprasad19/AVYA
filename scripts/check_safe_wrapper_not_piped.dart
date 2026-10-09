// scripts/check_safe_wrapper_not_piped.dart
//
// Blocks a STAGED ADDED line piping `safe_push.sh`/`safe_commit.sh` through
// `head`/`tail`. See safe_wrapper_not_piped_lib.dart for the bug class
// (CLAUDE.md §4.9 pitfalls table — a documented rule with zero enforcement
// until this gate; cost a real 5-minute push cycle per
// feedback_green_check_input_set_width.md #29's third error).
//
// Zero legitimate counter-case: the wrapper deletes its own temp log after
// printing it, so truncating that stdout can only ever discard information.
//
// Exit 0 = pass. Exit 1 = fail. `--warn-only` never fails.

import 'dart:convert';
import 'dart:io';

import 'safe_wrapper_not_piped_lib.dart';

const _tag = '[safe-wrapper-piped]';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');

  final result = Process.runSync(
    'git',
    [
      'diff',
      '--cached',
      '--unified=0',
      '--no-color',
      '--',
      '*.sh',
      '*.md',
      '*.dart',
      // Self-exclusion (see check_analyze_narrower_than_lib_in_tooling.dart
      // for the general note): this gate's own test file's fixture strings
      // necessarily quote the exact piped shape it detects.
      ':!scripts/check_safe_wrapper_not_piped.dart',
      ':!scripts/safe_wrapper_not_piped_lib.dart',
      ':!test/scripts/safe_wrapper_not_piped_lib_test.dart',
    ],
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) {
    stdout.writeln('$_tag NOTE: git diff --cached unavailable — skipped.');
    exit(0);
  }

  final violations = <String>[];
  var currentFile = '';
  for (final raw in const LineSplitter().convert(result.stdout.toString())) {
    if (raw.startsWith('+++ b/')) {
      currentFile = raw.substring('+++ b/'.length).trim();
      continue;
    }
    if (!raw.startsWith('+') || raw.startsWith('+++')) continue;
    final added = raw.substring(1);
    if (isPipedThroughHeadOrTail(added)) {
      violations.add('$currentFile:  ${added.trim()}');
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('$_tag PASS: no safe_push.sh/safe_commit.sh piped through head/tail.');
    exit(0);
  }

  final tag = warnOnly ? '[safe-wrapper-piped WARN]' : '[safe-wrapper-piped]';
  stderr.writeln('$tag FAIL: ${violations.length} invocation(s) pipe '
      'safe_push.sh/safe_commit.sh through head/tail:');
  for (final v in violations) {
    stderr.writeln('  $v');
  }
  stderr.writeln(
    '\n  The wrapper prints a temp log then DELETES it -- truncating that\n'
    '  stdout destroys the only copy of the diagnostic. Never pipe it.',
  );
  exit(warnOnly ? 0 : 1);
}
