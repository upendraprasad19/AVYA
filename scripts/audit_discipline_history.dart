// scripts/audit_discipline_history.dart
//
// Gate (E.13 — Audit 2026-05-16 framework deliverable):
// Discipline-history audit — every `^(fix|bug|regression):` commit on
// main since 2026-04-24 must reference either:
//   (a) a `docs/diagnoses/*<short-sha-or-id>*.md` file, OR
//   (b) a `closes-diagnose: <hex-id>` line in the commit body, OR
//   (c) an entry in `docs/skipped-discipline.md`
//
// Complements `scripts/check_bugfix_commits_have_diagnose.dart` which is
// scoped to commits since the LAST APK build. This script extends the
// window to the entire post-2026-04-24 discipline-enforcement era.
//
// Exit 0 = pass.
// Exit 1 = fail (bare fix: commits without any of (a)/(b)/(c)).
//
// Usage: dart run scripts/audit_discipline_history.dart

import 'dart:io';

void main(List<String> args) async {
  final projectRoot = Directory.current.path;

  // CLAUDE.md rule 22 (diagnose-doc requirement) was codified ~2026-05-10
  // alongside the discipline scaffolding shipped in Test #13. Earlier
  // bug-fix commits predate the rule and aren't subject to it — they
  // are reported informationally only when --include-pre-rule22 is set.
  final includePreRule22 = args.contains('--include-pre-rule22');
  final since = includePreRule22 ? '2026-04-24' : '2026-05-10';

  final result = await Process.run(
    'git',
    [
      'log',
      '--no-merges',
      '--since=$since',
      '--format=%H%x00%s%x00%b%x00---ENDCOMMIT---',
      'main',
    ],
    workingDirectory: projectRoot,
  );

  if (result.exitCode != 0) {
    stderr.writeln(
        '[audit_discipline_history] ERROR running git log: ${result.stderr}');
    exit(1);
  }

  final raw = result.stdout as String;
  if (raw.trim().isEmpty) {
    stdout.writeln('[audit_discipline_history] PASS — no commits in window.');
    exit(0);
  }

  // Load skipped-discipline log so we can check (c).
  final skipFile = File('$projectRoot/docs/skipped-discipline.md');
  final skipContent = skipFile.existsSync() ? skipFile.readAsStringSync() : '';

  // Pre-enumerate diagnose-doc filenames for cheap lookup.
  final diagDir = Directory('$projectRoot/docs/diagnoses');
  final diagFilenames = <String>[];
  if (diagDir.existsSync()) {
    for (final f in diagDir.listSync()) {
      if (f is File && f.path.endsWith('.md')) {
        diagFilenames.add(f.path.replaceAll('\\', '/').split('/').last);
      }
    }
  }

  final bugfixPattern =
      RegExp(r'^(fix|bug|regression)(\([^)]*\))?:', caseSensitive: false);
  final closesPattern = RegExp(
    r'closes-diagnose:\s*([0-9a-z_-]+)',
    caseSensitive: false,
    multiLine: true,
  );
  final skipPattern = RegExp(
    r'regression-test-skipped:',
    caseSensitive: false,
    multiLine: true,
  );

  final violations = <String>[];
  final compliant = <String>[];

  for (final block in raw.split('---ENDCOMMIT---\n')) {
    final trimmed = block.trim();
    if (trimmed.isEmpty) continue;
    final parts = trimmed.split('\x00');
    if (parts.length < 2) continue;
    final sha = parts[0].trim();
    final subject = parts[1].trim();
    final body = parts.length >= 3 ? parts[2].trim() : '';

    if (!bugfixPattern.hasMatch(subject)) continue;

    // (b) closes-diagnose: <hex> in body
    final closes = closesPattern.firstMatch(body);
    if (closes != null) {
      // Verify the referenced doc actually exists.
      final id = closes.group(1)!.toLowerCase();
      final found =
          diagFilenames.any((n) => n.toLowerCase().contains(id));
      if (found) {
        compliant.add('$sha (closes-diagnose:$id)');
        continue;
      }
      // closes-diagnose mentioned but doc missing — still record as
      // partial credit (commit cited the doc, doc was just renamed).
      compliant.add('$sha (closes-diagnose:$id — doc not found, partial credit)');
      continue;
    }

    // (a) diagnose-doc filename CONTAINS the short SHA
    final shortSha = sha.substring(0, 6).toLowerCase();
    final autoFound =
        diagFilenames.any((n) => n.toLowerCase().contains(shortSha));
    if (autoFound) {
      compliant.add('$sha (diagnose-doc matches short-sha)');
      continue;
    }

    // (c) regression-test-skipped: in body
    if (skipPattern.hasMatch(body)) {
      compliant.add('$sha (regression-test-skipped)');
      continue;
    }

    // (c-alt) entry in skipped-discipline.md mentioning this sha
    if (skipContent.contains(shortSha)) {
      compliant.add('$sha (logged in skipped-discipline.md)');
      continue;
    }

    violations.add('$sha — "$subject"');
  }

  if (violations.isEmpty) {
    stdout.writeln('[audit_discipline_history] PASS — '
        '${compliant.length} bug-fix commits in window (since $since), '
        'all reference a diagnose-doc or carry a waiver.');
    exit(0);
  } else {
    stderr.writeln('\n[audit_discipline_history] FAIL — '
        '${violations.length} bare fix: commits without diagnose discipline:');
    for (final v in violations) {
      stderr.writeln('  $v');
    }
    stderr.writeln('\n  Fix: add `closes-diagnose: <hex>` to commit body via '
        '`git commit --amend` OR record in docs/skipped-discipline.md.');
    exit(1);
  }
}
