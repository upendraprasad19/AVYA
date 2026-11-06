// scripts/gate_source_literal_brittleness_lib.dart
//
// Pure detection logic for check_gate_source_literal_whitespace_brittleness.dart.
//
// WHY (feedback_mistake_guard_without_its_mirror.md instances #7/#8,
// 2026-08-11): a gate's detection logic matched a literal string
// `'flutter analyze'` (exact substring) against captured shell-command /
// source text, and was trivially defeated by `'flutter  analyze'` — one
// extra space. A whitespace-tolerant `RegExp` (`flutter\s+analyze`) would
// not have this blind spot.
//
// SCOPE, deliberately narrow: only `scripts/check_*.dart` and
// `scripts/*_lib.dart` — gate-authoring code, where the compared text is
// untrusted external source/shell/command content by construction. A
// multi-word literal comparison anywhere else in the repo is usually just
// an ordinary string constant, not this specific brittleness risk.
//
// WARN-ONLY BY DESIGN: whether a given multi-word literal comparison is
// actually matching untrusted variable-whitespace text (vs. a harmless
// constant) is a judgment call this pure-text scan cannot make reliably.
// False positives here have real cost, so the caller (check_*.dart) never
// hard-fails on this gate's findings — see CLAUDE.md's own tier for this
// class of check (WARN-only, unlike the zero-legitimate-exception Tier-1
// gates in the same batch).

/// One flagged comparison: file, line content, and the literal found.
class BrittleLiteralHit {
  final String file;
  final String literal;
  final String lineText;
  const BrittleLiteralHit({
    required this.file,
    required this.literal,
    required this.lineText,
  });

  @override
  String toString() =>
      '$file:  literal "$literal" compared with exact whitespace — '
      'consider RegExp(r"...\\s+...") instead.  →  ${lineText.trim()}';
}

bool _inScope(String file) {
  if (file.startsWith('scripts/check_') && file.endsWith('.dart')) return true;
  if (file.startsWith('scripts/') && file.endsWith('_lib.dart')) return true;
  return false;
}

// Matches `.contains('...')` / `.contains("...")` and `== '...'` / `== "..."`
// with a NON-GREEDY body that stops at the first matching quote — good
// enough for the plain string literals gate source actually writes (no
// escaped quotes inside these comparison literals in this codebase).
final RegExp _containsCall = RegExp(r'''\.contains\((['"])(.*?)\1\)''');
final RegExp _eqCompare = RegExp(r'''==\s*(['"])(.*?)\1''');

bool _isMultiWord(String literal) {
  final tokens = literal.trim().split(RegExp(r'\s+'));
  return tokens.length >= 2 && tokens.every((t) => t.isNotEmpty);
}

List<BrittleLiteralHit> _scanLine(String file, String addedLine) {
  // Already regex-based on this line — treated as the safe form regardless
  // of content, per spec. A line mixing a safe RegExp use with an unrelated
  // unsafe literal comparison is not attempted here (out of scope for a
  // WARN-only advisory; false-negative risk accepted).
  if (addedLine.contains('RegExp(')) return const [];

  final hits = <BrittleLiteralHit>[];
  for (final m in _containsCall.allMatches(addedLine)) {
    final literal = m.group(2)!;
    if (_isMultiWord(literal)) {
      hits.add(BrittleLiteralHit(file: file, literal: literal, lineText: addedLine));
    }
  }
  for (final m in _eqCompare.allMatches(addedLine)) {
    final literal = m.group(2)!;
    if (_isMultiWord(literal)) {
      hits.add(BrittleLiteralHit(file: file, literal: literal, lineText: addedLine));
    }
  }
  return hits;
}

/// Parse a `git diff --cached --unified=0 --no-color -- 'scripts/check_*.dart'
/// 'scripts/*_lib.dart'` output and return every brittle literal comparison
/// found on an ADDED line, scoped to gate-authoring files.
List<BrittleLiteralHit> findBrittleLiteralComparisons(String diffText) {
  final hits = <BrittleLiteralHit>[];
  var currentFile = '';
  var inScope = false;
  for (final rawLine in diffText.split('\n')) {
    if (rawLine.startsWith('+++ b/')) {
      currentFile = rawLine.substring('+++ b/'.length).trim();
      inScope = _inScope(currentFile);
      continue;
    }
    if (!inScope) continue;
    if (!rawLine.startsWith('+') || rawLine.startsWith('+++')) continue;
    final added = rawLine.substring(1);
    hits.addAll(_scanLine(currentFile, added));
  }
  return hits;
}
