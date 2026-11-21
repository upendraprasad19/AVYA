// scripts/skill_tuning_lib.dart
//
// PURE predicate behind scripts/check_skill_tuning_history.dart.
//
// WHY THIS EXISTS. `.claude/skills/code-review/SKILL.md` §5 says, in its own words:
// "Append after each invocation: invocation date, blast-radius, findings count,
// false-alarm count, tuning made." On 2026-08-25 a B-pass ran, produced
// docs/reviews/2e9503eb-review.md with 4 findings, and NOTHING was appended —
// the omission surfaced only because founder asked whether discipline had been
// followed. The skill's own self-evolution loop was the thing decaying.
//
// That is the repo's most-repeated structural lesson, stated in CLAUDE.md §4.13
// point 6 about a different rule entirely: "everything with a gate holds,
// everything on intention decays." §5.1 had no gate. Now it does.
//
// TWO ROUTES (merge-conflict-treadmill A1, 2026-10-24). The archive
// (`.claude/skills/code-review/tuning-history.md`) was an append-at-EOF file that
// every parallel review PR edited at the same spot, so it conflicted on 35 of 52
// main-sync merges. A review now carries its OWN `## Tuning entry` section inside
// the review file (inReviewEntry); the archive is frozen (countDatedHeaders) and
// is read only for legacy entries. A review is satisfied by EITHER route, and the
// in-review route is evaluated first and independently of the archive: an
// unreadable archive no longer silences it.
//
// WHAT THIS CAN AND CANNOT PROVE. It proves a dated entry EXISTS for the review
// being added. It cannot prove the entry is honest, well-reasoned, or that any
// tuning actually happened — the same self-attested trust model as rule 21's
// `presence_only:` and rule 24's ledger. Say so plainly rather than implying the
// loop is now airtight; what is closed is the silent-omission hole.

/// One review file the commit is adding, reduced to what the gate needs.
class ReviewClaim {
  /// Repo-relative path, forward slashes.
  final String path;

  /// The `reviewed_at:` date as `YYYY-MM-DD`, or null when unparseable.
  final String? reviewedOn;

  /// The STAGED review body, for the in-review `## Tuning entry` route. Null =
  /// unreadable (that route then cannot be satisfied; the archive still can).
  final String? body;

  const ReviewClaim(this.path, this.reviewedOn, {this.body});
}

/// The verdict, carrying WHY rather than a bare bool.
///
/// A bool could not distinguish "no review was added, nothing to check" from
/// "a review was added and its entry is present" — and a caller that collapses
/// those two reports a PASS it never established. Same reason
/// `PlanIntegrityReconciler.computeTriggers` returns a record: a predicate must
/// not throw away the binding it establishes (see the 2026-08-17 B-pass, where
/// exactly that shape reopened a hole two review rounds had just closed).
enum TuningVerdict {
  /// No review file added — the gate has nothing to say.
  notApplicable,

  /// A review was added and a same-dated tuning entry exists.
  satisfied,

  /// A review was added and NO same-dated tuning entry exists. Blocks.
  missingEntry,

  /// A review was added but its `reviewed_at:` could not be parsed, so the gate
  /// cannot form a question. FAILS OPEN — never wedge a commit on a parse.
  undetermined,
}

class TuningResult {
  final TuningVerdict verdict;
  final String reason;
  final List<String> offendingPaths;
  const TuningResult(this.verdict, this.reason,
      [this.offendingPaths = const []]);
}

/// The UTF-8 byte order mark as a character. Built from its code point, never typed
/// into the source, so no invisible character lives in this file.
final String _bom = String.fromCharCode(0xFEFF);

/// [text] without a leading byte order mark. A BOM made `reviewed_at:` read as an
/// unknown key (the review was then SKIPPED, fail open) and made the frontmatter tier
/// check silently not run.
String _stripBom(String text) => text.startsWith(_bom) ? text.substring(1) : text;

