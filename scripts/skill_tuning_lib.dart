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

  const ReviewClaim(this.path, this.reviewedOn);
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

/// `YYYY-MM-DD` out of a `reviewed_at:` frontmatter line, or null.
///
/// Line-anchored on purpose. `docs/plan-reviews/` records are parsed the same
/// way by the keystone gate, and a session already lost a CI run to a bullet
/// header that the anchored parser read as null
/// (feedback_plan_review_record_frontmatter_format). Matching mid-line would
/// let prose mentioning "reviewed_at" satisfy the parse.
String? reviewedOnFrom(String markdown) {
  for (final raw in markdown.split('\n')) {
    final line = raw.trimRight();
    if (!line.startsWith('reviewed_at:')) continue;
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(line);
    if (m == null) return null;
    return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
  }
  return null;
}

/// True when [skillMarkdown] has a tuning-history bullet dated [isoDate].
///
/// The accepted shape is the one every existing entry already uses:
/// `- **YYYY-MM-DD** — blast-radius …`. Deliberately NOT a bare
/// `contains(isoDate)`: the date also appears in prose inside older entries
/// (one entry cites "2026-08-17" while describing a different batch), so a
/// substring test would let a NEW review be satisfied by an OLD entry's prose.
/// That is the input-set-width trap this repo files under
/// feedback_green_check_input_set_width — a check answering a narrower question
/// than the one being asked.
bool hasTuningEntryFor(String skillMarkdown, String isoDate) {
  final pattern = RegExp(
    r'^\s*[-*]\s+\*\*' + RegExp.escape(isoDate) + r'\*\*',
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
  final header = RegExp(r'^\s*[-*]\s+\*\*' + RegExp.escape(isoDate) + r'\*\*');
  final anyDatedHeader = RegExp(r'^\s*[-*]\s+\*\*\d{4}-\d{2}-\d{2}\*\*');

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

/// Decide, given the reviews this commit ADDS and the skill file's content.
///
/// [skillMarkdown] is null when the skill file could not be read — that is an
/// UNDETERMINED, not a failure. A gate that cannot read its own input must not
/// block a commit; the repo's other gates (`check_oi_numbering_unique`,
/// `check_worktree_config_integrity`) fail open for the same reason.
TuningResult evaluateTuning({
  required List<ReviewClaim> addedReviews,
  required String? skillMarkdown,
}) {
  if (addedReviews.isEmpty) {
    return const TuningResult(
        TuningVerdict.notApplicable, 'no review file added by this commit');
  }
  if (skillMarkdown == null) {
    return const TuningResult(TuningVerdict.undetermined,
        'could not read .claude/skills/code-review/SKILL.md — failing OPEN');
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
    // Date AND identity. A same-dated entry about a DIFFERENT review does not
    // discharge this one — see hasTuningEntryForReview.
    if (!hasTuningEntryForReview(skillMarkdown, r.reviewedOn!, r.path)) {
      missing.add('${r.path} (reviewed_at ${r.reviewedOn})');
    }
  }
  if (missing.isNotEmpty) {
    return TuningResult(
      TuningVerdict.missingEntry,
      'a code-review pass ran but its Tuning history entry was not appended',
      missing,
    );
  }
  return TuningResult(
    TuningVerdict.satisfied,
    'every added review has a same-dated Tuning history entry',
    const [],
  );
}
