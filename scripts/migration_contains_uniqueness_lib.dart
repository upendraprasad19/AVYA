// scripts/migration_contains_uniqueness_lib.dart
//
// Pure logic for check_migration_contains_assertion_uniqueness.dart.
//
// Bug class: feedback_mistake_guard_without_its_mirror.md instance #22 —
// `expect(sql.contains(RegExp(r"RAISE EXCEPTION\s+'consume_quota:")), isTrue)`
// stayed green when the WRONG guard's exception text was mutated, because the
// migration's function defines the same message PREFIX twice (a null-arg
// guard and an invalid-limit guard). `contains()` proves membership, not
// occurrence identity — it cannot tell which of the two fired.
//
// Scope, deliberately narrow: only test files that call
// `latestMigrationDefining(` (test/helpers/migration_cap_reader.dart) are
// examined — that is the one named, existing helper for "assert against a
// migration's live SQL body" in this repo, and the real incident used it.
//
// WARN-ONLY BY DESIGN (see check_migration_contains_assertion_uniqueness.dart
// header) — this heuristic approximates a regex literal by stripping common
// metacharacters, which is not a real regex-to-literal compiler, and
// resolving "which migration file is actually cited" is out of scope (we
// conservatively check against the UNION of all migration file content
// instead of trying to replicate latestMigrationDefining's own resolution).
// A false positive here blocks nothing; it only prints a warning.

/// Parses a `git diff --cached --unified=0 --no-color` blob into
/// file -> [added lines] (content only, `+` prefix stripped).
Map<String, List<String>> addedLinesByFile(String diffText) {
  final out = <String, List<String>>{};
  var currentFile = '';
  for (final raw in diffText.split('\n')) {
    if (raw.startsWith('+++ b/')) {
      currentFile = raw.substring('+++ b/'.length).trim();
      out.putIfAbsent(currentFile, () => <String>[]);
      continue;
    }
    if (!raw.startsWith('+') || raw.startsWith('+++')) continue;
    if (currentFile.isEmpty) continue;
    out.putIfAbsent(currentFile, () => <String>[]).add(raw.substring(1));
  }
  return out;
}

/// Extracts a rough plain-text literal from a `.contains(...)` argument.
///
/// Handles a bare string literal (`'...'`/`"..."`) or a `RegExp(r'...')` /
/// `RegExp(r"...")` argument. For the RegExp form, common metacharacters and
/// whitespace-class tokens are stripped/collapsed to approximate the plain
/// substring they were meant to match. Returns null when no literal is found
/// or the extracted literal is trivially short (< 8 chars after trimming) —
/// short fragments produce too much incidental-collision noise to be useful.
String? extractLiteralFragment(String line) {
  if (!line.contains('.contains(')) return null;

  // Quote-char matters: the literal itself may legitimately contain the
  // OTHER quote character (e.g. a double-quoted Dart string wrapping a SQL
  // message that itself uses single quotes, `"...'consume_quota:...'..."`).
  // A char class that excludes BOTH quote characters truncates at the first
  // embedded one. Try double-quoted first, then single-quoted, for both the
  // RegExp(r"...")  form and the bare .contains("...") form.
  String? raw = RegExp(r'RegExp\(\s*r?"([^"]*)"\s*\)').firstMatch(line)?.group(1) ??
      RegExp(r"RegExp\(\s*r?'([^']*)'\s*\)").firstMatch(line)?.group(1) ??
      RegExp(r'\.contains\(\s*"([^"]*)"\s*\)').firstMatch(line)?.group(1) ??
      RegExp(r"\.contains\(\s*'([^']*)'\s*\)").firstMatch(line)?.group(1);
  if (raw == null) return null;

  // Collapse common regex whitespace-class tokens to a single space, and
  // drop anchors / wildcard runs that carry no literal content.
  var s = raw
      .replaceAll(r'\s+', ' ')
      .replaceAll(r'\s*', ' ')
      .replaceAll(r'.*', ' ')
      .replaceAll(r'.+', ' ')
      .replaceAll('^', '')
      .replaceAll(r'$', '')
      .replaceAll(r'\d+', '')
      .replaceAll(r'\b', '');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

  if (s.length < 8) return null;
  return s;
}

/// Counts occurrences of [literal] inside [haystack], after collapsing
/// consecutive whitespace in BOTH to a single space — makes the approximate
/// literal match robust against incidental SQL formatting differences
/// (a migration wrapping a RAISE EXCEPTION message across two lines, etc.).
int countOccurrencesNormalized(String haystack, String literal) {
  final normHaystack = haystack.replaceAll(RegExp(r'\s+'), ' ');
  final normLiteral = literal.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normLiteral.isEmpty) return 0;
  var count = 0;
  var start = 0;
  while (true) {
    final idx = normHaystack.indexOf(normLiteral, start);
    if (idx < 0) break;
    count++;
    start = idx + normLiteral.length;
  }
  return count;
}

/// The full analysis: staged diff + migration contents -> warning lines.
List<String> findAmbiguousMigrationAssertions({
  required String diffText,
  required Map<String, String> migrationContents,
}) {
  final warnings = <String>[];
  final byFile = addedLinesByFile(diffText);
  final combinedMigrations = migrationContents.values.join('\n---\n');

  for (final entry in byFile.entries) {
    final file = entry.key;
    final lines = entry.value;
    final usesHelper = lines.any((l) => l.contains('latestMigrationDefining('));
    if (!usesHelper) continue;

    for (final line in lines) {
      final literal = extractLiteralFragment(line);
      if (literal == null) continue;
      final count = countOccurrencesNormalized(combinedMigrations, literal);
      if (count > 1) {
        warnings.add(
          '$file: ambiguous .contains() assertion — literal "$literal" '
          'appears $count times across migrations; pin something more '
          'unique (e.g. the full exception message). Line: ${line.trim()}',
        );
      }
    }
  }
  return warnings;
}
