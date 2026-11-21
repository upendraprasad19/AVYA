// scripts/no_conflict_markers_lib.dart
//
// Pure detection logic for unresolved git conflict markers in tracked files.
// The CLI entry point (check_no_conflict_markers.dart) delegates to this.
//
// WHY THIS EXISTS
//   On 2026-08-14 `docs/audit/open_issues.md` was found ON `main` carrying three
//   committed conflict markers (from the merge `5d1c6f12`). No gate anywhere in
//   the repo looked for them. The board stayed corrupt while every gate reported
//   green, because the markers are not `## OI-` headers — `build_oi_index.dart`
//   skipped them as prose and regenerated a clean-looking index over a broken
//   board. Nothing detected it for a day; a human eventually read the file.
//
// WHY THE PATTERNS ARE SYNTHESISED RATHER THAN WRITTEN AS LITERALS
//   A detector for a token cannot contain that token, or it flags its own source
//   and its own fixtures. The obvious workaround — excluding `scripts/` and
//   `test/` by path — is a BYPASS, not a fix: `test/` is precisely where merges
//   conflict, so the exclusion would blind the gate to the likeliest real case.
//   Building each pattern from a repeated character means NO literal marker
//   exists in this file or its tests, so nothing needs excluding and no hole is
//   opened. The fixtures write their markers to a temp dir at runtime for the
//   same reason.

/// The three marker tokens, built rather than spelled. See the header.
final String openMarker = '<' * 7;
final String separatorMarker = '=' * 7;
final String closeMarker = '>' * 7;

class ConflictHit {
  /// Repo-relative path.
  final String path;

  /// 1-indexed line number.
  final int line;

  /// `open` | `separator` | `close`.
  final String kind;

  const ConflictHit(this.path, this.line, this.kind);

  @override
  String toString() => '$path:$line — unresolved conflict marker ($kind)';

  @override
  bool operator ==(Object other) =>
      other is ConflictHit &&
      other.path == path &&
      other.line == line &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(path, line, kind);
}

/// Outcome of a scan.
///
/// [skipped] is carried deliberately rather than dropped: a file that could not
/// be read is NOT the same answer as a file with no markers, and collapsing the
/// two would make "0 conflicts" mean both "clean" and "could not look" — the
/// exact bad-news/no-news failure this repo has already shipped twice. The CLI
/// prints the skipped count on every run, including passing ones.
class ScanResult {
  final List<ConflictHit> conflicts;
  final List<String> skipped;

  const ScanResult(this.conflicts, this.skipped);
}

/// Scan a single file's [content]. [path] is used only for reporting.
List<ConflictHit> conflictsInFile(String path, String content) {
  final lines = content.replaceAll('\r\n', '\n').split('\n');
  final hits = <ConflictHit>[];
  final separatorLines = <int>[];
  var sawOpenOrClose = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith(openMarker)) {
      hits.add(ConflictHit(path, i + 1, 'open'));
      sawOpenOrClose = true;
    } else if (line.startsWith(closeMarker)) {
      hits.add(ConflictHit(path, i + 1, 'close'));
      sawOpenOrClose = true;
    } else if (line.trimRight() == separatorMarker) {
      separatorLines.add(i + 1);
    }
  }

  // A bare separator line counts ONLY when the same file also carries an open or
  // close marker. Standalone `=` runs are a legitimate prose divider (setext
  // headings, ASCII rules) and this repo's own docs contain them, so flagging
  // them unconditionally would buy a real class of false positives for no
  // detection at all: a conflict cannot exist without an open marker.
  if (sawOpenOrClose) {
    for (final l in separatorLines) {
      hits.add(ConflictHit(path, l, 'separator'));
    }
  }

  hits.sort((a, b) => a.line.compareTo(b.line));
  return hits;
}

/// Scan every path in [paths].
///
/// [readFile] returns the file's text, or null when it cannot be decoded as
/// text (binary, unreadable). Nulls land in [ScanResult.skipped], never silently
/// in the clean pile.
ScanResult scanPaths({
  required List<String> paths,
  required String? Function(String path) readFile,
}) {
  final conflicts = <ConflictHit>[];
  final skipped = <String>[];

  for (final path in paths) {
    final content = readFile(path);
    if (content == null) {
      skipped.add(path);
      continue;
    }
    conflicts.addAll(conflictsInFile(path, content));
  }

  return ScanResult(conflicts, skipped);
}
