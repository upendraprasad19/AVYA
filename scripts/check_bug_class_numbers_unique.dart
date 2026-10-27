// scripts/check_bug_class_numbers_unique.dart
//
// Assert that the debugging skill's bug-class numbers are unique and agree between the two files
// they live in. Takes no gate number: a new gate's filename is its identity (rule 24).
// Closes OI-167 (landing B of docs/plans/merge-conflict-treadmill.md; plan:
// docs/plans/bug-class-uniqueness.md).
//
// THE DEFECT. `.claude/skills/debugging/bug-classes.md` holds one `### 2.N Title` heading per
// class and `.claude/skills/debugging/SKILL.md` one index row. The next number was "max + 1"
// read by eye, and `tail -1` answers "the last-POSITIONED entry", not "the highest" (2.61 was
// minted twice on 2026-09-07; nine numbers ended up on two classes each). Two PRs that mint the
// same next number also collide only when both are merged: this gate runs on the PR's merge
// result in CI and in every commit's pre-commit loop.
//
// WHAT IT READS: the two files in the WORKING TREE (not the staged index). Root: `--root=<dir>`
// if given (the test seam), else the current directory (the pre-commit hook and CI run it from
// the repo root). The PASS line prints the resolved root so a run against the wrong tree shows.
//
// WHAT IT FAILS ON (see scripts/bug_class_ids_lib.dart): an id used twice, an id in one file and
// not the other, a major other than 2, a numeric heading in SKILL.md, a line that looks like a
// heading or row but does not parse, an id whose title differs between the files, a missing file,
// a missing index section, or no headings / no rows at all (a vacuous parse must not PASS).
//
// No git, no network: nothing here can fail open. A duplicate that reaches a tree through a merge
// blocks every commit in that tree until it is renumbered; the output names the ids and the
// next free id.
//
// Usage:
//   dart run scripts/check_bug_class_numbers_unique.dart            # check; exit 0 PASS / 1 FAIL
//   dart run scripts/check_bug_class_numbers_unique.dart --next     # print the next free id
//   dart run scripts/check_bug_class_numbers_unique.dart --root=<dir>
//
// Exit codes: 0 PASS (or --next printed), 1 a finding / unreadable input, 2 bad arguments.
// PASS goes to stdout; every finding goes to stderr as `<path>:<line>: <message>`.

import 'dart:io';

import 'bug_class_ids_lib.dart';

const String _usage = 'usage: dart run scripts/check_bug_class_numbers_unique.dart '
    '[--next] [--root=<dir>]';

/// Reads [path]; returns null and records a reason in [reasons] when it cannot be read as UTF-8.
String? _read(String root, String relative, List<String> reasons) {
  try {
    return File('$root/$relative').readAsStringSync();
  } on FileSystemException catch (e) {
    reasons.add('$relative: cannot read the file (${e.osError?.message ?? e.message})');
  } on FormatException catch (e) {
    // This SDK reports invalid UTF-8 as a FileSystemException (see the branch above); another may
    // throw a FormatException. Either way the run must end in exit 1 with the file named.
    reasons.add('$relative: the file is not valid UTF-8 (${e.message})');
  }
  return null;
}

void main(List<String> args) {
  var wantNext = false;
  String? rootArg;
  for (final a in args) {
    if (a == '--next') {
      wantNext = true;
    } else if (a.startsWith('--root=')) {
      rootArg = a.substring('--root='.length);
    } else {
      stderr.writeln('check_bug_class_numbers_unique: unknown argument "$a"');
      stderr.writeln(_usage);
      exit(2);
    }
  }
  if (rootArg != null && rootArg.isEmpty) {
    stderr.writeln('check_bug_class_numbers_unique: --root= needs a directory');
    stderr.writeln(_usage);
    exit(2);
  }
  final root = rootArg ?? Directory.current.path;
  final absoluteRoot = Directory(root).absolute.path;

  final reasons = <String>[];
  final bugClasses = _read(root, kBugClassesPath, reasons);
  final skill = _read(root, kBugClassSkillPath, reasons);
  if (bugClasses == null || skill == null) {
    for (final r in reasons) {
      stderr.writeln(r);
    }
    stderr.writeln('(root: $absoluteRoot)');
    exit(1);
  }

  final report = checkBugClassNumbers(bugClasses, skill);
  if (report.indexSectionMissing) {
    stderr.writeln('$kBugClassSkillPath: the index section "$kIndexHeadingPrefix" is missing; '
        'cannot compare the two files (root: $absoluteRoot)');
    exit(1);
  }

  if (wantNext) {
    final next = report.nextFree;
    if (next == null) {
      stderr.writeln('check_bug_class_numbers_unique: no major-2 id found in either file; '
          'cannot compute the next free id');
      exit(1);
    }
    for (final f in report.findings) {
      stderr.writeln('${f.file}:${f.line}: ${f.message}');
    }
    stdout.writeln(next);
    exit(0);
  }

  if (report.headings.isEmpty || report.rows.isEmpty) {
    // The findings (a lookalike heading, a malformed row, an unclosed fence) are usually WHY the
    // parse found nothing; print them before the summary.
    for (final f in report.findings) {
      stderr.writeln('${f.file}:${f.line}: ${f.message}');
    }
    stderr.writeln('check_bug_class_numbers_unique: parsed ${report.headings.length} headings '
        'and ${report.rows.length} index rows; a catalog with no headings or no rows is a '
        'failed parse, not a pass');
    exit(1);
  }

  if (report.findings.isEmpty) {
    stdout.writeln('PASS bug-class numbers unique '
        '(headings=${report.headings.length} rows=${report.rows.length}, root=$absoluteRoot)');
    exit(0);
  }

  for (final f in report.findings) {
    stderr.writeln('${f.file}:${f.line}: ${f.message}');
  }
  final next = report.nextFree;
  if (next != null) stderr.writeln('next free id: $next');
  exit(1);
}
