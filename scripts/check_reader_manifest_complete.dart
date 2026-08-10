// scripts/check_reader_manifest_complete.dart
//
// Gate: 18
//
// Audit gate (build-apk Gate 18) — enforces the reader-side manifest in
// `docs/sot_registry.yaml`.
//
// PHASE 1 (forbidden-patterns):
//   Any pattern listed under any `forbidden_legacy_patterns:` block MUST
//   be absent from `lib/` and `supabase/functions/`. Catches the
//   recurring writer/reader drift bug class.
//
// PHASE 2 (exhaustive reader completeness — added OI-01, 2026-05-17):
//   For every concept with BOTH `reader_manifest_complete: true` AND
//   `hive.key_prefix` set (non-empty, non-placeholder), every source
//   file in `lib/` + `supabase/functions/` that contains a Hive-read
//   reference to the prefix MUST appear in EITHER:
//     - the concept's `readers:` list
//     - the concept's `writers:` list (writers may read their own prefix)
//     - the concept's `reader_allow_files:` whitelist (ad-hoc helpers,
//       migrators, dead-code-elimination tools)
//
//   Reference forms detected (heuristic source-grep):
//     - `<box>.get('<prefix>...')`
//     - `key.startsWith('<prefix>')` / `keyStr.startsWith('<prefix>')`
//     - `<map>['<prefix>...']` literal-string key access
//     - `<prefix>` substring inside a Hive-read context (loose backup)
//
// Exit codes:
//   0  — all phases pass.
//   1  — at least one violation. Stderr lists the offender(s).

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

  // PHASE 1 — forbidden patterns.
  final patternEntries = _extractForbiddenPatterns(content);

  // PHASE 2 — concept manifests with key_prefix.
  final concepts = _extractConcepts(content);

  // Scan production code only. Test files (especially test/contracts/)
  // legitimately reference forbidden patterns in their assertion strings
  // to lock-down anti-regression — including them would create circular
  // failures.
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
  // document anti-patterns don't false-positive the gate.
  final fileSources = <File, String>{};
  final fileRelPaths = <File, String>{};
  final normalRoot = repoRoot.replaceAll(r'\', '/');
  for (final f in filesToScan) {
    if (f.path.endsWith('check_reader_manifest_complete.dart')) continue;
    fileSources[f] = _stripComments(f.readAsStringSync());
    fileRelPaths[f] = f.path
        .replaceAll(r'\', '/')
        .replaceFirst('$normalRoot/', '');
  }

  var failures = 0;

  // --- Phase 1 ---
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
        final rel = fileRelPaths[f.key]!;
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

  // --- Phase 2 ---
  var conceptsChecked = 0;
  for (final c in concepts) {
    if (!c.readerManifestComplete) continue;
    final prefix = c.keyPrefix;
    if (prefix == null || prefix.isEmpty) continue;
    // Skip placeholder/sentinel prefixes such as
    // "<per-key — see UserConfigMigrator.userScopedKeys>".
    if (prefix.startsWith('<') || prefix.contains('—')) continue;
    conceptsChecked++;

    // Build the set of files declared as readers / writers / allow.
    final declared = <String>{
      ...c.readers,
      ...c.writers,
      ...c.readerAllowFiles,
    };

    // Find every source file that references the prefix in a
    // Hive-read context. Detection forms:
    //   a) `.get('<prefix>...')`
    //   b) `.startsWith('<prefix>')`  (key.startsWith / s.startsWith / etc.)
    //   c) `['<prefix>...']`           (literal-string map key)
    //   d) The naked prefix string literal `'<prefix>...'` or `"<prefix>..."`
    //      appearing AFTER a Hive box reference within ~10 lines.
    // Edge case: prefixes that are full single keys (e.g. "is_pro",
    // "profile", "onboarding_completed", "streaks", "coaching_notes",
    // "saved_diet_plan", "water_target_override_ml") use exact-match,
    // not prefix-match, in the detector.
    final escaped = RegExp.escape(prefix);
    final isExactKey = !prefix.endsWith('_') && !prefix.endsWith('-');

    // Build the set of strict "Hive-read context" detectors. A reader is
    // a file that contains AT LEAST ONE of:
    //   (a) `.get('<key>')` / `.get("<key>")` / `.containsKey('<key>')`
    //   (b) `.put('<key>'` / `.delete('<key>')`  (writers/eraser of the key are still readers in the manifest sense — they touch the prefix)
    //   (c) `.startsWith('<prefix>')` or `.startsWith("<prefix>")`
    //   (d) Map subscript `['<key>']` ONLY when the file ALSO contains
    //       a Hive box reference. This is the weakest signal; many Map
    //       reads share the same literal but aren't Hive accesses.
    //
    // The key-literal form is either exact ("is_pro") or
    // prefix-with-suffix-chars ("exlog_<hex>"); we DO NOT match an
    // unbounded substring inside a longer identifier
    // (`weight_kg` should NOT match prefix `weight_`).
    final suffix = isExactKey ? '' : '[A-Za-z0-9_\\-:]*';
    final literal = "['\"]$escaped$suffix['\"]";

    // Strict detectors — Hive-key read contexts ONLY. We intentionally
    // do NOT match bare subscript form `['<prefix>...']` because it
    // overwhelmingly false-positives on Map field reads (e.g.,
    // `row['weight_kg']` for prefix `weight_`). Field-name contracts
    // are enforced by a separate test class (Hive field-name contracts
    // per docs/architecture/sync.md).
    final getCtxRe = RegExp(
        r'\.(get|containsKey|delete|put)\s*\(\s*' + literal);
    final startsWithRe =
        RegExp(r'\.startsWith\s*\(\s*' + literal + r'\s*\)');

    for (final f in fileSources.entries) {
      final src = f.value;
      String? matchedLine;
      int matchedLineNo = -1;

      for (final re in [getCtxRe, startsWithRe]) {
        final m = re.firstMatch(src);
        if (m != null) {
          matchedLineNo = _lineNumberFor(src, m.start);
          matchedLine = _lineAt(src, m.start);
          break;
        }
      }
      if (matchedLine == null) continue;

      final rel = fileRelPaths[f.key]!;
      if (declared.contains(rel)) continue;

      failures++;
      String snippet = matchedLine.trim();
      if (snippet.length > 160) snippet = '${snippet.substring(0, 160)}…';
      stderr.writeln(
          'FAIL reader-manifest-incomplete · concept=${c.name} · prefix=$prefix');
      stderr.writeln('  - $rel:$matchedLineNo  ($snippet)');
      stderr.writeln(
          '  fix: add to `readers:` or `reader_allow_files:` of `${c.name}` in docs/sot_registry.yaml');
    }
  }

  stdout.writeln(
      'check_reader_manifest_complete: phase-1 scanned ${fileSources.length} files '
      'against ${patternEntries.length} forbidden patterns; '
      'phase-2 enforced $conceptsChecked manifest-complete concepts.');
  if (failures > 0) {
    stderr.writeln(
        'Reader manifest check FAILED with $failures violation(s).');
    exit(1);
  }
  stdout.writeln('OK: reader manifest check passed.');
  exit(0);
}

// ---------------------------------------------------------------------------
// Phase 1 — forbidden_legacy_patterns extraction.
// ---------------------------------------------------------------------------

class _PatternEntry {
  final String pattern;
  final String reason;
  final List<String> allowFiles;
  _PatternEntry(this.pattern, this.reason, this.allowFiles);
}

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
      if (RegExp(r'^\s{6}-\s*\{').hasMatch(line)) {
        final pat = _readQuoted(line, 'pattern:');
        final rsn = _readQuoted(line, 'reason:');
        final allowRaw = _readQuoted(line, 'allow_files:');
        final allow = allowRaw == null
            ? const <String>[]
            : allowRaw
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
        if (pat != null) result.add(_PatternEntry(pat, rsn ?? '', allow));
        continue;
      }
      if (RegExp(r'^\s{0,4}\S').hasMatch(line)) {
        inBlock = false;
      }
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Phase 2 — concept manifest extraction.
// ---------------------------------------------------------------------------

class _Concept {
  final String name;
  bool readerManifestComplete = false;
  String? keyPrefix;
  final Set<String> readers = <String>{};
  final Set<String> writers = <String>{};
  final Set<String> readerAllowFiles = <String>{};
  _Concept(this.name);
}

/// Walks the YAML line-by-line. Concepts start with `  - concept: <name>`
/// at 2-space indent under the top-level `concepts:` array. Within each
/// concept, we look for:
///   - `reader_manifest_complete: true`
///   - `hive:` block followed by `key_prefix:` at +2 indent
///   - `writers:` / `readers:` lists with `file:` entries
///   - `reader_allow_files:` list with either inline `- path/to/file`
///     or `- { file: path/to/file }` entries
///
/// Concept boundary: next `  - concept:` line OR end-of-file.
List<_Concept> _extractConcepts(String yaml) {
  final out = <_Concept>[];
  final lines = yaml.split('\n');
  _Concept? cur;
  // Sub-block tracker: 'writers' | 'readers' | 'reader_allow_files' | 'hive'
  //                     | null (no active sub-block)
  String? sub;

  void closeCurrent() {
    if (cur != null) out.add(cur!);
    cur = null;
    sub = null;
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    // Skip pure-comment lines for sub-block parsing (but keep concept
    // boundary detection).
    final trimmed = line.trim();
    if (trimmed.startsWith('#')) continue;

    // Concept boundary.
    final conceptMatch =
        RegExp(r'^\s{2}-\s+concept:\s*(\S+)').firstMatch(line);
    if (conceptMatch != null) {
      closeCurrent();
      cur = _Concept(conceptMatch.group(1)!);
      sub = null;
      continue;
    }
    if (cur == null) continue;

    // reader_manifest_complete at concept root (4 spaces).
    if (RegExp(r'^\s{4}reader_manifest_complete:\s*true\s*$').hasMatch(line)) {
      cur!.readerManifestComplete = true;
      continue;
    }

    // Sub-block headers at 4-space indent.
    if (RegExp(r'^\s{4}writers:\s*$').hasMatch(line)) {
      sub = 'writers';
      continue;
    }
    if (RegExp(r'^\s{4}readers:\s*$').hasMatch(line)) {
      sub = 'readers';
      continue;
    }
    if (RegExp(r'^\s{4}reader_allow_files:\s*$').hasMatch(line)) {
      sub = 'reader_allow_files';
      continue;
    }
    if (RegExp(r'^\s{4}hive:\s*$').hasMatch(line)) {
      sub = 'hive';
      continue;
    }

    // Inside a sub-block — keys at 6-space indent indicate list items
    // or kv pairs.
    if (sub == 'hive') {
      // `      key_prefix: "..."` at 6-space indent.
      final kp = _readQuoted(line, 'key_prefix:');
      if (kp != null) {
        cur!.keyPrefix = kp;
        continue;
      }
      // A 4-space indented line that isn't blank breaks `hive` block.
      if (RegExp(r'^\s{4}\S').hasMatch(line) &&
          !RegExp(r'^\s{6,}').hasMatch(line)) {
        sub = null;
      }
      continue;
    }

    if (sub == 'writers' || sub == 'readers') {
      // List items like `      - file: lib/foo.dart`
      final m = RegExp(r'^\s{6}-\s+file:\s*(\S+)').firstMatch(line);
      if (m != null) {
        final path = m.group(1)!.replaceAll(',', '').trim();
        if (sub == 'writers') {
          cur!.writers.add(path);
        } else {
          cur!.readers.add(path);
        }
        continue;
      }
      // Break sub when a sibling key shows up at 4-space indent.
      if (RegExp(r'^\s{4}\S').hasMatch(line)) {
        sub = null;
      }
      continue;
    }

    if (sub == 'reader_allow_files') {
      // Two accepted forms:
      //   `      - lib/path/to/file.dart`
      //   `      - { file: lib/path/to/file.dart, reason: ... }`
      var m = RegExp(r'^\s{6}-\s+\{\s*file:\s*([^\s,}]+)').firstMatch(line);
      if (m != null) {
        cur!.readerAllowFiles.add(m.group(1)!.trim());
        continue;
      }
      m = RegExp(r"^\s{6}-\s+([^\s#].*?)\s*(#.*)?$").firstMatch(line);
      if (m != null) {
        final raw = m.group(1)!.trim();
        // Strip surrounding quotes if present.
        var path = raw;
        if ((path.startsWith('"') && path.endsWith('"')) ||
            (path.startsWith("'") && path.endsWith("'"))) {
          path = path.substring(1, path.length - 1);
        }
        if (path.isNotEmpty) cur!.readerAllowFiles.add(path);
        continue;
      }
      if (RegExp(r'^\s{4}\S').hasMatch(line)) {
        sub = null;
      }
    }
  }
  closeCurrent();
  return out;
}

// ---------------------------------------------------------------------------
// Shared helpers.
// ---------------------------------------------------------------------------

int _lineNumberFor(String src, int offset) {
  var n = 1;
  for (var i = 0; i < offset && i < src.length; i++) {
    if (src[i] == '\n') n++;
  }
  return n;
}

String _lineAt(String src, int offset) {
  var start = offset;
  while (start > 0 && src[start - 1] != '\n') start--;
  var end = offset;
  while (end < src.length && src[end] != '\n') end++;
  return src.substring(start, end);
}

String _stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '*') {
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
