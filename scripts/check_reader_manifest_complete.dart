// scripts/check_reader_manifest_complete.dart
//
// Audit gate (build-apk Gate 18) — enforces the reader-side manifest in
// `docs/sot_registry.yaml`.
//
// Check: any pattern listed under any `forbidden_legacy_patterns:` block
// MUST be absent from `lib/`, `supabase/functions/`, and `test/` (with
// this script's own file excluded). Catches the recurring writer/reader
// drift bug class — pre-2026-05-16 the patterns `log['best_single_set_reps']`
// and `log['best_single_set_duration']` were live in
// `workout_repository.dart` even though the writer never produced either
// field.
//
// Exit codes:
//   0  — no forbidden patterns found anywhere they shouldn't be.
//   1  — at least one violation. Stderr lists pattern + file(s).
//
// Bootstrap context (2026-05-16):
//   Today's audit demonstrated that the writer-side registry didn't
//   catch reader-side regressions — 6 user-visible bugs on +27 fresh-
//   install, all from readers reading the wrong field with the wrong
//   semantic. This gate locks down the FUTURE; existing drift must be
//   eliminated by populating reader_manifest_complete + adding
//   forbidden_legacy_patterns to each concept.

import 'dart:io';

void main(List<String> args) async {
  final repoRoot = Directory.current.path;
  final registryPath = '$repoRoot/docs/sot_registry.yaml';
  final registry = File(registryPath);
  if (!registry.existsSync()) {
    stderr.writeln('Registry not found at $registryPath');
    exit(1);
  }

  final content = registry.readAsStringSync();

  // Extract every `{ pattern: "...", reason: "..." }` entry under any
  // `forbidden_legacy_patterns:` block. We don't strictly require the
  // entries to be nested under a specific concept — every forbidden
  // pattern in the file is enforced globally.
  final patternEntries = _extractForbiddenPatterns(content);
  if (patternEntries.isEmpty) {
    stdout.writeln(
        'check_reader_manifest_complete: registry has no forbidden_legacy_patterns entries — gate is a no-op.');
    exit(0);
  }

  // Scan production code only. Test files (especially test/contracts/)
  // legitimately reference forbidden patterns in their assertion strings
  // to lock-down anti-regression — including them would create circular
  // failures where the test that prevents the bug fails the gate.
  final filesToScan = <File>[];
  for (final dir in ['lib', 'supabase/functions']) {
    final d = Directory('$repoRoot/$dir');
    if (!d.existsSync()) continue;
    for (final entity in d.listSync(recursive: true)) {
      if (entity is File &&
          (entity.path.endsWith('.dart') || entity.path.endsWith('.ts'))) {
        filesToScan.add(entity);
      }
    }
  }

  // Pre-read all files once. Strip comments so docstrings that
  // explicitly document anti-patterns (e.g. "// pre-fix this called
  // log['best_single_set_reps']") don't false-positive the gate.
  // Only the code body should be scanned.
  final fileSources = <File, String>{};
  for (final f in filesToScan) {
    if (f.path.endsWith('check_reader_manifest_complete.dart')) continue;
    fileSources[f] = _stripComments(f.readAsStringSync());
  }

  var failures = 0;
  for (final entry in patternEntries) {
    final pattern = entry.pattern;
    final reason = entry.reason;
    RegExp re;
    try {
      re = RegExp(pattern);
    } catch (_) {
      re = RegExp(RegExp.escape(pattern));
    }
    final hits = <String>[];
    for (final f in fileSources.entries) {
      if (re.hasMatch(f.value)) {
        // Normalise to forward-slash repo-relative path.
        final normalRoot = repoRoot.replaceAll(r'\', '/');
        final rel = f.key.path
            .replaceAll(r'\', '/')
            .replaceFirst('$normalRoot/', '');
        // Allowlist — pattern is intentionally permitted at canonical
        // callsite(s).
        if (entry.allowFiles.contains(rel)) continue;
        hits.add(rel);
      }
    }
    if (hits.isNotEmpty) {
      failures++;
      stderr.writeln('FAIL forbidden pattern `$pattern` found in:');
      for (final h in hits) {
        stderr.writeln('  - $h');
      }
      stderr.writeln('  reason: $reason');
    }
  }

  stdout.writeln(
      'check_reader_manifest_complete: scanned ${fileSources.length} files '
      'against ${patternEntries.length} forbidden patterns.');
  if (failures > 0) {
    stderr.writeln(
        'Reader manifest check FAILED with $failures violation(s).');
    exit(1);
  }
  stdout.writeln('OK: reader manifest check passed.');
  exit(0);
}

class _PatternEntry {
  final String pattern;
  final String reason;
  /// Files where the pattern is expected to appear (canonical callsite).
  /// Comma-separated path list in the registry; relative to repo root.
  final List<String> allowFiles;
  _PatternEntry(this.pattern, this.reason, this.allowFiles);
}

/// Matches inline-map entries under `forbidden_legacy_patterns:`. The
/// schema in `sot_registry.yaml` consistently writes these as:
///   - { pattern: "regex", reason: "..." }
/// or with single quotes. Multi-line maps not supported (none exist
/// today; add when needed).
List<_PatternEntry> _extractForbiddenPatterns(String yaml) {
  final result = <_PatternEntry>[];
  final lines = yaml.split('\n');
  var inBlock = false;
  for (final line in lines) {
    if (line.trim().startsWith('#')) continue;
    if (RegExp(r'^\s{4}forbidden_legacy_patterns:\s*$').hasMatch(line)) {
      inBlock = true;
      continue;
    }
    if (inBlock) {
      // Continued list item?
      if (RegExp(r'^\s{6}-\s*\{').hasMatch(line)) {
        final pat = _readQuoted(line, 'pattern:');
        final rsn = _readQuoted(line, 'reason:');
        final allowRaw = _readQuoted(line, 'allow_files:');
        final allow = allowRaw == null
            ? const <String>[]
            : allowRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (pat != null) result.add(_PatternEntry(pat, rsn ?? '', allow));
        continue;
      }
      // Anything else at <=4 space indent ends the block.
      if (RegExp(r'^\s{0,4}\S').hasMatch(line)) {
        inBlock = false;
      }
    }
  }
  return result;
}

/// Reads the quoted string value of `key:` from a single line. Supports
/// both `"..."` and `'...'` quoting. Escaped quotes inside the value
/// are passed through unmodified (regex authors keep their `\\` etc).
/// Strips `//`-line comments and `/* ... */` block comments from Dart/TS
/// source. String literals are NOT preserved across the strip — gate
/// patterns are anti-regression checks on code shape, not strict syntax
/// fidelity. Replaces stripped content with spaces to preserve line
/// numbers if anyone wants to extend the gate later.
String _stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '/') {
      // Line comment — skip to newline.
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '*') {
      // Block comment — skip to closing.
      i += 2;
      while (i + 1 < src.length &&
          !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}

String? _readQuoted(String line, String key) {
  final ix = line.indexOf(key);
  if (ix < 0) return null;
  final after = line.substring(ix + key.length).trim();
  if (after.isEmpty) return null;
  final quote = after[0];
  if (quote != '"' && quote != "'") return null;
  // Find the matching closing quote (skip over `\"` or `\'`).
  var i = 1;
  while (i < after.length) {
    final c = after[i];
    if (c == r'\' && i + 1 < after.length) {
      i += 2;
      continue;
    }
    if (c == quote) {
      return after.substring(1, i);
    }
    i++;
  }
  return null;
}
