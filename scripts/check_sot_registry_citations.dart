// scripts/check_sot_registry_citations.dart
//
// Gate 44 (post38-auth-fixes, 2026-08-08): assert that every diagnose-doc's
// `sot_registry_entry:` names a concept that ACTUALLY EXISTS in
// docs/sot_registry.yaml.
//
// WHY THIS GATE EXISTS
//
// `scripts/validate_diagnose_doc.dart` — the validator every diagnose-doc must
// pass — contains ZERO references to the SoT registry. It checks that the
// `sot_registry_entry:` FIELD is present and non-empty; it has never checked
// that the value RESOLVES. That blind spot let three docs authored in this very
// batch ship citations pointing at nothing:
//
//   d3a7c9 -> oauth_signin_completion            (0 hits)
//   a4f1c8 -> notifications_inbox_id_contract    (0 hits)
//   c9e2b7 -> password_recovery_session          (0 hits)
//
// all while "passing their validator" — a false-green of exactly the shape
// `feedback_source_grep_false_confidence.md` describes. A dangling citation is
// worse than an absent one: §4.1's writer/reader discipline sends you to the
// registry to find the contract, and finding nothing reads as "this concept was
// never registered" rather than "this doc lied about registering it".
//
// WHY A DATE CUTOFF, NOT A REPO-WIDE HARD FAIL
//
// Measured at introduction: 370 tracked diagnose-docs carrying 90 unresolved
// identifier-shaped citations accumulated since 2026-05-03. A repo-wide
// hard-fail would be UNSATISFIABLE on day one — the failure mode
// `feedback_mistake_claimed_gate_unsatisfiable.md` warns about, where a gate
// nobody can go green against gets bypassed, and a bypassed gate enforces
// nothing.
//
// So the contract is scoped by DOC DATE (parsed from the filename convention
// `YYYY-MM-DD-<slug>-<id>.md`):
//
//   - dated >= citationCutoff -> MUST resolve. Hard fail.
//   - dated <  citationCutoff -> counted and reported as backlog. Never fails.
//
// The backlog count is COMPUTED LIVE, never hand-written, so it cannot go stale
// the way a snapshot number would. `--strict` fails on the backlog too and is
// how this gate graduates once the backlog reaches zero.
//
// WHY NOT SCOPE TO THE STAGED DIFF
//
// scripts/pre-commit.sh invokes every `scripts/check_*.dart` gate with NO
// ARGUMENTS, and CI runs the same set against a checked-out tree where nothing
// is staged. A staged-diff-scoped gate would therefore be VACUOUS in CI —
// green over an empty input set (`feedback_green_check_input_set_width.md`).
// `git ls-files` is correct in both contexts: at pre-commit the index already
// contains staged additions; in CI it is the checked-out tree.
//
// NEGATIVE CONTROL (2026-08-08): with the three docs above staged, this gate
// exits 1 naming all three; unstaged, it exits 0. Pure logic is covered by
// test/contracts/sot_registry_citations_test.dart.
//
// Usage:
//   dart run scripts/check_sot_registry_citations.dart            # cutoff-scoped (default)
//   dart run scripts/check_sot_registry_citations.dart --strict   # fail on the backlog too
//
// Exit 0 = PASS.  Exit 1 = FAIL.

import 'dart:io';

import 'sot_citation_lib.dart';

