// scripts/batch_close_lib.dart
//
// PURE predicate behind the Stop hook scripts/batch_close_hook.dart.
//
// WHY A STOP HOOK AND NOT A GATE. CLAUDE.md §5 is a checklist the agent "MUST
// consider" at the end of every batch. On 2026-08-25 an audit of a three-part
// batch found FOUR §5 rows unwalked — the skill tuning history, the feedback
// memory, the CLAUDE.md rows, and an unstated full-suite scope — and none of
// them surfaced until founder asked directly whether discipline had been
// followed. Every row backed by a gate held; every row backed by intention
// decayed. That is the same sentence §4.13 point 6 already writes about
// worktree retirement.
//
// The three wired hook events (SessionStart, UserPromptSubmit, PreToolUse) all
// fire BEFORE work. Nothing fired at the END of a batch, which is precisely
// where §5 lives. A pre-commit gate cannot cover it either: the rows are about
// the batch as a whole, and several of their artifacts live OUTSIDE the repo in
// the harness memory directory, which no in-repo gate can see.
//
// WHAT THIS ENFORCES, precisely: not that the rows were DONE — that is not
// mechanically knowable — but that they were ANSWERED. It converts a checklist
// nobody is obliged to read into one interaction that must happen. Same trust
// model as rule 21's `presence_only:` and rule 24's ledger: the structure is
// forced, the content is self-attested.

/// Which commit range describes THIS batch.
///
/// ⚠ `origin/main..HEAD` ALONE IS WRONG HERE, and the B-pass proved it live in
/// this repo: local `main` was **7** commits ahead of `origin/main` (three
/// earlier batches merged but not yet pushed) while the batch under review was
/// **2**. The hook reported "9 unpushed", and — far worse — every DERIVED row
/// was computed over the wrong range: it picked up another batch's
/// `docs/reviews/*.md` and marked the skill-tuning row satisfied, matched
/// another batch's `fix(...)` subjects, and anchored the retrospective
/// freshness check to an unrelated commit's date. Three rows reported green on
/// evidence belonging to somebody else's work.
///
/// CLAUDE.md §4.13 point 1 documents merged-but-unpushed as **the common state**
/// for this repo, and `new-worktree.sh:65-91` already solved this exact
/// range-selection problem with `merge-base --is-ancestor`. This hook reinvented
/// range detection and did not carry that fix across — the textbook
/// guard-without-its-mirror shape, and the third instance of it in this batch.
///
/// The rule: prefer the TIGHTEST range that still describes the batch.
///   - on a feature branch  -> `main..HEAD` (this branch's own commits)
///   - on `main` post-merge -> `main..HEAD` is empty, so `origin/main..HEAD`
///   - neither resolvable   -> null, meaning UNKNOWN (see [BatchCloseInputs])
String? chooseRange({
  required bool mainExists,
  required int commitsNotInMain,
  required bool originMainExists,
}) {
  if (mainExists && commitsNotInMain > 0) return 'main..HEAD';
  if (originMainExists) return 'origin/main..HEAD';
  return null;
}

/// The PRIMARY repo root, parsed from `git rev-parse --path-format=absolute
/// --git-common-dir`.
///
/// EXTRACTED so it can be tested. It was inline in the hook, and round 1 of this
/// batch's review proved the consequence: reverting it to the original
/// `--show-toplevel` bug reddened ZERO tests, while the commit message claimed
/// it was "pinned by the e2e". A function no test can reach is a function no
/// test protects — the same lesson `gatherHoldRows` taught one batch earlier.
///
/// ⚠ `--show-toplevel` is WRONG here and must not come back: in a linked
/// worktree it returns the WORKTREE path, and §4.13 makes every session work in
/// one, so the derived harness directory never matched and every batch was
/// reported UNVERIFIED.
String? primaryRootFrom(String? gitCommonDirOutput) {
  final raw = gitCommonDirOutput?.trim();
  if (raw == null || raw.isEmpty) return null;
  final norm = raw.replaceAll(RegExp(r'[\\]'), '/');
  final idx = norm.lastIndexOf('/.git');
  if (idx <= 0) return null;
  return norm.substring(0, idx);
}