/// `YYYY-MM-DD` out of a `reviewed_at:` frontmatter line, or null.
///
/// Line-anchored on purpose. `docs/plan-reviews/` records are parsed the same
/// way by the keystone gate, and a session already lost a CI run to a bullet
/// header that the anchored parser read as null
/// (feedback_plan_review_record_frontmatter_format). Matching mid-line would
/// let prose mentioning "reviewed_at" satisfy the parse.
String? reviewedOnFrom(String markdown) {
  for (final raw in _stripBom(markdown).split('\n')) {
    final line = raw.trimRight();
    if (!line.startsWith('reviewed_at:')) continue;
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(line);
    if (m == null) return null;
    return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
  }
  return null;
}

/// A dated tuning-history bullet header, with the OPTIONAL same-day
/// disambiguator the file's own convention uses: `- **2026-08-29 (d)** — …`.
///
/// ⚠ The suffix arm is load-bearing and its absence was a live bug (found
/// 2026-08-30 by plan-review round 1 of `process-hardening`, while the gate
/// was blocking that batch's own honest entry). The original pattern required
/// the date to be immediately closed by `**`, so it matched NONE of the **5**
/// suffixed headers already in `code-review/SKILL.md` — the dominant shape for
/// a second review on one date, which that file's history explicitly needs
/// ("a batch commonly runs a B-pass on the day a sibling batch also does").
/// The effect was not a false PASS but a false FAIL that pushes toward the
/// wrong repair: a correctly-written `(b)` entry reads as missing, and the
/// obvious way out is to flatten the date and lose the disambiguation the
/// convention exists for. Same guard-without-its-mirror class as the rest of
/// this batch — a matcher that only accepts the spelling its author pictured.
/// ⚠ The suffix body is `.*` (greedy), NOT `[^)]*` (round-2 review P3). With
/// `[^)]*` the group stops at the FIRST `)`, so a nested-paren disambiguator
/// — `**2026-08-29 (see note (details))**` — matched neither this pattern nor
/// `anyDatedHeader`. The false NEGATIVE is the visible half; the dangerous
/// half is that failing to match `anyDatedHeader` means such a header no
/// longer TERMINATES the preceding block, so the entry above it gets credited
/// with naming a review belonging to a different date — a false PASS of
/// exactly the check `hasTuningEntryForReview` exists to make. Greedy `.*`
/// backtracks to the LAST `)` on the line and cannot cross a newline (Dart's
/// `.` excludes `\n` without `dotAll`), so it stays line-scoped.
String _datedHeaderSource(String isoDatePattern) =>
    r'^\s*[-*]\s+\*\*' + isoDatePattern + r'(?:\s*\(.*\))?\*\*';

/// True when [skillMarkdown] has a tuning-history bullet dated [isoDate].
///
/// The accepted shape is the one every existing entry already uses:
/// `- **YYYY-MM-DD** — blast-radius …` (optionally `**YYYY-MM-DD (b)**`).
/// Deliberately NOT a bare
/// `contains(isoDate)`: the date also appears in prose inside older entries
/// (one entry cites "2026-08-17" while describing a different batch), so a
/// substring test would let a NEW review be satisfied by an OLD entry's prose.
/// That is the input-set-width trap this repo files under
/// feedback_green_check_input_set_width — a check answering a narrower question
/// than the one being asked.
bool hasTuningEntryFor(String skillMarkdown, String isoDate) {
  final pattern = RegExp(
    _datedHeaderSource(RegExp.escape(isoDate)),
    multiLine: true,
  );
  return pattern.hasMatch(skillMarkdown);
}

