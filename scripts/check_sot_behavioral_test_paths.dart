// scripts/check_sot_behavioral_test_paths.dart
//
// Gate: 42
//
// Gate 42 (Tech-debt audit 2026-05-20, B5 D2 deliverable): assert every
// SoT registry concept entry carries either:
//   - `behavioral_test_path:` (cite a real behavioral contract test)
//   - `presence_only: true`   (source-grep / static / Deno-EF-only, no Flutter seam)
//
// `presence_only: true` is the authorised escape hatch for exactly these cases:
//   - Dep-canonicalization (dependency_canonical_http_client): source-grep IS the test
//   - Static structural (typography_canonical_source): source-grep only
//   - Presentation (ui_header_no_clip): source-grep only
//   - Cross-user Deno EF (community_review_queue): not Flutter-unit-testable
//   - Deno EF placeholder (ai_proxy_placeholder_resolution): no Flutter unit-test seam
//
// Per `feedback_source_grep_false_confidence.md` + CLAUDE.md §4.4 rule 21
// amendment (B5 D1 2026-05-21, tightened P1.D part 2 2026-06-18):
//
//   Source-grep tests count for PRESENCE only — every SoT registry entry
//   MUST have a `behavioral_test_path:` (Hive-write → Hive-read assertion,
//   fakeAsync race harness, or end-to-end flow) that fails when the runtime
//   path is broken even if the source text remains intact, UNLESS the entry
//   explicitly carries `presence_only: true` documenting WHY a behavioral
//   test is not feasible.
//
//   There is NO `behavioral_test_required: true` backlog allowed — the gate
//   is STRICT by default. Any remaining TODO markers block the commit.
//
// Behaviour (P1.D part 2: strict by default):
//   - Default: STRICT — exit 1 if any concept lacks behavioral_test_path AND
//     does not carry presence_only: true. Zero TODOs are allowed.
//   - --warn-only: demote to WARN, exit 0. Use ONLY for temporary debugging
//     of a large refactor in a feature branch; never merge to main with warn-only.
//
// Every cited path must EXIST (OI-195, gate-integrity batch 2026-09-19):
//   Until this change the gate validated the SHAPE of a `behavioral_test_path:`
//   value (non-empty, not tbd/todo, not `""`) and never opened the file it
//   named — a concept could cite a test that was never written, or a
//   `presence_only: true` justification could cite a live-verify SQL file that
//   did not exist yet, and the gate printed PASS. The writer/reader half of the
//   same registry had been resolved on disk by check_sot_registry_parity.dart
//   for months; the test half was not. Now:
//   - `behavioral_test_path:` AND every sibling `behavioral_test_path_<suffix>:`
//     value is comment-stripped (three real entries carry a trailing
//     `# <id> — note`) and must resolve via File(...).existsSync() from CWD.
//   - the trailing `# …` prose on a `presence_only: true` line, and the body
//     of a `presence_only_reason: |` (or `>`) block, are scanned for
//     repo-shaped paths (`test/…`, `docs/…`, `scripts/…`, `supabase/…`,
//     `lib/…`); each must exist too. A cited path is a claim.
//   - ONE helper (`_missingOnDisk`) backs both sinks, so neither can regress
//     while the other keeps the tally green.
//   - the tally counts EVERY `presence_only: true` line and says how many of
//     those concepts also cite a behavioral path (the pre-fix tally reported
//     only the presence-only-WITHOUT-behavioral subset: "7", when 17 lines
//     carry the flag).
//   Red-path tests: test/scripts/sot_behavioral_test_paths_gate_test.dart.
//
// Usage:
//   dart run scripts/check_sot_behavioral_test_paths.dart            # strict (default)
//   dart run scripts/check_sot_behavioral_test_paths.dart --strict   # explicit strict
//   dart run scripts/check_sot_behavioral_test_paths.dart --warn-only
//
// Exit 0 = PASS.
// Exit 1 = FAIL (unresolved entries or missing cited paths in strict mode).

import 'dart:io';

/// OI-195: a cited path is a claim — resolve it against CWD (the repo root
/// when run by the hooks, a fixture dir under test). Returns the path when it
/// does NOT exist so the caller can report it, `null` when it does. This ONE
/// helper backs BOTH sinks (behavioral_test_path values and presence_only
/// prose citations) deliberately: a regression in either cannot hide behind
/// the other's green.
String? _missingOnDisk(String path) =>
    File('${Directory.current.path}/$path').existsSync() ? null : path;

/// Strips a trailing YAML comment (`  # b8d5c2 — note`) and any surrounding
/// quotes from a scalar value. Three live registry values carry the comment
/// shape (lines 3236, 6064, 6350 at filing time); none is quoted today, but a
/// quoted path is still a path.
String _stripValueComment(String raw) {
  var v = raw.replaceFirst(RegExp(r'\s+#.*$'), '').trim();
  if (v.length >= 2 &&
      ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'")))) {
    v = v.substring(1, v.length - 1).trim();
  }
  return v;
}

