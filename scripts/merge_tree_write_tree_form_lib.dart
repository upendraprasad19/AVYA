// scripts/merge_tree_write_tree_form_lib.dart
//
// Pure detection logic for check_merge_tree_write_tree_form.dart. See that
// file's header for the bug class this exists to catch.

/// One flagged staged-added line.
class MergeTreeViolation {
  final String file;
  final String line;
  const MergeTreeViolation(this.file, this.line);

  @override
  String toString() => '$file:  ${line.trim()}';
}

final _mergeTreeToken = RegExp(r'git merge-tree\b');

/// Scans `git diff --cached --unified=0 --no-color` output for STAGED ADDED
/// lines that invoke the legacy 3-arg `git merge-tree <base> <a> <b>` form
/// without `--write-tree`. That legacy form NEVER emits `<<<<<<<` conflict
/// markers, so grepping its output for conflicts always reports zero --
/// silently wrong, not merely uninformative (2026-08-10 instance: a session
/// reported "will auto-merge cleanly" from this; the real answer, via
/// `--write-tree`, was 3 real conflicts).
List<MergeTreeViolation> findLegacyMergeTreeInvocations(String diffText) {
  final violations = <MergeTreeViolation>[];
  var currentFile = '';
  for (final rawLine in diffText.split('\n')) {
    if (rawLine.startsWith('+++ b/')) {
      currentFile = rawLine.substring('+++ b/'.length).trim();
      continue;
    }
    if (!rawLine.startsWith('+') || rawLine.startsWith('+++')) continue;
    final added = rawLine.substring(1);
    if (_isLegacyInvocation(added)) {
      violations.add(MergeTreeViolation(currentFile, added));
    }
  }
  return violations;
}

/// Real invocations pass at least two non-flag tokens after `merge-tree`
/// (the base/a/b refs). Prose that merely NAMES the command -- typically a
/// short inline-code span like `` `git merge-tree` `` with nothing but the
/// closing backtick right after -- must not be flagged, so scope the token
/// count to the same inline-code span (up to the next backtick) rather than
/// the rest of the line. A plain-text (non-markdown) invocation has no
/// backtick to stop at, so the whole rest of the line is used.
bool _isLegacyInvocation(String line) {
  for (final m in _mergeTreeToken.allMatches(line)) {
    final rest = line.substring(m.end);
    final backtickIdx = rest.indexOf('`');
    final scope = backtickIdx == -1 ? rest : rest.substring(0, backtickIdx);
    if (scope.contains('--write-tree')) continue;
    final beforePipe = scope.split('|').first;
    final tokens = beforePipe
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && !t.startsWith('-'))
        .toList();
    if (tokens.length >= 2) return true;
  }
  return false;
}
