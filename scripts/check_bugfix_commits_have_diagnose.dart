// scripts/check_bugfix_commits_have_diagnose.dart
//
// Gate: 10
//
// Gate 10: Bug-fix commits since last APK build reference a valid diagnose-doc.
//
// Logic:
//   1. Find the last APK build commit on main via `git log --grep='bump versionCode'`.
//   2. For every commit in <lastApkSha>..HEAD that is NOT a merge commit:
//      - If subject matches ^(fix|bug|regression)(\([^)]*\))?: → MUST have either
//          closes-diagnose: <6+ hex> referencing a real docs/diagnoses/*-<id>.md
//          OR regression-test-skipped: <reason>
//   3. Exit 1 listing any non-compliant commits.
//
// Exit 0 = pass.
// Exit 1 = fail.
//
// Usage: dart run scripts/check_bugfix_commits_have_diagnose.dart

import 'dart:io';

void main(List<String> args) async {
  final projectRoot = Directory.current.path;

  // ── 1. Find last APK-build commit ─────────────────────────────────────────

  final lastApkResult = await Process.run(
    'git',
    ['log', '--format=%H %s', '--grep=bump versionCode', '-1'],
    workingDirectory: projectRoot,
  );

  if (lastApkResult.exitCode != 0) {
    stderr.writeln(
        '[Gate 10] ERROR: could not run git log: ${lastApkResult.stderr}');
    exit(1);
  }

  final lastApkLine = (lastApkResult.stdout as String).trim();
  if (lastApkLine.isEmpty) {
    // No prior APK commit — treat all commits as "since beginning"
    stdout.writeln(
        '[Gate 10] PASS — no prior APK build commit found; nothing to check.');
    exit(0);
  }

  final lastApkSha = lastApkLine.split(' ').first;

  // ── 2. Get commits since last APK, excluding merges ───────────────────────

  final logResult = await Process.run(
    'git',
    [
      'log',
      '--format=%H%x00%s%x00%b%x00---ENDCOMMIT---',
      '--no-merges',
      '$lastApkSha..HEAD',
    ],
    workingDirectory: projectRoot,
  );

  if (logResult.exitCode != 0) {
    stderr.writeln(
        '[Gate 10] ERROR: could not run git log: ${logResult.stderr}');
    exit(1);
  }

  final rawLog = logResult.stdout as String;
  if (rawLog.trim().isEmpty) {
    stdout.writeln('[Gate 10] PASS — no commits since last APK build ($lastApkSha).');
    exit(0);
  }

  // ── 3. Parse commits ──────────────────────────────────────────────────────

  final commitBlocks = rawLog.split('---ENDCOMMIT---\n');
  final bugfixPattern = RegExp(
    r'^(fix|bug|regression)(\([^)]*\))?:',
    caseSensitive: false,
  );
  final closesPattern = RegExp(
    r'closes-diagnose:\s*([0-9a-f]{6,})',
    caseSensitive: false,
    multiLine: true,
  );
  final skipPattern = RegExp(
    r'regression-test-skipped:\s*\S+',
    caseSensitive: false,
    multiLine: true,
  );

  final violations = <String>[];

  for (final block in commitBlocks) {
    final trimmed = block.trim();
    if (trimmed.isEmpty) continue;

    final parts = trimmed.split('\x00');
    if (parts.length < 2) continue;

    final sha = parts[0].trim();
    final subject = parts[1].trim();
    final body = parts.length >= 3 ? parts[2].trim() : '';

    if (!bugfixPattern.hasMatch(subject)) continue;

    // Check for closes-diagnose OR regression-test-skipped
    final closesMatch = closesPattern.firstMatch(body);
    if (skipPattern.hasMatch(body)) continue; // waiver present

    if (closesMatch == null) {
      violations.add('$sha — "$subject"');
      violations.add('  → missing: closes-diagnose: <hex-id>  OR  regression-test-skipped: <reason>');
      continue;
    }

    // Verify the referenced diagnose-doc actually exists
    final diagnoseId = closesMatch.group(1)!.toLowerCase();
    final diagnosesDir = Directory('$projectRoot/docs/diagnoses');
    var found = false;
    if (diagnosesDir.existsSync()) {
      for (final entity in diagnosesDir.listSync()) {
        if (entity is File && entity.path.contains('-$diagnoseId.md')) {
          found = true;
          break;
        }
      }
    }

    if (!found) {
      violations.add('$sha — "$subject"');
      violations.add(
          '  → closes-diagnose: $diagnoseId references no file in docs/diagnoses/');
    }
  }

  // ── 4. Report ─────────────────────────────────────────────────────────────

  if (violations.isEmpty) {
    stdout.writeln('[Gate 10] PASS — all bug-fix commits since $lastApkSha'
        ' reference valid diagnose-docs or carry regression-test-skipped waivers.');
    exit(0);
  } else {
    stderr.writeln('\n[Gate 10] FAIL — non-compliant bug-fix commits:');
    for (final v in violations) {
      stderr.writeln('  $v');
    }
    stderr.writeln(
        '\n  Fix: run /diagnose-bug to generate a diagnose-doc, then add');
    stderr.writeln(
        '  "closes-diagnose: <6-char-id>" to the commit body. Or add');
    stderr.writeln(
        '  "regression-test-skipped: <reason>" if truly exceptional.');
    exit(1);
  }
}
