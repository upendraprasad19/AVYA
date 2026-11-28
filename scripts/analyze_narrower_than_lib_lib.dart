// scripts/analyze_narrower_than_lib_lib.dart
//
// Pure detection logic for check_analyze_narrower_than_lib_in_tooling.dart.
// No I/O — takes a unified-diff string, returns violation strings.
//
// THE CLASS: `flutter analyze <single-file-or-narrow-path>` reports CLEAN on a
// library that does not compile, because a `part of` file has no imports of
// its own and is only analysed as part of its whole library
// (feedback_green_check_input_set_width.md #29, 2026-09-02 — a B-pass finding
// scoped to one file broke a real push; CLAUDE.md §4.9 names the fix as
// "the only valid input set is `flutter analyze lib/`").
//
// SCOPE IS DELIBERATELY NARROW — TOOLING/INSTRUCTION FILES ONLY. Calibrated
// live against this repo (2026-09-19): `docs/diagnoses/*.md` files legitimately
// cite scoped `flutter analyze <touched files>` as spot-verification EVIDENCE
// in dozens of existing diagnose-docs (that citation records a fix's own
// verification step; it does not replace the unconditional full-tree
// `flutter analyze` that ADR-0018 already runs at pre-push regardless of what
// any doc claims). A repo-wide gate would flood on that legitimate, historical
// pattern. This gate's CALLER (check_analyze_narrower_than_lib_in_tooling.dart)
// therefore restricts the `git diff --cached` path filter to
// `scripts/*.sh scripts/*.dart .claude/skills/**/*.md` — the places that
// DIRECT an agent's future actions, never `docs/**`, which only RECORDS past
// evidence. Do not widen that filter without re-deriving this calibration.
library;

/// Matches `flutter analyze` followed by zero or more arguments on the same
/// line. Captures everything after the phrase up to a shell/string
/// terminator, so a trailing backtick, quote, or `&&`/`;`/`|`/`#` doesn't get
/// swept into the argument list.
final _analyzeCall = RegExp(r'flutter\s+analyze\b');

const _terminators = ['`', '"', "'", '&&', ';', '|', '#'];

/// Markers that legitimately precede a REAL `flutter analyze` invocation:
/// start of a shell command (after a backtick/quote/paren/operator), or the
/// literal start of the line. Anything else means the phrase is sitting
/// inside prose — e.g. `echo "[pre-push] flutter analyze (always -- runs...`
/// (a REAL, currently-committed line in scripts/pre-push.sh) — which must
/// NOT be read as an invocation with `(always` as its scope argument.
const _commandStartMarkers = ['`', '"', "'", '(', '&&', ';', '|', '='];

bool _looksLikeCommandStart(String line, int matchStart) {
  final prefix = line.substring(0, matchStart).trimRight();
  if (prefix.isEmpty) return true; // start of the (trimmed) added line
  return _commandStartMarkers.any((m) => prefix.endsWith(m));
}

/// True if [args] (the tokens found after `flutter analyze`) scope the run
/// narrower than the whole `lib/` tree.
///
/// - No non-flag tokens at all -> bare `flutter analyze`, whole project. Fine.
/// - A non-flag token equal to `lib/` or `lib` -> whole app tree. Fine.
/// - Any other non-flag token present -> a specific file/dir narrower than
///   `lib/`. This is the class that goes CLEAN on a broken `part of` sibling.
bool _isScopedNarrowerThanLib(List<String> args) {
  final nonFlags = args.where((a) => !a.startsWith('-')).toList();
  if (nonFlags.isEmpty) return false;
  return !nonFlags.any((a) => a == 'lib/' || a == 'lib');
}

List<String> _tokensAfter(String line, int start) {
  var end = line.length;
  for (final t in _terminators) {
    final i = line.indexOf(t, start);
    if (i != -1 && i < end) end = i;
  }
  final rest = line.substring(start, end).trim();
  if (rest.isEmpty) return const [];
  return rest.split(RegExp(r'\s+'));
}

/// Scans a `git diff --cached --unified=0 --no-color` transcript for ADDED
/// lines (already scoped by the caller's `--` pathspec to tooling/instruction
/// files) that invoke `flutter analyze` scoped narrower than `lib/`.
///
/// Returns one human-readable violation string per hit:
/// `<file>:  flutter analyze <args>`.
List<String> findScopedAnalyzeInTooling(String diffText) {
  final violations = <String>[];
  var currentFile = '';
  for (final rawLine in diffText.split('\n')) {
    if (rawLine.startsWith('+++ b/')) {
      currentFile = rawLine.substring('+++ b/'.length).trim();
      continue;
    }
    if (!rawLine.startsWith('+') || rawLine.startsWith('+++')) continue;
    final added = rawLine.substring(1);

    for (final match in _analyzeCall.allMatches(added)) {
      if (!_looksLikeCommandStart(added, match.start)) continue;
      final args = _tokensAfter(added, match.end);
      if (_isScopedNarrowerThanLib(args)) {
        violations.add(
          '$currentFile:  flutter analyze ${args.join(' ')}',
        );
      }
    }
  }
  return violations;
}