void main(List<String> args) {
  final strict = args.contains('--strict');

  final registry = File('docs/sot_registry.yaml');
  if (!registry.existsSync()) {
    // FAIL CLOSED. An earlier version exited 0 here ("SKIP"), which meant a
    // rename or accidental deletion of the registry silently DISABLED the gate
    // while a registry that merely parsed to zero concepts failed hard — two
    // states that both mean "citations cannot be verified", handled opposite
    // ways. B-pass 2026-08-08, Finding 5.
    stderr.writeln('[Gate 44] FAIL: docs/sot_registry.yaml not present.');
    stderr.writeln('  Citations cannot be verified without it. If the registry');
    stderr.writeln('  genuinely moved, update this path — do not delete the check.');
    exit(1);
  }

  final concepts = parseConcepts(registry.readAsStringSync());
  if (concepts.isEmpty) {
    stderr.writeln('[Gate 44] FAIL: parsed 0 concepts from docs/sot_registry.yaml.');
    stderr.writeln('  Refusing to run — with an empty concept set every citation');
    stderr.writeln('  would read as dangling. The registry format likely changed.');
    exit(1);
  }

  final ls = Process.runSync('git', ['ls-files', '--', 'docs/diagnoses']);
  if (ls.exitCode != 0) {
    stderr.writeln('[Gate 44] FAIL: `git ls-files` errored: ${ls.stderr}');
    exit(1);
  }

  final docs = (ls.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.endsWith('.md') && !s.contains('INDEX'))
      .toList();

  final violations = <String>[]; // dated >= cutoff, identifier-shaped, unresolved
  final backlog = <String>[]; //   dated <  cutoff, identifier-shaped, unresolved
  final prose = <String>[]; //     not identifier-shaped — unadjudicable

  for (final path in docs) {
    final file = File(path);
    if (!file.existsSync()) continue;

    final name = path.split('/').last;
    final content = file.readAsStringSync();
    final raw = citationOf(content);
    if (raw == null) continue; // no field — validate_diagnose_doc.dart owns that

    // A whole-value sentinel ("Not applicable — …", "N/A", "none") settles the
    // doc before tokenising. Tokenising first reduced `Not applicable` to `Not`,
    // which matched no sentinel and was reported as a hard violation — a false
    // positive that blocked two docs already merged to main.
    if (isSentinelValue(raw)) continue;

    // Date from filename OR `date:` frontmatter, whichever is later.
    final post = isPostCutoff(name, docContent: content);

    for (final cited in splitCitation(raw)) {
      final entry = '$name -> $cited';
      switch (classifyCitation(cited, concepts)) {
        case CitationVerdict.sentinel:
        case CitationVerdict.resolved:
          break;
        case CitationVerdict.prose:
          // A POST-cutoff doc must cite a resolvable concept or an explicit
          // sentinel — prose is a VIOLATION, not a shrug. Otherwise the whole
          // gate is opt-out: write `sot_registry_entry: some new concept` with
          // spaces and the resolve-check never applies, in --strict too.
          // B-pass 2026-08-08, Finding 2.
          (post ? violations : prose).add(entry);
          break;
        case CitationVerdict.dangling:
          (post ? violations : backlog).add(entry);
          break;
      }
    }
  }

  if (backlog.isNotEmpty) {
    stdout.writeln('[Gate 44] WARN: ${backlog.length} pre-$citationCutoff '
        'citation(s) do not resolve (backlog).');
    if (strict) {
      for (final b in backlog) {
        stderr.writeln('  BACKLOG $b');
      }
    }
  }

  if (prose.isNotEmpty) {
    // Stated, not swallowed: this is the gate's known blind spot. A doc that
    // writes its citation as prose is not adjudicated here at all.
    stdout.writeln('[Gate 44] WARN: ${prose.length} citation(s) are prose, not a '
        'concept identifier — not adjudicated.');
  }

  final failures = strict ? [...violations, ...backlog] : violations;

  if (failures.isNotEmpty) {
    stderr.writeln('[Gate 44] FAIL: ${failures.length} diagnose-doc citation(s) '
        'name a concept absent from docs/sot_registry.yaml:');
    for (final v in failures) {
      stderr.writeln('  $v');
    }
    stderr.writeln('');
    stderr.writeln('Fix: add the concept to docs/sot_registry.yaml (with a');
    stderr.writeln('`behavioral_test_path:` per rule 21 / Gate 42), or correct the');
    stderr.writeln('citation to an existing concept, or use `not_applicable`.');
    stderr.writeln('Do NOT delete the field to get green — that just hides the gap.');
    exit(1);
  }

  stdout.writeln('[Gate 44] PASS: ${docs.length} diagnose-doc(s) checked, '
      '${concepts.length} registry concept(s); '
      '0 unresolved citation(s) dated >= $citationCutoff'
      '${backlog.isEmpty ? '' : ', ${backlog.length} in backlog'}.');
  exit(0);
}