/// Repo-shaped paths inside free prose — the same idea as
/// check_sot_registry_citations.dart's identifier scan over diagnose-docs.
/// Trailing sentence punctuation is trimmed (`… pinned by test/x.dart.`).
final _repoPathRe =
    RegExp(r'\b(?:test|docs|scripts|supabase|lib)/[A-Za-z0-9_./-]+');

Iterable<String> _repoPathsIn(String prose) => _repoPathRe
    .allMatches(prose)
    .map((m) => m.group(0)!.replaceFirst(RegExp(r'[.,;)]+$'), ''))
    .where((p) => p.isNotEmpty);

void main(List<String> args) async {
  // Default is now STRICT. --warn-only downgrades.
  final warnOnly = args.contains('--warn-only');
  final strict = !warnOnly; // strict unless explicitly overridden

  final file = File('docs/sot_registry.yaml');
  if (!file.existsSync()) {
    stdout.writeln('[Gate 42] SKIP: docs/sot_registry.yaml not present.');
    exit(0);
  }

  final content = file.readAsStringSync().replaceAll('\r\n', '\n');
  final lines = content.split('\n');

  // Walk concept blocks. Each starts with `  - concept: <name>` (2-space + dash).
  // Block ends at the next `  - concept:` line OR EOF.
  final missing = <String>[]; // no behavioral_test_path AND no presence_only
  final staleRequired = <String>[]; // legacy behavioral_test_required: true still present
  final missingFiles = <String>[]; // OI-195: a cited path that does not exist on disk
  final presenceOnly = <String>[]; // presence_only WITHOUT a behavioral path (the concept tally)
  final behavioralPaths = <String>[]; // counted for reporting
  var presenceOnlyLines = 0; // EVERY `presence_only: true` line, whatever else the concept carries
  var presenceOnlyWithBehavioral = 0; // ...of which the concept ALSO cites a behavioral path
  var behavioralPathsChecked = 0; // behavioral_test_path(_*) values resolved on disk
  var prosePathsChecked = 0; // repo-shaped paths inside presence_only prose resolved on disk

  String? currentConcept;
  int? currentLine;
  bool currentHasBehavioralPath = false;
  bool currentHasPresenceOnly = false;
  bool currentHasRequiredFlag = false;

  void flushCurrent() {
    if (currentConcept == null) return;
    final concept = currentConcept; // non-null: guard above returned early
    if (currentHasPresenceOnly && currentHasBehavioralPath) {
      presenceOnlyWithBehavioral++;
    }
    if (currentHasRequiredFlag) {
      // Legacy TODO marker — now a HARD blocker
      staleRequired.add('$concept (line $currentLine)');
    } else if (currentHasBehavioralPath) {
      behavioralPaths.add(concept);
    } else if (currentHasPresenceOnly) {
      presenceOnly.add(concept);
    } else {
      // No behavioral_test_path, no presence_only, no required flag
      missing.add('$concept (line $currentLine)');
    }
  }

  /// OI-195 prose sink: every repo-shaped path in [prose] must exist.
  void checkProsePaths(String prose, int lineNo) {
    for (final p in _repoPathsIn(prose)) {
      prosePathsChecked++;
      if (_missingOnDisk(p) != null) {
        missingFiles.add(
            '$currentConcept: presence_only cites `$p` which does not exist (registry line $lineNo)');
      }
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lineNo = i + 1;
    final conceptMatch = RegExp(r'^  - concept:\s*(\S+)').firstMatch(line);
    if (conceptMatch != null) {
      flushCurrent();
      currentConcept = conceptMatch.group(1);
      currentLine = lineNo;
      currentHasBehavioralPath = false;
      currentHasPresenceOnly = false;
      currentHasRequiredFlag = false;
      continue;
    }
    if (currentConcept == null) continue;

    // behavioral_test_path: <non-empty, non-TBD value> — and every sibling
    // behavioral_test_path_<suffix>: key (registry line 826 is the live one).
    final btpMatch =
        RegExp(r'^\s+behavioral_test_path(?:_[a-z0-9_]+)?\s*:\s*(.*)$')
            .firstMatch(line);
    if (btpMatch != null) {
      // Strip the trailing `# <id> — note` BEFORE judging the value, so a
      // note that happens to say "todo" does not disqualify a real path.
      final path = _stripValueComment(btpMatch.group(1) ?? '');
      if (path.isNotEmpty &&
          !path.toLowerCase().contains('tbd') &&
          !path.toLowerCase().contains('todo')) {
        currentHasBehavioralPath = true;
        // OI-195: the field is a CLAIM about the tree; resolve it.
        behavioralPathsChecked++;
        if (_missingOnDisk(path) != null) {
          missingFiles.add(
              '$currentConcept: behavioral_test_path `$path` does not exist (registry line $lineNo)');
        }
      }
    }

    // presence_only: true  — authorised escape hatch (Deno-EF, static, source-grep-only).
    // The trailing `# …` is the justification; any repo path it names must exist.
    final poMatch =
        RegExp(r'^\s+presence_only\s*:\s*true(.*)$').firstMatch(line);
    if (poMatch != null) {
      currentHasPresenceOnly = true;
      presenceOnlyLines++;
      final trailing = poMatch.group(1) ?? '';
      final hash = trailing.indexOf('#');
      if (hash >= 0) checkProsePaths(trailing.substring(hash + 1), lineNo);
    }

    // presence_only_reason: | (or >) — block scalar; every following line
    // that is MORE indented than the key belongs to it (blank lines are part
    // of a block scalar; the first non-blank line at the key's indent or less
    // ends it). The live block at registry line 6082 has key indent 4, body
    // indent 6, and stops at `description:`. Body lines are consumed here so
    // the main loop never re-reads them as keys.
    final reasonBlock =
        RegExp(r'^(\s+)presence_only_reason\s*:\s*[|>]').firstMatch(line);
    if (reasonBlock != null) {
      final keyIndent = reasonBlock.group(1)!.length;
      final body = StringBuffer();
      var j = i + 1;
      for (; j < lines.length; j++) {
        final l = lines[j];
        if (l.trim().isEmpty) continue;
        final indent = l.length - l.trimLeft().length;
        if (indent <= keyIndent) break;
        body.writeln(l);
      }
      checkProsePaths(body.toString(), lineNo);
      i = j - 1; // the loop's i++ lands on the terminating line
      continue;
    }
    // presence_only_reason: <plain scalar> — same sink, one line.
    final reasonPlain =
        RegExp(r'^\s+presence_only_reason\s*:\s*(.+)$').firstMatch(line);
    if (reasonPlain != null) {
      checkProsePaths(reasonPlain.group(1)!, lineNo);
    }

    // behavioral_test_required: true  — STALE marker; now a gate blocker
    if (RegExp(r'^\s+behavioral_test_required\s*:\s*true').hasMatch(line)) {
      currentHasRequiredFlag = true;
    }
  }
  flushCurrent();

  final tag = strict ? '[Gate 42]' : '[Gate 42 WARN]';
  final problems = <String>[...staleRequired, ...missing, ...missingFiles];

  // Report stale required markers (hard blocker even in warn-only when present)
  if (staleRequired.isNotEmpty) {
    stderr.writeln(
        '$tag ${staleRequired.length} concept(s) still have STALE behavioral_test_required: true:');
    for (final r in staleRequired.take(15)) {
      stderr.writeln('  - $r');
    }
    if (staleRequired.length > 15) {
      stderr.writeln('  ... and ${staleRequired.length - 15} more');
    }
    stderr.writeln(
        '  Fix: add behavioral_test_path: OR presence_only: true, then delete the flag.');
  }

  // Report missing (no path, no presence_only, no required flag)
  if (missing.isNotEmpty) {
    stderr.writeln(
        '$tag ${missing.length} concept(s) have NO behavioral_test_path AND NO presence_only: true:');
    for (final m in missing.take(20)) {
      stderr.writeln('  - $m');
    }
    if (missing.length > 20) {
      stderr.writeln('  ... and ${missing.length - 20} more');
    }
    stderr.writeln('');
    stderr.writeln(
        'Per feedback_source_grep_false_confidence.md + CLAUDE.md §4.4 rule 21:');
    stderr.writeln(
        '  Every SoT concept needs either behavioral_test_path: OR presence_only: true.');
    stderr.writeln(
        '  Source-grep alone is insufficient. presence_only: true is only for');
    stderr.writeln(
        '  Deno-EF / static-structural / source-grep-gated concepts with no Flutter seam.');
  }

  // Report cited paths that do not exist on disk (OI-195). Mirrors the
  // `[file-missing]` shape check_sot_registry_parity.dart uses for the
  // writer/reader half of the same registry.
  if (missingFiles.isNotEmpty) {
    stderr.writeln(
        '$tag ${missingFiles.length} cited path(s) do NOT exist on disk (OI-195):');
    for (final m in missingFiles.take(20)) {
      stderr.writeln('  - [file-missing] $m');
    }
    if (missingFiles.length > 20) {
      stderr.writeln('  ... and ${missingFiles.length - 20} more');
    }
    stderr.writeln(
        '  A cited path is a claim. Fix the citation or write the test it names;');
    stderr.writeln(
        '  never satisfy this by deleting the citation (that is the pre-OI-195 gap).');
  }

  if (problems.isEmpty) {
    stdout.writeln(
        '$tag PASS: all ${behavioralPaths.length} SoT concepts have behavioral_test_path; '
        '$presenceOnlyLines carry presence_only: true '
        '($presenceOnlyWithBehavioral of them also cite a behavioral path; '
        '${presenceOnly.length} presence-only). '
        '$behavioralPathsChecked behavioral_test_path value(s) + '
        '$prosePathsChecked presence_only prose citation(s) resolved on disk. '
        'Zero behavioral_test_required TODOs remain.');
    exit(0);
  }

  // Summary
  stderr.writeln('');
  stderr.writeln(
      '$tag SUMMARY: ${behavioralPaths.length} with behavioral_test_path, '
      '$presenceOnlyLines presence_only lines ($presenceOnlyWithBehavioral also behavioral), '
      '${staleRequired.length} stale-required (BLOCKER), '
      '${missing.length} missing (BLOCKER), '
      '${missingFiles.length} file-missing (BLOCKER).');

  exit(strict ? 1 : 0);
}
