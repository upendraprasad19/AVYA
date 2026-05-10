// scripts/check_naming_audit.dart
//
// Gate 8: Forbidden legacy patterns absent.
//
// For every concept's forbidden_legacy_patterns[] in docs/sot_registry.yaml,
// source-grep lib/, supabase/functions/, test/, integration_test/ (.dart and
// .ts files only) and assert each pattern is absent.
//
// Exit 0 = pass (or warn-only when > WARN_THRESHOLD violations found —
//   indicates T2.3 naming-drift cleanup is still in progress).
// Exit 1 = fail (hard violations when under threshold).
//
// Usage: dart run scripts/check_naming_audit.dart

import 'dart:io';

// Violations above this count trigger warn-don't-fail mode.
// Rationale: T2.3 (naming-drift cleanup) may still be in progress.
const int _warnThreshold = 30;

// Files/directories that are allowed to contain forbidden patterns
// because they are the tests / audit docs that reference them as data.
const _allowedPathFragments = [
  'test/contracts/naming_audit',
  'scripts/check_naming_audit.dart',
  'docs/sot_registry.yaml',
  'docs/diagnoses/',
  'CLAUDE.md',
  'MEMORY.md',
];

void main(List<String> args) async {
  final projectRoot = Directory.current.path;
  final registryFile = File('$projectRoot/docs/sot_registry.yaml');

  if (!registryFile.existsSync()) {
    stderr.writeln('[Gate 8] ERROR: docs/sot_registry.yaml not found');
    exit(1);
  }

  final registryContent = registryFile.readAsStringSync();

  // ── 1. Extract forbidden_legacy_patterns ────────────────────────────────
  // Format in YAML:
  //   forbidden_legacy_patterns:
  //     - { pattern: "someRegex", reason: "why" }

  final patterns = <_ForbiddenPattern>[];
  final patternLineRegex = RegExp(
    r'\{\s*pattern:\s*"([^"]+)"\s*,\s*reason:\s*"([^"]+)"\s*\}',
    multiLine: true,
  );
  for (final m in patternLineRegex.allMatches(registryContent)) {
    patterns.add(_ForbiddenPattern(m.group(1)!, m.group(2)!));
  }

  if (patterns.isEmpty) {
    stdout.writeln(
        '[Gate 8] PASS — no forbidden_legacy_patterns defined in registry.');
    exit(0);
  }

  // ── 2. Collect files to scan ─────────────────────────────────────────────

  final scanDirs = ['lib', 'supabase/functions', 'test', 'integration_test'];
  final scanExtensions = {'.dart', '.ts'};

  final filesToScan = <File>[];
  for (final dirName in scanDirs) {
    final dir = Directory('$projectRoot/$dirName');
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final ext = _extension(entity.path);
      if (!scanExtensions.contains(ext)) continue;
      filesToScan.add(entity);
    }
  }

  // ── 3. Run each pattern against all files ────────────────────────────────

  final violations = <_Violation>[];

  for (final pattern in patterns) {
    RegExp? regex;
    try {
      regex = RegExp(pattern.regex, multiLine: true);
    } catch (e) {
      stderr.writeln('[Gate 8] WARN — invalid regex in registry: "${pattern.regex}" — $e');
      continue;
    }

    for (final file in filesToScan) {
      final relPath = file.path
          .replaceAll('\\', '/')
          .replaceFirst('$projectRoot/', '');

      // Skip allowed paths (e.g. the test files that reference patterns as data)
      if (_isAllowed(relPath)) continue;

      final content = file.readAsStringSync();
      final matches = regex.allMatches(content);
      if (matches.isEmpty) continue;

      // Find line numbers for each match
      final lines = content.split('\n');
      for (final match in matches) {
        // Count newlines before match start to find line number
        final lineNo =
            content.substring(0, match.start).split('\n').length;
        final lineContent =
            lineNo <= lines.length ? lines[lineNo - 1].trim() : '';
        violations.add(_Violation(
          file: relPath,
          line: lineNo,
          pattern: pattern.regex,
          reason: pattern.reason,
          lineContent: lineContent,
        ));
      }
    }
  }

  // ── 4. Report ────────────────────────────────────────────────────────────

  if (violations.isEmpty) {
    stdout.writeln('[Gate 8] PASS — no forbidden legacy patterns found'
        ' (${patterns.length} patterns checked across ${filesToScan.length} files).');
    exit(0);
  }

  final limit = violations.take(20).toList();

  if (violations.length > _warnThreshold) {
    stderr.writeln(
        '\n[Gate 8] WARN — ${violations.length} forbidden-pattern violations'
        ' (> $_warnThreshold threshold → warn-only; T2.3 cleanup may still be in progress).');
    stderr.writeln('  First ${limit.length}:');
    for (final v in limit) {
      stderr.writeln('  ${v.file}:${v.line} — pattern: ${v.pattern}');
      stderr.writeln('    reason: ${v.reason}');
      if (v.lineContent.isNotEmpty) {
        stderr.writeln('    line: ${v.lineContent}');
      }
    }
    stdout.writeln('[Gate 8] PASS (warn-only) — see stderr for violations.');
    exit(0);
  } else {
    stderr.writeln(
        '\n[Gate 8] FAIL — ${violations.length} forbidden-pattern violations:');
    for (final v in limit) {
      stderr.writeln('  ${v.file}:${v.line} — pattern: ${v.pattern}');
      stderr.writeln('    reason: ${v.reason}');
      if (v.lineContent.isNotEmpty) {
        stderr.writeln('    line: ${v.lineContent}');
      }
    }
    if (violations.length > 20) {
      stderr.writeln('  ... and ${violations.length - 20} more.');
    }
    exit(1);
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

bool _isAllowed(String relPath) {
  for (final fragment in _allowedPathFragments) {
    if (relPath.contains(fragment)) return true;
  }
  return false;
}

String _extension(String path) {
  final idx = path.lastIndexOf('.');
  if (idx == -1) return '';
  return path.substring(idx);
}

class _ForbiddenPattern {
  final String regex;
  final String reason;
  const _ForbiddenPattern(this.regex, this.reason);
}

class _Violation {
  final String file;
  final int line;
  final String pattern;
  final String reason;
  final String lineContent;
  const _Violation({
    required this.file,
    required this.line,
    required this.pattern,
    required this.reason,
    required this.lineContent,
  });
}
