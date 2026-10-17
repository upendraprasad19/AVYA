// scripts/teardown_sibling_await_lib.dart
//
// Pure decision logic for scripts/check_teardown_no_unguarded_sibling_await.dart.
// Kept separate + I/O-free (git-free, disk-free) so every branch is testable
// deterministically against literal Dart source strings — same split as
// worktree_config_integrity_lib.dart.
//
// WHY THIS EXISTS (feedback_mistake_guard_without_its_mirror.md, instance #27,
// 2026-09-10): a tearDown block wrapped ONE cleanup call in
// `try { await x.delete(); } catch (_) {}` and left a SIBLING cleanup call in
// the SAME block as a bare, unguarded `await y.signOut();` two lines below.
// The guard protected one call and not its neighbour in the identical block —
// classic guard-without-its-mirror. CLAUDE.md's own `@Timeout`/full-suite
// pitfalls row independently names the same class: "a failing teardown can
// mask the failure it follows... make it never throw."
//
// SCOPE, deliberately narrow: only tearDown/tearDownAll blocks that contain
// BOTH a guarded await (inside a try{...}catch(...)) AND a bare await outside
// every guard span in that same block. A block with ZERO guards at all is a
// different, wider problem this gate does NOT claim to cover -- flagging it
// would conflate "nothing is guarded" (a design choice some teardowns
// legitimately make) with "guarding is inconsistent within one block" (a
// mirror defect). Only the second is this gate's job.
//
// Detection is deliberately a brace-counting scan, not a full Dart parser --
// this repo's convention (see check_no_deferral_euphemism.dart, a line-level
// text scan) already accepts that tradeoff for gates whose false-positive
// surface is small. A block containing string literals with unbalanced braces
// (rare in test source) could defeat the brace counter; not handled here.
//
// COMMENTS ARE BLANKED BEFORE ANY SCAN (diagnose d3e8a1, 2026-09-20 --
// feedback_source_grep_strip_comments_first.md EXCEPTION 2, third instance of
// this exact class in this repo). This gate scans the RAW `await` keyword
// with no comment-awareness, so a tearDown block's own explanatory comment
// discussing a PAST bare-await bug -- prose that necessarily contains the
// word "await" -- was misread as a second, unguarded await sibling.
// `test/edge_functions/ai_proxy_test.dart`'s `tearDownAll` has exactly this
// shape: a single guarded `await client.auth.signOut();` preceded by a
// multi-line comment recounting the 2026-09-10 incident that made this
// exact call need guarding in the first place, and the comment's own prose
// ("A bare await here turned a fully-passing file RED") tripped the gate
// that exists to prevent a REGRESSION of it. `_blankComments` replaces every
// `//` and `/* */` comment's characters with spaces (newlines preserved), so
// every absolute index and line number computed downstream is unaffected --
// the scan is simply blind to comment content, for BOTH the await keyword
// and (as a side effect) any brace a comment might contain.

/// One flagged tearDown/tearDownAll block.
class TeardownFinding {
  final String file;
  final int teardownLine;
  final int bareAwaitLine;

  const TeardownFinding(this.file, this.teardownLine, this.bareAwaitLine);

  String describe() =>
      '$file:$teardownLine — tearDown/tearDownAll block has a try/catch-guarded '
      'await AND an unguarded sibling await at line $bareAwaitLine. A throwing '
      'bare await can mask the guarded cleanup and the real test failure '
      'underneath it (feedback_mistake_guard_without_its_mirror.md #27).';
}

int _lineOf(String s, int index) =>
    '\n'.allMatches(s.substring(0, index)).length + 1;

/// [source] with every `//`-to-end-of-line and `/* ... */` comment's
/// characters replaced by spaces (newlines preserved). Length and every
/// newline position are IDENTICAL to [source], so an index or line number
/// computed from the result is valid against the original text too --
/// blanking, not stripping, is load-bearing here.
String _blankComments(String source) {
  var out = source.replaceAllMapped(
    RegExp(r'/\*[\s\S]*?\*/'),
    (m) => m.group(0)!.replaceAll(RegExp(r'[^\n]'), ' '),
  );
  return out.replaceAllMapped(
    RegExp(r'//[^\n]*'),
    (m) => ' ' * m.group(0)!.length,
  );
}

/// Index of the '{' at [openIndex]'s matching '}', or -1 if unbalanced.
int _matchBrace(String s, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < s.length; i++) {
    if (s[i] == '{') depth++;
    if (s[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// Every tearDown(...)/tearDownAll(...) callback body, as a [start, end]
/// index span (inclusive of the enclosing braces) into [source].
List<({int start, int end})> _blockBodies(String source, RegExp keyword) {
  final spans = <({int start, int end})>[];
  for (final m in keyword.allMatches(source)) {
    final braceIdx = source.indexOf('{', m.end);
    if (braceIdx == -1) continue;
    final closeIdx = _matchBrace(source, braceIdx);
    if (closeIdx == -1) continue;
    spans.add((start: braceIdx, end: closeIdx));
  }
  return spans;
}

/// Every `try { ... } catch (...)` span WITHIN [block] (indices relative to
/// [block], not the outer source). A `try { ... } finally { ... }` with no
/// `catch` does NOT count as guarded -- it can still rethrow.
List<({int start, int end})> _tryCatchSpans(String block) {
  final spans = <({int start, int end})>[];
  final tryRe = RegExp(r'\btry\b');
  for (final m in tryRe.allMatches(block)) {
    final braceIdx = block.indexOf('{', m.end);
    if (braceIdx == -1) continue;
    final closeIdx = _matchBrace(block, braceIdx);
    if (closeIdx == -1) continue;
    var i = closeIdx + 1;
    while (i < block.length && block[i].trim().isEmpty) {
      i++;
    }
    if (block.startsWith('catch', i)) {
      spans.add((start: braceIdx, end: closeIdx));
    }
  }
  return spans;
}

/// Scan [sourceContent] (one Dart file's full text) for tearDown/tearDownAll
/// blocks that mix a try/catch-guarded await with an unguarded sibling await
/// in the same block. [fileLabel] is echoed into the finding for display only.
List<TeardownFinding> findUnguardedSiblingAwaits(
  String sourceContent, {
  required String fileLabel,
}) {
  final findings = <TeardownFinding>[];
  final keyword = RegExp(r'\btearDown(All)?\s*\(');
  final blanked = _blankComments(sourceContent);

  for (final span in _blockBodies(blanked, keyword)) {
    final block = blanked.substring(span.start, span.end + 1);
    final guardSpans = _tryCatchSpans(block);

    final guardedAwaitFound =
        guardSpans.any((s) => block.substring(s.start, s.end).contains('await'));
    if (!guardedAwaitFound) continue;

    final awaitRe = RegExp(r'\bawait\b');
    int? bareAwaitAbsoluteIndex;
    for (final m in awaitRe.allMatches(block)) {
      final insideGuard =
          guardSpans.any((s) => m.start >= s.start && m.start <= s.end);
      if (!insideGuard) {
        bareAwaitAbsoluteIndex = span.start + m.start;
        break;
      }
    }

    if (bareAwaitAbsoluteIndex != null) {
      findings.add(TeardownFinding(
        fileLabel,
        _lineOf(sourceContent, span.start),
        _lineOf(sourceContent, bareAwaitAbsoluteIndex),
      ));
    }
  }

  return findings;
}