/// True when a dated entry exists **that is about THIS review**.
///
/// ⚠ DATE ALONE IS NOT ENOUGH, and the B-pass proved this was live: on
/// 2026-08-25 `SKILL.md` already carried a `- **2026-08-25** —` bullet for the
/// `oi60-client-blockers` review, so the very next review written that same day
/// would have been reported SATISFIED by an entry describing somebody else's
/// batch. The gate built to stop the skill's self-evolution loop decaying would
/// have silently passed its own first real use.
///
/// Two reviews on one calendar date is not exotic here — a batch commonly runs a
/// B-pass on the day a sibling batch also does.
///
/// So the dated bullet's BLOCK (from its own line to the next dated bullet, or
/// EOF) must also NAME the review — its basename, with or without extension.
/// The block scan is why this cannot be one regex: an entry is multi-line prose
/// and the reference usually sits several lines below its header.
bool hasTuningEntryForReview(
  String skillMarkdown,
  String isoDate,
  String reviewPath,
) {
  final basename = reviewPath.split('/').last;
  final stem =
      basename.endsWith('.md') ? basename.substring(0, basename.length - 3) : basename;
  final lines = skillMarkdown.split('\n');
  // Both patterns accept the optional `(x)` same-day disambiguator — see
  // _datedHeaderSource. `anyDatedHeader` must accept it too, and that half is
  // the subtler one: it terminates a block. If it did not match `(b)` headers,
  // a suffixed entry would be absorbed into the PRECEDING entry's block, and
  // the previous batch's entry would then be credited with naming this
  // review — a false PASS, the exact "an OLD entry satisfies a NEW review"
  // failure this function was written to prevent.
  final header = RegExp(_datedHeaderSource(RegExp.escape(isoDate)));
  final anyDatedHeader = RegExp(_datedHeaderSource(r'\d{4}-\d{2}-\d{2}'));

  for (var i = 0; i < lines.length; i++) {
    if (!header.hasMatch(lines[i])) continue;
    final block = StringBuffer(lines[i]);
    for (var j = i + 1; j < lines.length; j++) {
      if (anyDatedHeader.hasMatch(lines[j])) break;
      block.writeln();
      block.write(lines[j]);
    }
    if (block.toString().contains(stem)) return true;
  }
  return false;
}

final RegExp _anyDatedHeaderLine = RegExp(_datedHeaderSource(r'\d{4}-\d{2}-\d{2}'));

/// True when [line] is a dated tuning bullet header (`- **YYYY-MM-DD** ...`, with
/// the optional same-day `(x)` disambiguator). Public so the in-review scanner,
/// the archive freeze and `hasTuningEntryForReview` share ONE definition. An
/// indented SUB-bullet matches too (`^\s*`): it counts as an entry everywhere.
bool isDatedHeaderLine(String line) => _anyDatedHeaderLine.hasMatch(line);

/// The dated header lines of [markdown], in file order.
List<String> datedHeaderLines(String markdown) =>
    markdown.split('\n').map((l) => l.trimRight()).where(isDatedHeaderLine).toList();

/// How many dated bullet headers [markdown] has. The freeze compares this count
/// between the staged archive and its HEAD blob: strictly greater = a new entry.
int countDatedHeaders(String markdown) => datedHeaderLines(markdown).length;

/// The four tiers `docs/blast_radius.yaml` knows. The header/frontmatter tier check
/// runs only when BOTH sides are one of these, so a template placeholder
/// (`<feature|account|...>`) or free text never produces a false mismatch.
const _knownTiers = {'feature', 'account', 'platform', 'catastrophic'};

/// The tier a review's frontmatter declares: the first word of its `blast_radius:`
/// value (an optional quote stripped), or null. Read ONLY inside the leading `---`
/// block. A value that does not START with a word (`<feature|account|...>`)
/// yields null.
String? frontmatterBlastRadius(String review) {
  final lines = _stripBom(review).split('\n').map((l) => l.trimRight()).toList();
  // Leading blank lines are tolerated: a review that starts with one still has its
  // frontmatter, and refusing to read it would silently switch the tier check off.
  var start = 0;
  while (start < lines.length && lines[start].isEmpty) {
    start++;
  }
  if (start >= lines.length || lines[start] != '---') return null;
  for (var i = start + 1; i < lines.length; i++) {
    final l = lines[i];
    if (l == '---' || l == '...') return null;
    final m = RegExp(r'^blast_radius:\s*(.*)$').firstMatch(l);
    if (m == null) continue;
    final w = RegExp("^[\"']?([A-Za-z]+)").firstMatch(m.group(1)!.trim());
    return w?.group(1)?.toLowerCase();
  }
  return null;
}