/// The harness's directory name for a repo path.
///
/// Colon, separators and spaces each become ONE dash. ⚠ NO `-+` collapse: the
/// harness keeps the DOUBLE dash that a drive colon plus its separator produce
/// (`C:/Upendra` -> `C--Upendra`). Collapsing yielded `C-Upendra-…`, which does
/// not exist, so the lookup returned null and every batch read UNVERIFIED.
/// Verified against this machine's real directory name.
String mangleProjectPath(String root) =>
    root.replaceAll(RegExp(r'[:\\/ ]'), '-');

/// One §5 row the hook reports, with whatever the hook could establish itself.
class ChecklistRow {
  final String label;

  /// What the hook determined mechanically, or null when it could not tell.
  /// Null is NOT "fine" — it is printed as UNVERIFIED so the difference between
  /// "checked and clean" and "could not check" never collapses. That collapse is
  /// the bad-news-vs-no-news class this repo has hit twice.
  final bool? satisfied;

  /// Shown to the agent — what to do, or why the hook cannot answer.
  final String detail;

  const ChecklistRow(this.label, this.satisfied, this.detail);
}

class BatchCloseVerdict {
  /// True when the hook should block and hand [rows] back to the agent.
  final bool shouldBlock;
  final String reason;
  final List<ChecklistRow> rows;
  const BatchCloseVerdict(this.shouldBlock, this.reason, this.rows);
}

/// Inputs the hook gathers from the world, kept separate so the decision is pure.
class BatchCloseInputs {
  /// Commits on HEAD not on the upstream/mainline ref. 0 ⇒ nothing landed.
  final int unpushedCommits;

  /// Current HEAD sha, or null when git could not answer.
  final String? headSha;

  /// The sha this hook last reported on. Equal to [headSha] ⇒ already reported,
  /// so stay silent. This is what bounds the hook to ONE interruption per batch
  /// state rather than one per conversational turn.
  final String? lastReportedSha;

  /// True when the harness says a Stop hook is already driving the loop.
  /// MUST short-circuit — otherwise blocking on Stop re-triggers Stop forever.
  final bool stopHookActive;

  /// True when the operator kill switch file exists.
  final bool killSwitch;

  /// Newest mtime among the harness memory dir's `project_*.md`, or null when
  /// the directory could not be located. Null ⇒ UNVERIFIED, never "missing".
  final DateTime? newestRetrospective;

  /// Author date of the OLDEST unpushed commit — the batch's start.
  final DateTime? oldestUnpushedAt;

  /// Paths the unpushed range added under `docs/reviews/`.
  final List<String> reviewsAdded;

  /// True when any unpushed commit subject matches the bugfix prefixes.
  final bool hasBugfixCommit;

  const BatchCloseInputs({
    required this.unpushedCommits,
    required this.headSha,
    required this.lastReportedSha,
    required this.stopHookActive,
    required this.killSwitch,
    required this.newestRetrospective,
    required this.oldestUnpushedAt,
    required this.reviewsAdded,
    required this.hasBugfixCommit,
  });
}

