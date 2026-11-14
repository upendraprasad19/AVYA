// scripts/check_single_schedule_row_builder.dart
//
// Asserts that only the allowlisted files construct a `schedule_<date>` Hive
// row map. Detection + the allowlist live in the pure, unit-tested
// scripts/schedule_row_builder_gate_lib.dart; this file only gathers files.
//
// WHY (OI-166, 2026-09-07). Four independent implementations of "lay out
// schedule rows for a phase" had drifted into 8 real differences, 4 of them
// live user-visible defects — while three of the four carried comments
// asserting they mirrored each other. Comments do not hold; a gate does.
// Per CLAUDE.md §4.11 (gates before refactor) this ships in an EARLIER commit
// than the de-duplication it protects, so each later refactor commit can
// detect its own partial-state drift.
//
// ⚠ WARN IS THE BUILT-IN DEFAULT, NOT A FLAG AT THE CALL SITE, and that is
// deliberate (review round 5, P2-11). Both scripts/pre-commit.sh and
// .github/workflows/test.yml auto-wire every scripts/check_*.dart BY GLOB with
// NO arguments, so this gate is live from the commit it lands in and nothing
// can pass it `--warn-only`. §4.11's baseline window therefore has to be
// expressed as the default of `_hardFail` below.
// ⚠ CORRECTED 2026-09-12 (OI-190): this header used to say "OI-166 Unit 2's final
// commit flips it to `true`". Unit 2 shipped (`de52f1e8`) WITHOUT the shared
// builder — its round-1 review found the builder as specified could not express
// what caller C already does, and the re-plan fixed B and C in place. So the
// flip did not happen, both `pendingUnit2` entries still stand, and
// `lib/core/services/schedule_row_builder.dart` does not exist yet. The flip is
// owned by OI-190: the same commit that lands the builder and empties the
// `pendingUnit2` list sets `_hardFail = true`. Until then this gate's value is
// that no THIRD implementation can appear in lib/ unlisted.
//
// ⚠ SCOPE IS `lib/` ONLY. Run repo-wide the same heuristic matches two
// existing test fixtures plus every behavioural test Unit 2 adds — the
// hard-fail flip would break the build on the batch's own tests. See the
// library header for the full reasoning and for the two known blind spots.
//
// Exit 0 = pass (or warn). Exit 1 = fail. `--warn-only` never fails;
// `--strict` forces failure regardless of `_hardFail`.

import 'dart:io';

import 'schedule_row_builder_gate_lib.dart';

/// Flip to `true` in OI-166 Unit 2's final commit, once every
/// `ScheduleRowExemption.pendingUnit2` entry has been removed from the
/// allowlist. Until then this gate reports and passes.
const bool _hardFail = false;

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final strict = args.contains('--strict');

  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    // Fail OPEN. Being unable to find lib/ means we are not where we think we
    // are (a hook running from an odd cwd, a partial checkout) — never wedge a
    // commit on that. Same posture as check_worktree_config_integrity.dart.
    stdout.writeln(
        '[schedule-row-builder] SKIPPED: no lib/ directory from ${Directory.current.path}');
    exit(0);
  }

  final files = <String, String>{};
  for (final e in libDir.listSync(recursive: true, followLinks: false)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final rel = e.path.replaceAll(r'\', '/');
    final idx = rel.indexOf('lib/');
    files[idx <= 0 ? rel : rel.substring(idx)] = e.readAsStringSync();
  }

  final violations = scheduleRowViolations(files);
  final stale = staleAllowlistEntries(files);

  for (final path in stale) {
    stdout.writeln(
        '[schedule-row-builder] WARN: allowlist entry no longer constructs a '
        'schedule row, delete it: $path');
  }

  if (violations.isEmpty) {
    final pending = scheduleRowAllowlist.entries
        .where((e) => e.value == ScheduleRowExemption.pendingUnit2)
        .length;
    stdout.writeln(
        '[schedule-row-builder] PASS: ${files.length} lib/ file(s) scanned, '
        'no unlisted schedule-row constructor'
        '${pending > 0 ? ' ($pending pending OI-166 Unit 2 migration)' : ''}.');
    exit(0);
  }

  stdout.writeln(
      '[schedule-row-builder] ${violations.length} file(s) construct a schedule '
      'row outside the shared builder:');
  for (final path in violations) {
    stdout.writeln('  - $path');
  }
  stdout.writeln(
      '  Use lib/core/services/schedule_row_builder.dart, or — if this is '
      'genuinely not a phase layout — add it to `scheduleRowAllowlist` in '
      'scripts/schedule_row_builder_gate_lib.dart WITH A REASON, and update '
      'test/scripts/schedule_row_builder_gate_lib_test.dart, which pins the '
      'exact allowlist contents.');

  if (warnOnly || (!strict && !_hardFail)) {
    stdout.writeln(
        '[schedule-row-builder] WARN-ONLY (baseline window, CLAUDE.md §4.11) — '
        'not failing.');
    exit(0);
  }
  exit(1);
}