/// The tier a tuning header names: the first word after `blast-radius` (an optional
/// colon is allowed) and any `*` bold markers (`blast-radius **account**`,
/// `blast-radius: account`, `blast-radius account (L ...)`).
String? _headerTier(String headerLine) {
  final m = RegExp(r'blast-radius(?::\s*|\s+)\**([a-z]+)', caseSensitive: false).firstMatch(headerLine);
  return m?.group(1)?.toLowerCase();
}

/// The outcome of the in-review route for one review.
class InReviewCheck {
  /// True when the review carries a valid `## Tuning entry` section.
  final bool ok;

  /// Why not, naming the construct and its line. Null when [ok].
  final String? problem;

  const InReviewCheck.ok()
      : ok = true,
        problem = null;
  const InReviewCheck.fail(String this.problem) : ok = false;
}

final RegExp _fenceOpener = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
final RegExp _tuningHeading = RegExp(r'^## Tuning entry[ \t]*$');

/// What the single-pass scanner found.
class _SectionScan {
  /// 0-based index of the FIRST `## Tuning entry` heading outside every fence and
  /// comment, or null.
  final int? heading;

  /// 1-based line where a fence opened and never closed (runs to EOF), or null.
  final int? unclosedFenceLine;

  /// 1-based line where a comment opened and never closed, or null.
  final int? unclosedCommentLine;

  const _SectionScan(this.heading, this.unclosedFenceLine, this.unclosedCommentLine);
}

/// One pass over [lines] (already `trimRight`ed, so CRLF files read like LF ones,
/// as `reviewedOnFrom` does). A line state machine, NOT strip-fences-then-strip-
/// comments: two passes cannot tell a fence opener inside a comment (inert) from
/// a real one, nor a comment opener inside a fence (inert) from a real one, and
/// each order has a hand-built review that fools it.
///   * fences follow CommonMark: backtick or tilde, the closer is the same
///     character and at least as long, an unclosed fence runs to EOF (and the
///     backtick info string may not contain a backtick);
///   * `<!--` ... `-->` may span lines and may open and close several times on one
///     line; an opener inside an inline code span or after a backslash is literal text;
///   * a line that begins inside a comment, or that contains a comment opener, is
///     never a heading.
/// [line] with every CommonMark code span blanked to spaces (same length, so indices
/// still line up): a backtick run closed by a later run of the SAME length. A run with
/// no matching closer is literal text. A comment opener quoted in inline code
/// (`<!--` in backticks) is therefore not an opener; without this, one unclosed
/// mention in a review's prose hid the `## Tuning entry` section after it and BLOCKED
/// the commit.
String _blankCodeSpans(String line) {
  final out = StringBuffer();
  var i = 0;
  while (i < line.length) {
    if (line[i] != '`') {
      out.write(line[i]);
      i++;
      continue;
    }
    var n = 0;
    while (i + n < line.length && line[i + n] == '`') {
      n++;
    }
    int? close;
    var j = i + n;
    while (j < line.length) {
      if (line[j] != '`') {
        j++;
        continue;
      }
      var m = 0;
      while (j + m < line.length && line[j + m] == '`') {
        m++;
      }
      if (m == n) {
        close = j;
        break;
      }
      j += m;
    }
    if (close == null) {
      out.write(line.substring(i, i + n));
      i += n;
    } else {
      out.write(' ' * (close + n - i));
      i = close + n;
    }
  }
  return out.toString();
}

/// True when the `<` at [index] of [line] is backslash-escaped (an odd number of
/// backslashes directly before it), which CommonMark reads as a literal `<`.
bool _escaped(String line, int index) {
  var k = 0;
  while (index - 1 - k >= 0 && line[index - 1 - k] == '\\') {
    k++;
  }
  return k.isOdd;
}

