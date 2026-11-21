// scripts/check_snapshot_contract.dart
//
// OI-03 gate — enforces the snapshot contract in docs/snapshot_contract.yaml.
//
// Two checks:
//
//   1. Writer-emit verification: every `key` listed in the contract's
//      `keys:` array MUST appear in `buildAiContext` (or its helper-
//      returned maps spread into the snapshot). Catches a key being
//      silently removed from the writer.
//
//   2. Reader-read verification: every `readers:` entry citing
//      `{fn, file, line}` MUST actually contain a snapshot field read
//      for that key at or near the cited line (±15 lines of slack).
//      Catches a key listed as consumed when the reader stopped using
//      it (which would silently break the contract on the next
//      writer-side rename).
//
// Phase 3 (deferred, NOT in this script): catch a NEW reader added to
// an Edge Function that references a key NOT in the contract. Requires
// parsing Edge Function source for `snapshot.<key>` / `snapshot['<key>']`
// access patterns. Will be added when at least one such drift surfaces.
//
// Exit codes:
//   0 — pass
//   1 — at least one writer-emit or reader-read violation
//   2 — manifest parse error
//
// closes-diagnose: 2026-05-17-oi-03-snapshot-contract-gate-<hex>

import 'dart:io';

void main(List<String> args) async {
  final repoRoot = Directory.current.path;
  final contractPath = '$repoRoot/docs/snapshot_contract.yaml';
  final contract = File(contractPath);
  if (!contract.existsSync()) {
    stderr.writeln('Snapshot contract not found at $contractPath');
    exit(2);
  }
  final yaml = contract.readAsStringSync();
  final keys = _extractKeys(yaml);
  if (keys.isEmpty) {
    stderr.writeln(
        'No keys parsed from snapshot_contract.yaml — schema drift?');
    exit(2);
  }

  // Writer source
  final writerPath =
      'lib/features/ai_coach/repositories/ai_coach_repository.dart';
  final writerFile = File('$repoRoot/$writerPath');
  if (!writerFile.existsSync()) {
    stderr.writeln('Writer file not found at $writerPath');
    exit(2);
  }
  final writerSrc = _stripComments(writerFile.readAsStringSync());

  var failures = 0;

  // Phase 1 — every key must appear in the writer source as
  // `'<key>':` (the YAML-emission pattern).
  for (final k in keys) {
    // `extra_server_written_keys:` entries are read by servers but NOT emitted
    // by buildAiContext — that is what the block means, so a writer-emit check
    // would fail by construction. Phase 2 still validates their citations.
    if (k.extraServerWritten) continue;
    final name = k.name;
    // Allow nested keys like `daily_targets.protein` — only check the
    // top-level segment.
    final topLevel = name.contains('.') ? name.split('.').first : name;
    final emitRe = RegExp("'$topLevel'\\s*:");
    if (!emitRe.hasMatch(writerSrc)) {
      failures++;
      stderr.writeln(
          'FAIL writer-emit · key="$name" not emitted by buildAiContext');
      stderr.writeln(
          '  expected pattern: "\'$topLevel\':" in $writerPath');
      stderr.writeln(
          "  fix: emit the key in buildAiContext OR remove it from "
          'snapshot_contract.yaml.');
    }
  }

  // Phase 2 — every reader citation must contain a reference to the
  // key within ±15 lines of the cited line.
  for (final k in keys) {
    for (final r in k.readers) {
      final readerFile = File('$repoRoot/${r.file}');
      if (!readerFile.existsSync()) {
        failures++;
        stderr.writeln(
            'FAIL reader-file · key="${k.name}" reader file ${r.file} does not exist');
        continue;
      }
      final readerLines = readerFile.readAsLinesSync();
      // Build a probe — match `snap.<key>` or `snapshot.<key>` or
      // `snap['<key>']` or `snapshot['<key>']` or `snap_json.<key>`.
      // Tolerant — many cron functions use varied aliases for the
      // root.
      final topLevel = k.name.contains('.') ? k.name.split('.').first : k.name;
      // Two alternatives:
      //   (a) rooted   — `snap`/`snapshot`/`snapshot_json` then the key.
      //   (b) unrooted — the key as a property access or string index,
      //                  whatever precedes it.
      //
      // (b) added 2026-07-26. The rooted form alone produced FALSE NEGATIVES on
      // the two idioms this codebase actually uses:
      //   `snapshot?.snapshot_json?.notification_preferences`   ← optional chain
      //   `(snapshot as Record<string, unknown>)?.notif…`       ← cast in between
      // Both put tokens between the root and the key, so the rooted probe
      // missed them and the gate would have demanded "fixes" to citations that
      // were already correct. Requiring a property access still means a bare
      // mention in prose cannot satisfy the check.
      final probe = RegExp(
          "(snap|snapshot)(_?json)?\\s*\\??\\s*(\\.${topLevel}\\b|\\[\\s*['\"]${topLevel}['\"]\\s*\\])"
          "|[.\\[]\\s*['\"]?${topLevel}\\b");
      final start = (r.line - 15).clamp(1, readerLines.length);
      final end = (r.line + 15).clamp(1, readerLines.length);
      var matched = false;
      for (var i = start - 1; i < end; i++) {
        if (i < 0 || i >= readerLines.length) continue;
        if (probe.hasMatch(readerLines[i])) {
          matched = true;
          break;
        }
      }
      if (!matched) {
        failures++;
        stderr.writeln(
            'FAIL reader-read · key="${k.name}" not found in ${r.file} near line ${r.line}');
        stderr.writeln(
            '  expected pattern: snap.<key> or snapshot.<key> or '
            "snap['<key>'] within ±15 lines");
        stderr.writeln(
            '  fix: confirm reader still reads this key, OR remove '
            'this reader entry from the contract.');
      }
    }
  }

  stdout.writeln(
      'check_snapshot_contract: ${keys.length} keys checked, '
      '${keys.fold<int>(0, (s, k) => s + k.readers.length)} reader citations checked.');
  if (failures > 0) {
    stderr.writeln('Snapshot contract check FAILED with $failures violation(s).');
    exit(1);
  }
  stdout.writeln('OK: snapshot contract check passed.');
  exit(0);
}

