// scripts/sot_citation_lib.dart
//
// Pure parsing/classification logic for the diagnose-doc SoT-citation gate
// (scripts/check_sot_registry_citations.dart). Kept separate + IO-free so the
// contract test can exercise every branch deterministically without a git or
// filesystem fixture. Named WITHOUT the `check_` prefix so the pre-commit
// `check_*.dart` gate loop (and Gate 33) treat only the gate itself as a gate.
//
// See the gate file header for the full rationale (validate_diagnose_doc.dart
// never checked that `sot_registry_entry:` RESOLVES, so three docs in the
// post38-auth-fixes batch shipped citations pointing at nothing while "passing
// their validator").

/// Docs dated on/after this MUST cite a resolvable concept.
///
/// Chosen as the earliest date at which the tracked corpus was already clean:
/// at introduction all 16 tracked docs dated >= this resolved. Moving it
/// EARLIER is a tightening and requires clearing whatever it newly captures.
const String citationCutoff = '2026-08-01';

/// Values that explicitly assert "no registry concept applies", in NORMALISED
/// form — compare with [normalizeSentinel], never against a raw string.
const Set<String> citationSentinels = {
  'n_a',
  'na',
  'null',
  'none',
  'not_applicable',
  'tbd',
  'nil',
};

/// Case-folds and collapses every run of non-alphanumerics to a single `_`.
///
/// `Not applicable`, `NOT APPLICABLE`, `not-applicable`, `n/a`, `N/A` all
/// normalise onto the set above.
///
/// Why this exists: the first version compared raw lowercased TOKENS against a
/// literal set. `sot_registry_entry: Not applicable — …` tokenised to `Not`,
/// missed the set, was not identifier-shaped, and — once post-cutoff prose
/// became a hard violation — was reported as a FAILURE. That false positive
/// blocked two diagnose-docs that had already merged to main
/// (a4f7c2, d7b3e9), i.e. a gate shipped hours earlier was failing other
/// people's valid work. A gate that rejects correct input is worse than no gate.
String normalizeSentinel(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+'), '')
    .replaceAll(RegExp(r'_+$'), '');

/// Words that OPEN an explicit "no concept applies" declaration.
///
/// The repo's real convention is not a bare token — authors write a sentence
/// saying why nothing applies, e.g.
///   `sot_registry_entry: > Not a Hive/cloud writer-reader storage concept — …`
///   `sot_registry_entry: n/a — no writer contract changed`
/// Both are the author being MORE explicit, not less. A first version treated
/// all post-cutoff prose as a violation and so rejected two docs already merged
/// to main (a4f7c2, d7b3e9).
///
/// The line that actually matters: a value OPENING with a negation is a
/// declaration; prose that opens with anything else (`some new concept here`)
/// is unadjudicable and stays a violation post-cutoff — that is the evasion
/// shape the B-pass flagged.
const Set<String> _negationOpeners = {
  'not', 'no', 'none', 'na', 'n', 'nil', 'null', 'tbd', 'nothing', 'neither',
};

/// True when the citation VALUE AS A WHOLE declares that no concept applies.
///
/// Checked BEFORE tokenising — that is the entire point. Tokenising first
/// reduced `Not applicable` to `Not`, matched no sentinel, and failed the doc.
bool isSentinelValue(String raw) {
  var s = raw.split('#').first;
  s = s.replaceAll(RegExp(r'\([^)]*\)'), ' '); // provenance parentheticals
  for (final marker in ['—', '--', ';', ':']) {
    final i = s.indexOf(marker);
    if (i >= 0) s = s.substring(0, i);
  }
  final norm = normalizeSentinel(s);
  if (norm.isEmpty || citationSentinels.contains(norm)) return true;
  // The negation rule applies to PROSE ONLY. A bare snake_case identifier is a
  // concept name and must be adjudicated as one — otherwise any concept
  // starting `no_` (e.g. `no_such_concept`) would be waved through as a
  // declaration, which is a hole, not a fix.
  if (isIdentifierShaped(s.trim())) return false;
  return _negationOpeners.contains(norm.split('_').first);
}

/// How a single citation token is adjudicated.
enum CitationVerdict {
  /// An explicit "no concept applies" marker. Fine.
  sentinel,

  /// Not identifier-shaped — free prose. This gate cannot adjudicate it either
  /// way; reported so the blind spot is visible rather than silently skipped.
  prose,

  /// Names a concept that exists in docs/sot_registry.yaml.
  resolved,

  /// Identifier-shaped but names nothing in the registry. The defect.
  dangling,
}

/// A bare snake_case concept name — the only shape this gate can adjudicate.
final RegExp _identifierShaped = RegExp(r'^[a-z][a-z0-9_]{2,}$');

bool isIdentifierShaped(String s) => _identifierShaped.hasMatch(s);

/// Concept entries in docs/sot_registry.yaml are a LIST — `  - concept: <name>`
/// — not a mapping.
///
/// Parsing them as `  <name>:` yields an EMPTY set, which makes every citation
/// look dangling. That exact mistake produced a bogus "299 broken docs" reading
/// during this gate's design, so callers must treat an empty result as a parse
/// failure rather than as "no concepts exist".
Set<String> parseConcepts(String yaml) => RegExp(
      r'^\s*-\s*concept:\s*([A-Za-z0-9_]+)\s*$',
      multiLine: true,
    ).allMatches(yaml.replaceAll('\r\n', '\n')).map((m) => m.group(1)!).toSet();

/// Extracts the raw `sot_registry_entry:` value from a diagnose-doc, following
/// a `>`/`|` block scalar to its first non-empty continuation line.
/// Returns null when the field is absent (validate_diagnose_doc.dart owns that).
String? citationOf(String docContent) {
  final lines = docContent.replaceAll('\r\n', '\n').split('\n');
  for (var i = 0; i < lines.length; i++) {
    final m = RegExp(r'^sot_registry_entry:\s*(.*)$').firstMatch(lines[i]);
    if (m == null) continue;
    var value = m.group(1)!.trim();
    if (value.startsWith('>') || value.startsWith('|')) {
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].trim().isEmpty) continue;
        if (!lines[j].startsWith(' ')) break; // dedented — block ended
        value = lines[j].trim();
        break;
      }
    }
    return value;
  }
  return null;
}

