// scripts/context_budget_lib.dart
//
// Pure logic for `check_context_artifact_budget.dart`. No dart:io, so every
// branch is unit-testable without a fixture repo.
//
// WHY THIS EXISTS. The repo already guards the size of the artifact USERS
// download (`check_apk_size_within_bounds.dart`, Gate 13: recorded baseline,
// ±10% band, `--record` to re-baseline). Nothing guarded the artifacts the
// AGENT loads on every session, and they drifted badly before anyone measured:
//
//   docs/audit/open_issues.md   67,895 -> 357,664 B in 30 days (~+3,200 tok/day)
//   docs/audit/OPEN_INDEX.md     3,759 ->  18,958 B, while CLAUDE.md §7 still
//                                advertised it as "~950 tokens" — a claim that
//                                was TRUE when written (`e4bc9040`, 2026-07-29)
//                                and that nothing re-derived.
//
// Four independent reasons nothing caught it, all worth keeping in view because
// they say what this gate is FOR:
//   1. Every review is diff-scoped (`/code-review` reads `git diff --cached`;
//      blast-radius classifies a diff). Each commit added ~3 KB and was
//      individually innocent. CLAUDE.md:477 already records this exact lesson
//      for `check_no_deferral_euphemism` and it was never generalised.
//   2. `docs/audit/LENS_REGISTRY.md` had 53 lenses (L1–L53) and none about
//      artifact size, and §4.8 makes an audit declare its lenses in scope — so
//      it could not be found. Closed by L54, added with this gate.
//   3. The tech-debt audit's Documentation pass asks whether docs are CORRECT,
//      not whether they are AFFORDABLE.
//   4. The one size gate in the repo pointed at the other artifact class.
//
// This is a CUMULATIVE check, not a diff check — that is the entire point, and
// it is why it reads the working tree rather than the staged diff.

/// What a single artifact's measurement came to.
enum BudgetStatus {
  /// Within the soft band, or smaller than baseline. Nothing to say.
  ok,

  /// Past the soft band. Reported loudly; NEVER blocks a commit.
  warn,

  /// Past the hard band. Blocks.
  fail,

  /// Could not be measured, or has no baseline yet. Reported as SKIPPED, never
  /// as PASS — an unaskable question and a satisfied one must not look alike
  /// (`feedback_bad_news_vs_no_news`: a gate whose "clean" and "couldn't check"
  /// render identically is the bug, not the reporting of it).
  skipped,
}

class BudgetFinding {
  final String path;
  final BudgetStatus status;

  /// Recorded baseline in bytes, or null when there is none.
  final int? baseline;

  /// Measured size in bytes, or null when the file could not be read.
  final int? actual;

  /// Growth as a fraction of baseline (0.25 == +25%). Null unless both sizes
  /// are known.
  final double? drift;

  /// Why, when [status] is [BudgetStatus.skipped].
  final String? reason;

  const BudgetFinding({
    required this.path,
    required this.status,
    this.baseline,
    this.actual,
    this.drift,
    this.reason,
  });

  /// `+18.4%` / `-3.0%` / `n/a`.
  String get driftLabel => drift == null
      ? 'n/a'
      : '${drift! >= 0 ? '+' : ''}${(drift! * 100).toStringAsFixed(1)}%';
}

/// Default bands.
///
/// TWO bands, not one, and the split is deliberate. A single hard band forces a
/// choice between "blocks legitimate work" and "says nothing": `open_issues.md`
/// legitimately grows every time an issue is filed, so a tight hard band would
/// ship-stop ordinary work for a hygiene problem — the same error class as the
/// 2026-07-25/26 required-status-checks incident, and the reason §4.13 point 6
/// deliberately left worktree retirement ungated.
///
/// So: [softBand] is where a human should look, and it never blocks. [hardBand]
/// is growth no one does by accident — the drift this gate was born from was
/// **+427%**, an order of magnitude past it.
const double kSoftBand = 0.15;
const double kHardBand = 0.50;

/// Evaluate one artifact.
///
/// [actual] null means unreadable; [baseline] null means unrecorded. Both are
/// [BudgetStatus.skipped] — FAIL OPEN. A gate that wedges every commit because a
/// file moved is worse than the drift it watches for.
BudgetFinding evaluateOne(
  String path, {
  required int? baseline,
  required int? actual,
  double softBand = kSoftBand,
  double hardBand = kHardBand,
}) {
  if (actual == null) {
    return BudgetFinding(
      path: path,
      status: BudgetStatus.skipped,
      baseline: baseline,
      reason: 'not readable',
    );
  }
  if (baseline == null) {
    return BudgetFinding(
      path: path,
      status: BudgetStatus.skipped,
      actual: actual,
      reason: 'no baseline recorded — run with --record',
    );
  }
  if (baseline <= 0) {
    return BudgetFinding(
      path: path,
      status: BudgetStatus.skipped,
      baseline: baseline,
      actual: actual,
      reason: 'baseline is not a positive size',
    );
  }

  final drift = (actual - baseline) / baseline;
  // Shrinking is always fine, and is the point of the batch that added this.
  final status = drift > hardBand
      ? BudgetStatus.fail
      : drift > softBand
          ? BudgetStatus.warn
          : BudgetStatus.ok;

  return BudgetFinding(
    path: path,
    status: status,
    baseline: baseline,
    actual: actual,
    drift: drift,
  );
}

/// Evaluate every tracked artifact. [actuals] carries null for unreadable files.
List<BudgetFinding> evaluateAll(
  Map<String, int> baselines,
  Map<String, int?> actuals, {
  double softBand = kSoftBand,
  double hardBand = kHardBand,
}) {
  // Union of both key sets: an artifact present in the tree but absent from the
  // baseline must still be REPORTED (as skipped), or adding a new always-loaded
  // doc would silently escape the budget forever.
  final paths = <String>{...baselines.keys, ...actuals.keys}.toList()..sort();
  return [
    for (final p in paths)
      evaluateOne(
        p,
        baseline: baselines[p],
        actual: actuals[p],
        softBand: softBand,
        hardBand: hardBand,
      )
  ];
}

/// True when at least one finding is [BudgetStatus.fail] — the only condition
/// that blocks. Warnings and skips never do.
bool anyBlocking(List<BudgetFinding> findings) =>
    findings.any((f) => f.status == BudgetStatus.fail);

/// ~tokens for [bytes], at the ~3.6 chars/token this repo's prose measures.
/// Approximate ON PURPOSE and never used for a pass/fail decision — the bands
/// compare bytes. It exists so the report speaks in the unit the reader budgets
/// in, since "18,958 bytes" does not tell anyone what it costs to read.
int approxTokens(int bytes) => bytes * 10 ~/ 36;