_SectionScan _scanSections(List<String> lines) {
  String? fenceChar;
  var fenceLen = 0;
  var fenceLine = 0;
  var inComment = false;
  var commentLine = 0;
  int? heading;

  // Walk `<!--` / `-->` through [line] starting in state [open]; returns the state at
  // the end of the line (a comment may open and close several times on one line).
  bool commentStateAfter(String line, bool open) {
    var pos = 0;
    // Openers are looked for in the line with code spans blanked; closers in the line
    // as written (inside a comment nothing is code).
    final masked = _blankCodeSpans(line);
    while (true) {
      if (!open) {
        final s = masked.indexOf('<!--', pos);
        if (s < 0) return false;
        if (_escaped(masked, s)) {
          pos = s + 1;
          continue;
        }
        open = true;
        pos = s + 4;
      } else {
        final e = line.indexOf('-->', pos);
        if (e < 0) return true;
        open = false;
        pos = e + 3;
      }
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    // 1. Inside a fence: only a closer matters; a comment opener here is inert.
    if (fenceChar != null) {
      final closer = RegExp('^ {0,3}${RegExp.escape(fenceChar)}{$fenceLen,}[ \\t]*\$');
      if (closer.hasMatch(line)) fenceChar = null;
      continue;
    }
    // 2. Inside a comment: everything is inert, a fence opener included.
    if (inComment) {
      inComment = commentStateAfter(line, true);
      continue;
    }
    // 3. A fence opener wins over a comment opener in its own info string
    //    (CommonMark: the info string is opaque text), so decide it BEFORE comments.
    final f = _fenceOpener.firstMatch(line);
    if (f != null && !(f.group(1)!.startsWith('`') && f.group(2)!.contains('`'))) {
      fenceChar = f.group(1)![0];
      fenceLen = f.group(1)!.length;
      fenceLine = i + 1;
      continue;
    }
    // 4. An ordinary line. A heading is the exact text `## Tuning entry`, so a line
    //    carrying a comment opener can never be one.
    if (heading == null && _tuningHeading.hasMatch(line)) heading = i;
    if (commentStateAfter(line, false)) {
      inComment = true;
      commentLine = i + 1;
    }
  }
  return _SectionScan(heading, fenceChar != null ? fenceLine : null, inComment ? commentLine : null);
}

/// The in-review route: does [review] carry a valid `## Tuning entry` section?
///
/// The FIRST heading `^## Tuning entry[ \t]*$` at column 0 outside every fence and
/// comment is judged (a later one cannot rescue a bad first). The first non-blank
/// line after it must be a dated bullet ([isDatedHeaderLine]) whose date equals
/// [isoDate] (the review's own `reviewed_at`). When the bullet's `blast-radius`
/// word and [tier] (the frontmatter tier, see [frontmatterBlastRadius]) are BOTH
/// known tiers they must agree. The entry need not name the review file: it lives
/// inside it, so it cannot describe somebody else's batch (the archive route needed
/// that identity check; this one is structurally immune).
InReviewCheck inReviewEntry(String review, String isoDate, String? tier) {
  final lines = _stripBom(review).split('\n').map((l) => l.trimRight()).toList();
  final scan = _scanSections(lines);
  final h = scan.heading;
  if (h == null) {
    final why = scan.unclosedFenceLine != null
        ? ' (a code fence opened at line ${scan.unclosedFenceLine} is never closed, so everything after it is ignored)'
        : scan.unclosedCommentLine != null
            ? ' (a comment opened at line ${scan.unclosedCommentLine} is never closed, so everything after it is ignored; '
            'to quote a comment opener literally, put it in backticks)'
            : '';
    return InReviewCheck.fail(
        'no `## Tuning entry` heading at column 0 outside code fences and comments$why');
  }
  var j = h + 1;
  while (j < lines.length && lines[j].isEmpty) {
    j++;
  }
  if (j >= lines.length) {
    return InReviewCheck.fail('the `## Tuning entry` heading at line ${h + 1} has no dated bullet after it');
  }
  final header = lines[j];
  if (!isDatedHeaderLine(header)) {
    return InReviewCheck.fail(
        'line ${j + 1} (the first non-blank line after the `## Tuning entry` heading at line ${h + 1}) '
        'is not a dated bullet like `- **YYYY-MM-DD** - blast-radius <tier> - N findings; ...`');
  }
  final date = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(header)!.group(0)!;
  if (date != isoDate) {
    return InReviewCheck.fail('the dated bullet at line ${j + 1} says $date but the review\'s reviewed_at '
        'is $isoDate; edit whichever is wrong');
  }
  final headerTier = _headerTier(header);
  if (headerTier != null &&
      tier != null &&
      _knownTiers.contains(headerTier) &&
      _knownTiers.contains(tier) &&
      headerTier != tier) {
    return InReviewCheck.fail('the dated bullet at line ${j + 1} says blast-radius $headerTier but the '
        'review\'s frontmatter blast_radius is $tier; edit whichever is wrong');
  }
  return const InReviewCheck.ok();
}

/// Decide, given the reviews this commit ADDS and the legacy archive's content.
///
/// A review is satisfied by EITHER route: its own `## Tuning entry` section
/// ([inReviewEntry]), evaluated FIRST and independently of the archive, or a
/// legacy dated bullet in the archive that names it ([hasTuningEntryForReview]).
/// [skillMarkdown] is the archive; null (unreadable or absent) now only means "no
/// legacy entries", so a review failing the in-review route is
/// [TuningVerdict.missingEntry], never [TuningVerdict.undetermined]. The only
/// fail-open left is a review with no parseable `reviewed_at:` date: no question
/// can be formed, and a gate must not wedge a commit on a parse it cannot make.
TuningResult evaluateTuning({
  required List<ReviewClaim> addedReviews,
  required String? skillMarkdown,
}) {
  if (addedReviews.isEmpty) {
    return const TuningResult(
        TuningVerdict.notApplicable, 'no review file added by this commit');
  }
  final unparseable =
      addedReviews.where((r) => r.reviewedOn == null).map((r) => r.path).toList();
  final dated = addedReviews.where((r) => r.reviewedOn != null).toList();

  // A dateless file must not MASK a dated one that is genuinely missing its
  // entry. The first version returned undetermined the moment ANY candidate was
  // unparseable, so adding one stray .md alongside a real review silenced the
  // gate for both. Only when there is nothing dated to judge is the whole
  // evaluation undetermined.
  if (dated.isEmpty) {
    if (unparseable.isEmpty) {
      return const TuningResult(
          TuningVerdict.notApplicable, 'no review file added by this commit');
    }
    return TuningResult(
      TuningVerdict.undetermined,
      'review(s) carry no parseable line-anchored `reviewed_at:` date, so no '
      'question can be formed — failing OPEN',
      unparseable,
    );
  }

  final missing = <String>[];
  for (final r in dated) {
    final body = r.body;
    final inReview = body == null
        ? const InReviewCheck.fail('the staged review could not be read')
        : inReviewEntry(body, r.reviewedOn!, frontmatterBlastRadius(body));
    if (inReview.ok) continue;
    // Date AND identity. A same-dated entry about a DIFFERENT review does not
    // discharge this one — see hasTuningEntryForReview.
    if (skillMarkdown != null &&
        hasTuningEntryForReview(skillMarkdown, r.reviewedOn!, r.path)) {
      continue;
    }
    missing.add('${r.path} (reviewed_at ${r.reviewedOn}): ${inReview.problem}');
  }
  if (missing.isNotEmpty) {
    return TuningResult(
      TuningVerdict.missingEntry,
      'a code-review pass ran but its Tuning entry is missing from the review file',
      missing,
    );
  }
  return const TuningResult(
    TuningVerdict.satisfied,
    'every added review has a Tuning entry',
    [],
  );
}