/// The decision. Ordered so the cheapest, most absolute silencers come first.
BatchCloseVerdict evaluateBatchClose(BatchCloseInputs i) {
  const quiet = <ChecklistRow>[];

  // 1. NEVER loop. The harness sets this when a Stop hook already blocked once.
  if (i.stopHookActive) {
    return const BatchCloseVerdict(
        false, 'stop hook already active — never re-block', quiet);
  }
  // 2. Operator kill switch.
  if (i.killSwitch) {
    return const BatchCloseVerdict(false, 'kill switch present', quiet);
  }
  // 3. Nothing landed ⇒ no batch to close. The overwhelmingly common case, and
  //    the reason this hook is silent during ordinary conversation.
  if (i.unpushedCommits == 0) {
    return const BatchCloseVerdict(false, 'no unpushed commits', quiet);
  }
  // 4. Git could not answer ⇒ fail OPEN, exactly like every other gate here.
  if (i.headSha == null) {
    return const BatchCloseVerdict(
        false, 'git unavailable — failing OPEN', quiet);
  }
  // 5. Already reported for this exact state. Bounds the hook to one
  //    interruption per HEAD, not one per turn.
  if (i.lastReportedSha != null && i.lastReportedSha == i.headSha) {
    return const BatchCloseVerdict(
        false, 'already reported for this HEAD', quiet);
  }

  final rows = <ChecklistRow>[];

  // Retrospective — the row that actually decayed, and the only one whose
  // artifact lives outside the repo.
  if (i.newestRetrospective == null || i.oldestUnpushedAt == null) {
    rows.add(const ChecklistRow(
      'project_*.md retrospective (§5)',
      null,
      'UNVERIFIED — could not locate the harness memory directory or date the '
      'batch. Answer it yourself; do not read this as satisfied.',
    ));
  } else {
    final fresh = i.newestRetrospective!.isAfter(i.oldestUnpushedAt!);
    rows.add(ChecklistRow(
      'project_*.md retrospective (§5)',
      fresh,
      fresh
          ? 'a retrospective was written after this batch began'
          : 'NO retrospective newer than the oldest unpushed commit',
    ));
  }

  // Skill self-evolution — pre-commit already blocks the code-review case, so
  // this row exists to prompt the WIDER question §5.1 asks (any skill, any new
  // bug-class), which no gate can see.
  rows.add(ChecklistRow(
    'Skill self-evolution (§5.1)',
    i.reviewsAdded.isEmpty ? null : true,
    i.reviewsAdded.isEmpty
        ? 'UNVERIFIED — no review added, but §5.1 also covers a NEW bug-class, '
            'red flag or trigger phrase in ANY skill. Only you can answer that.'
        : 'code-review tuning entry enforced by check_skill_tuning_history; '
            'still consider whether any OTHER skill needs an entry',
  ));

  // Rows no script can determine. Listed so they are ANSWERED, not assumed.
  rows.add(const ChecklistRow(
    'CLAUDE.md / nested CLAUDE.md (§5)',
    null,
    'UNVERIFIED by construction — "did a contract change?" is a judgement. '
    'State your answer explicitly, including "no update needed".',
  ));
  rows.add(const ChecklistRow(
    'Worktree retirement (§4.13 point 6)',
    null,
    'UNVERIFIED — run `dart run scripts/retire_worktree.dart` (dry-run) from '
    'the PRIMARY worktree. This checklist row IS the trigger; nothing else fires it.',
  ));
  if (i.hasBugfixCommit) {
    rows.add(const ChecklistRow(
      'feedback_*.md for a recurring class (§5)',
      null,
      'UNVERIFIED — this batch carries a fix commit. If it repeated a known '
      'class, the class file needs the instance. Gates cannot see the memory dir.',
    ));
  }
  rows.add(const ChecklistRow(
    'Full-suite SCOPE stated (§4.3)',
    null,
    'UNVERIFIED — pre-push (>=account) and CI are the full-suite gates and '
    'neither has run on unpushed commits. If you report tests green, say WHICH.',
  ));

  return BatchCloseVerdict(
    true,
    '${i.unpushedCommits} unpushed commit(s) — walk the §5 close-out before '
    'ending the turn',
    rows,
  );
}

/// The message handed back to the agent when blocking.
String renderBlockReason(BatchCloseVerdict v) {
  final b = StringBuffer()
    ..writeln('BATCH CLOSE-OUT (CLAUDE.md §5) — ${v.reason}.')
    ..writeln('')
    ..writeln('This fires ONCE per HEAD, not per turn. Answer each row out loud;')
    ..writeln('"no update needed" is a valid answer, silence is not.')
    ..writeln('');
  for (final r in v.rows) {
    final mark = r.satisfied == null
        ? '[?]'
        : (r.satisfied! ? '[x]' : '[ ]');
    b.writeln('$mark ${r.label}');
    b.writeln('      ${r.detail}');
  }
  b
    ..writeln('')
    ..writeln('Kill switch: .claude/.batch_close.disabled');
  return b.toString();
}
