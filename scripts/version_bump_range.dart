// scripts/version_bump_range.dart
//
// Usage:  dart scripts/version_bump_range.dart <baseRev> <headRev>
//
// Exit 0   the net change <baseRev>..<headRev> is a bare version bump (the SAME
//          predicate the CI keystone gate, scripts/check_plan_review_record_exists.dart,
//          applies to a direct commit and to a merge commit: rangeIsVersionBump in
//          scripts/version_bump_git_lib.dart).
// Exit 1   it is not - including when git could not answer. Fail-closed: a caller
//          treats 1 as "no exemption", never as "unknown, assume fine".
// Exit 64  usage.
//
// Why a CLI at all: scripts/safe_merge.sh previews the gate's "no plan-review record"
// failure BEFORE a merge exists, but it could not mirror the version-bump exemption
// (it is Dart, not shell - OI-222), so it told the author of a bump branch they needed
// a record they do not need. The advisory passes the merge base and the branch tip.
//
// Prints one line saying which way it decided, on stdout, so the advisory can show it.

import 'dart:io';

import 'version_bump_git_lib.dart';

int _run(List<String> args) {
  if (args.length != 2 || args.any((a) => a.trim().isEmpty)) {
    stderr.writeln('usage: dart scripts/version_bump_range.dart <baseRev> <headRev>');
    return 64;
  }
  final isBump = rangeIsVersionBump(args[0], args[1]);
  stdout.writeln(isBump
      ? 'version_bump_range: ${args[0]}..${args[1]} is a bare version bump'
      : 'version_bump_range: ${args[0]}..${args[1]} is NOT a bare version bump '
          '(or git could not answer)');
  return isBump ? 0 : 1;
}

void main(List<String> args) => exit(_run(args));