class _Key {
  final String name;
  final List<_Reader> readers;

  /// True for entries under `extra_server_written_keys:` — keys that servers
  /// READ but `buildAiContext` does not emit.
  ///
  /// Added 2026-07-26. That whole block was previously invisible to this gate:
  /// the parser stopped at the first column-0 key after `keys:`, so its reader
  /// citations were never checked and drifted 1-42 lines undetected — which is
  /// exactly how `notification_preferences` sat as a documented orphan while
  /// nothing verified its six citations.
  ///
  /// These keys are exempt from Phase 1 (writer-emit) BY DEFINITION — "no
  /// writer emits this" is the fact the block records. Phase 2 (reader-citation
  /// accuracy) applies to them in full, and is the check that was missing.
  final bool extraServerWritten;

  _Key(this.name, this.readers, {this.extraServerWritten = false});
}

class _Reader {
  final String fn;
  final String file;
  final int line;
  _Reader(this.fn, this.file, this.line);
}

/// Lightweight extraction. Looks for blocks under `keys:` in the YAML:
///   - key: <name>
///     ...
///     readers:
///       - { fn: <fn>, file: <path>, line: <int> }
List<_Key> _extractKeys(String yaml) {
  // 2026-05-17 fix: strip `\r` after split so regex `.+$` matches
  // correctly on CRLF-terminated files. Pre-fix the gate exited 2
  // ("No keys parsed") on any clone with CRLF line endings (Windows
  // default + Git autocrlf on checkout).
  final lines = yaml.split('\n').map((l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l).toList();
  // Find start of `keys:` block (top-level, not nested in orphan_readers).
  var inKeys = false;
  var inReaders = false;
  // Which block we are inside, so entries can be tagged. See _Key.extraServerWritten.
  var inExtraBlock = false;
  String? currentKey;
  final result = <_Key>[];
  var currentReaders = <_Reader>[];

  void flush() {
    if (currentKey != null) {
      result.add(_Key(currentKey!, List.of(currentReaders),
          extraServerWritten: inExtraBlock));
      currentKey = null;
      currentReaders = <_Reader>[];
    }
  }

  for (final raw in lines) {
    final line = raw;
    if (line.startsWith('keys:')) {
      flush();
      inKeys = true;
      inExtraBlock = false;
      continue;
    }
    // 2026-07-26: this block used to terminate parsing entirely, leaving its
    // reader citations unvalidated (they had drifted 1-42 lines). Same entry
    // shape as `keys:`, so parse it identically and tag the entries.
    if (line.startsWith('extra_server_written_keys:')) {
      flush();
      inKeys = true;
      inExtraBlock = true;
      continue;
    }
    if (!inKeys) continue;
    // Leave the current section when we hit any other top-level key.
    if (RegExp(r'^[a-z_]+:').hasMatch(line)) {
      flush();
      inKeys = false;
      inExtraBlock = false;
      continue;
    }
    final keyMatch = RegExp(r'^\s+- key:\s*(.+)$').firstMatch(line);
    if (keyMatch != null) {
      flush();
      currentKey = keyMatch.group(1)!.trim();
      inReaders = false;
      continue;
    }
    if (RegExp(r'^\s+readers:\s*\[\s*\]\s*$').hasMatch(line)) {
      inReaders = false;
      continue;
    }
    if (RegExp(r'^\s+readers:\s*$').hasMatch(line)) {
      inReaders = true;
      continue;
    }
    if (inReaders) {
      final readerMatch = RegExp(
              r"^\s+-\s*\{\s*fn:\s*([\w-]+),\s*file:\s*([^,]+),\s*line:\s*(\d+)\s*\}")
          .firstMatch(line);
      if (readerMatch != null) {
        currentReaders.add(_Reader(
          readerMatch.group(1)!.trim(),
          readerMatch.group(2)!.trim(),
          int.parse(readerMatch.group(3)!.trim()),
        ));
        continue;
      }
      // Leave readers list when next non-list-item line at <= reader
      // indent.
      if (RegExp(r'^\s{4}\w').hasMatch(line) &&
          !RegExp(r'^\s+-').hasMatch(line)) {
        inReaders = false;
      }
    }
  }
  flush();
  return result;
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
