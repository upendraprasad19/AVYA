// scripts/blast_radius_stdin_usage_lib.dart
//
// Pure logic for check_blast_radius_stdin_usage.dart.
//
// Bug class: feedback_mistake_blast_radius_positional_mode.md (5 recorded
// recurrences). scripts/blast_radius_from_diff.dart's contract (confirmed by
// reading it): no args -> reads `git diff --cached --name-only`; args == ['-']
// -> reads stdin; any OTHER non-empty args -> treated as explicit file paths
// (and the script itself already fails loud, exit 2, if any of THOSE resolve
// as a git commit-ish ref — that misuse is already self-gated at runtime and
// is NOT this check's job).
//
// The one ungated shape: a producer is PIPED into the invocation without the
// trailing bare `-`. The pipe's stdin is then never read (args is empty, not
// ['-']), so the script silently falls through to its own
// `git diff --cached --name-only` default -- "silently classifies the EMPTY
// staged set instead" (CLAUDE.md OI-172 pitfalls row).

/// Requires an actual shell-invocation shape after the pipe — `dart run` (or
/// `$DART_BIN run`) followed by the script name — not just a bare filename
/// mention. Without this, a markdown TABLE row (`| \`blast_radius_from_diff
/// .dart\` | description |`) false-positives: the leading `|` and the bare
/// filename look identical to a real piped invocation to a naive scanner.
final _invocationAfterPipe = RegExp(
  r'(?:dart|\$DART_BIN|"\$DART_BIN")\s+run\s+[^\n|]*blast_radius_from_diff\.dart',
);

/// True iff [addedLine] pipes into a `blast_radius_from_diff.dart` invocation
/// without a trailing bare `-` argument.
bool isPositionalMisuse(String addedLine) {
  final pipeIdx = addedLine.indexOf('|');
  if (pipeIdx < 0) return false;

  final afterPipe = addedLine.substring(pipeIdx + 1);
  final scriptMatch = _invocationAfterPipe.firstMatch(afterPipe);
  if (scriptMatch == null) return false;

  // Everything after the invocation on this line.
  final tail = afterPipe.substring(scriptMatch.end).trim();
  if (tail.isEmpty) return true; // piped, but no trailing '-' at all.

  // Good usage requires the FIRST token to be a bare `-` (the script's only
  // stdin-reading form is `args.length == 1 && args[0] == '-'`), optionally
  // touching closing markdown/shell punctuation (`` ` ``/`'`/`"`/`)`).
  final tokens = tail.split(RegExp(r'\s+'));
  final first = tokens.first;
  final firstIsBareDash = RegExp(r'''^-[`')"]*$''').hasMatch(first);
  if (!firstIsBareDash) return true;

  // Everything AFTER that bare `-` must be shell noise the dart process
  // never sees as an argument — redirection (`2>/dev/null`, `>file`,
  // `2>&1`, `&>`) or a line-continuation backslash — never a genuine
  // second CLI argument (which WOULD change the script's own args.length
  // and defeat its `args[0] == '-'` check). Verified against the real
  // committed shape at scripts/pre-push.sh:168:
  //   | "$DART_BIN" run scripts/blast_radius_from_diff.dart - 2>/dev/null \
  final safeTrailingToken = RegExp(r'''^(\\|\d*>&?\d*\S*|&>\S*|[`')"]+)$''');
  for (final tok in tokens.skip(1)) {
    if (!safeTrailingToken.hasMatch(tok)) return true;
  }
  return false;
}
