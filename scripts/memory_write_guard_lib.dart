// scripts/memory_write_guard_lib.dart
//
// Pure validation logic behind the memory write-guard PreToolUse hook
// (scripts/memory_write_guard_hook.dart). Adopted from ICANBEFITTER's
// claude-memory-write-guard.mjs (discipline-v3 Phase 3, 2026-09-23).
//
// Validates the STRUCTURE of a memory file about to be written -- frontmatter
// shape for a topic file, line-byte-cap + hard-cap for the MEMORY.md index
// itself -- so a malformed write doesn't silently corrupt what every future
// session loads. WARN-ONLY BY DESIGN: the hook wrapper never blocks a save on
// this. A validation bug here must never wedge a legitimate memory write --
// see memory_write_guard_hook.dart's fail-open contract.
//
// Byte counts use utf8.encode(...).length throughout, never String.length --
// Dart strings are UTF-16 code-unit counted, and the founder's global
// CLAUDE.md caps (600B/line, 18,000B soft, 24,400B hard) are BYTE counts.

import 'dart:convert';

/// True when [path] looks like it targets a memory directory (harness-level
/// `~/.claude/projects/<mangled>/memory/*.md` OR project-local `memory/*.md`)
/// -- the guard only applies to these, never to an arbitrary `.md` file.
bool isMemoryFilePath(String path) {
  final norm = path.replaceAll('\\', '/');
  if (!norm.endsWith('.md')) return false;
  return norm.contains('/memory/') || norm.startsWith('memory/');
}

/// True when [path] is the index file itself, which has a byte-cap rule
/// distinct from a topic file's frontmatter rule. Deliberately excludes
/// MEMORY_ARCHIVED.md -- that file is an append-only archive, not the loaded
/// index, and does not carry the same per-line pointer-cap contract.
bool isMemoryIndexPath(String path) {
  final norm = path.replaceAll('\\', '/');
  return norm == 'MEMORY.md' || norm.endsWith('/MEMORY.md');
}

/// One issue found in a memory file write.
class MemoryValidationIssue {
  final String message;
  const MemoryValidationIssue(this.message);
  @override
  String toString() => message;
  @override
  bool operator ==(Object other) =>
      other is MemoryValidationIssue && other.message == message;
  @override
  int get hashCode => message.hashCode;
}

int _utf8Len(String s) => utf8.encode(s).length;

/// Validates a TOPIC memory file's content (anything under memory/ that is
/// NOT MEMORY.md/MEMORY_ARCHIVED.md): must open with a `---` frontmatter
/// block that declares `name:`, `description:`, and a `type:` field (bare or
/// nested under `metadata:`, both forms are live in this repo's memory dir).
List<MemoryValidationIssue> validateTopicFile(String content) {
  final issues = <MemoryValidationIssue>[];
  final lines = content.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') {
    issues.add(const MemoryValidationIssue(
        'missing opening `---` frontmatter delimiter as the first line'));
    return issues; // nothing else is checkable without a frontmatter block
  }
  final closeIdx = lines.indexWhere((l) => l.trim() == '---', 1);
  if (closeIdx == -1) {
    issues.add(const MemoryValidationIssue(
        'frontmatter opened with `---` but never closed with a second `---`'));
    return issues;
  }
  final frontmatter = lines.sublist(1, closeIdx).join('\n');
  if (!RegExp(r'^name:\s*\S+', multiLine: true).hasMatch(frontmatter)) {
    issues.add(const MemoryValidationIssue('frontmatter missing `name:` field'));
  }
  if (!RegExp(r'^description:\s*\S+', multiLine: true).hasMatch(frontmatter)) {
    issues.add(
        const MemoryValidationIssue('frontmatter missing `description:` field'));
  }
  final hasBareType = RegExp(r'^type:\s*\S+', multiLine: true).hasMatch(frontmatter);
  final hasNestedType =
      RegExp(r'^\s+type:\s*\S+', multiLine: true).hasMatch(frontmatter);
  if (!hasBareType && !hasNestedType) {
    issues.add(const MemoryValidationIssue(
        'frontmatter missing `type:` field (bare or nested under `metadata:`)'));
  }
  return issues;
}

/// Validates MEMORY.md itself: every non-blank, non-heading, non-blockquote
/// line must stay under the 600-byte pointer cap (founder's global CLAUDE.md
/// memory-hygiene rule: "A new index line is a POINTER, max 600 bytes"), and
/// the whole file must stay under the hard byte cap. The soft cap is a
/// SessionStart NUDGE (scripts/discipline_hook.dart), not a write-time
/// concern, so it is deliberately NOT re-checked here -- duplicating it would
/// just be two places able to disagree about the same threshold.
List<MemoryValidationIssue> validateIndexFile(
  String content, {
  int hardCapBytes = 24400,
  int maxLineBytes = 600,
}) {
  final issues = <MemoryValidationIssue>[];
  final totalBytes = _utf8Len(content);
  if (totalBytes > hardCapBytes) {
    issues.add(MemoryValidationIssue(
        'MEMORY.md would be $totalBytes bytes, over the hard cap of $hardCapBytes B '
        '-- it will be TRUNCATED on load. Run /consolidate-memory.'));
  }
  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('#')) continue; // headings are not pointer lines
    if (trimmed.startsWith('>')) continue; // blockquote notes are not pointer lines
    final lineBytes = _utf8Len(line);
    if (lineBytes > maxLineBytes) {
      final preview = line.length > 60 ? '${line.substring(0, 60)}...' : line;
      issues.add(MemoryValidationIssue(
          'line ${i + 1} is ${lineBytes}B, over the ${maxLineBytes}B pointer cap: "$preview"'));
    }
  }
  return issues;
}

/// Dispatches to the right validator based on the path shape. Returns an
/// empty list (no issues) for a path the guard does not recognise as a
/// memory file at all -- callers should already have filtered with
/// [isMemoryFilePath] before calling, but this stays safe either way.
List<MemoryValidationIssue> validateMemoryWrite(String path, String content) {
  if (!isMemoryFilePath(path)) return const [];
  if (isMemoryIndexPath(path)) return validateIndexFile(content);
  return validateTopicFile(content);
}