/// Splits a citation into individual concept tokens.
///
/// The field's real-world shape in this repo is looser than "a bare concept
/// name". All of these occur in tracked docs and are LEGITIMATE:
///
///   workout_receipt_rendering, workout_log_edit_surface
///   phase_progress_current_phase (docs/sot_registry.yaml)
///   onboarding_completed_at (docs/sot_registry.yaml:3847) — no new concept
///   n/a — no Hive/cloud writer contract changed
///
/// So: strip `#` comments and `(...)` provenance parentheticals, cut prose at
/// the first em-dash / `--` / `;`, split on commas, take each part's leading
/// token. A first version that skipped these steps reported 9 false failures
/// against docs whose citations were entirely valid.
Iterable<String> splitCitation(String raw) sync* {
  var s = raw.split('#').first;
  s = s.replaceAll(RegExp(r'\([^)]*\)'), ' '); // provenance parentheticals
  for (final marker in ['—', '--', ';']) {
    final i = s.indexOf(marker);
    if (i >= 0) s = s.substring(0, i);
  }
  s = s.trim();
  if (s.isEmpty) return;
  for (final part in s.split(',')) {
    final tokens = part.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (tokens.isEmpty) continue;
    yield tokens.first.replaceAll(RegExp(r'[.;:,]+$'), '').trim();
  }
}

/// Adjudicates one already-split citation token against the registry.
CitationVerdict classifyCitation(String cited, Set<String> concepts) {
  final norm = normalizeSentinel(cited);
  if (citationSentinels.contains(norm)) return CitationVerdict.sentinel;
  // Negation opener => a prose declaration. NOT applied to identifier-shaped
  // values, or `no_such_concept` would classify as "no concept applies".
  if (!isIdentifierShaped(cited) &&
      _negationOpeners.contains(norm.split('_').first)) {
    return CitationVerdict.sentinel;
  }
  if (!isIdentifierShaped(cited)) return CitationVerdict.prose;
  return concepts.contains(cited) ? CitationVerdict.resolved : CitationVerdict.dangling;
}

/// True when a diagnose-doc is on or after [cutoff] — i.e. subject to the hard
/// resolve-check rather than grandfathered into the backlog.
///
/// Reads BOTH the filename's leading `YYYY-MM-DD-` and the doc's own `date:`
/// frontmatter, and takes the LATER of the two. Lexicographic compare is
/// correct for zero-padded ISO dates.
///
/// Why both: B-pass 2026-08-08 (Finding 6) pointed out that a filename-only
/// check lets a new doc exempt itself permanently just by being NAMED with a
/// pre-cutoff date. Requiring both fields to be backdated raises the cost and,
/// more usefully, makes the evasion VISIBLE in review — a doc whose frontmatter
/// date disagrees with its filename is an obvious smell.
///
/// Stated plainly so nobody over-trusts it: this cutoff is a GRANDFATHERING
/// mechanism, not a security boundary. An author who controls both fields can
/// still opt out. The defence against that is review, not this function.
///
/// A doc with neither parseable date is treated as PRE-cutoff — the gate must
/// not hard-fail on a naming convention it cannot read.
bool isPostCutoff(
  String fileName, {
  String cutoff = citationCutoff,
  String? docContent,
}) {
  final dates = <String>[];
  final fromName = RegExp(r'^(\d{4}-\d{2}-\d{2})-').firstMatch(fileName);
  if (fromName != null) dates.add(fromName.group(1)!);
  if (docContent != null) {
    final fromFm =
        RegExp(r'^date:\s*(\d{4}-\d{2}-\d{2})', multiLine: true).firstMatch(docContent);
    if (fromFm != null) dates.add(fromFm.group(1)!);
  }
  if (dates.isEmpty) return false;
  dates.sort();
  return dates.last.compareTo(cutoff) >= 0;
}
