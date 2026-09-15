// Pure state logic for the post-push CI reconciler.
//
// No file or network I/O — every function here takes its inputs as values, so
// the whole file is unit-testable without a repo, a temp dir, or `gh`.
// The orchestrator that does the actual I/O is scripts/reconcile_ci.dart.
//
// State file: .claude/.ci_reconcile_pending.jsonl (gitignored), one JSON object
// per line, appended by scripts/arm_ci_reconcile.sh on a landed push.

import 'dart:convert';

import 'gh_run_lib.dart';

/// Branches whose pushes actually trigger CI.
///
/// Must match `.github/workflows/test.yml`'s `on.push.branches`. If that list
/// ever changes, this one has to change with it — nothing detects the drift
/// automatically, so it is stated here in one place rather than inline at the
/// use site.
const ciTriggeringBranches = {'main', 'develop'};

/// A push that landed and whose CI outcome has not been established yet.
class PendingEntry {
  final String branch;
  final String sha;
  final DateTime armedAt;

  const PendingEntry({
    required this.branch,
    required this.sha,
    required this.armedAt,
  });

  /// Identity of the thing being reconciled. A branch alone is NOT the
  /// identity: a rebase-and-repush puts a second, different SHA on the same
  /// branch, and each has its own CI run to account for.
  String get key => '$branch@$sha';

  Map<String, dynamic> toJson() => {
        'branch': branch,
        'sha': sha,
        'armed_at': armedAt.toIso8601String(),
      };

  static PendingEntry? tryFromJson(Map<String, dynamic> m) {
    final branch = m['branch'];
    final sha = m['sha'];
    final armedAt = m['armed_at'];
    if (branch is! String || branch.isEmpty) return null;
    if (sha is! String || sha.isEmpty) return null;
    if (armedAt is! String) return null;
    final parsed = DateTime.tryParse(armedAt);
    if (parsed == null) return null;
    return PendingEntry(branch: branch, sha: sha, armedAt: parsed);
  }
}

/// What should happen to a pending entry after its CI outcome is looked up.
enum ReconcileAction {
  /// CI passed. Drop it, say nothing.
  resolvedSuccess,

  /// CI failed/cancelled/timed out. Warn, then drop — remediation is a new
  /// push, which arms a fresh entry, so carrying a dead red entry forward
  /// would repeat the same warning every session.
  resolvedFailure,

  /// Past the staleness bound with no run ever found, on a branch where CI
  /// was supposed to run. Warn, then drop.
  staleNeverRan,

  /// No verdict yet (queued, running, or the lookup failed), or past the bound
  /// on a branch where no run was ever expected. Keep waiting, say nothing.
  stillPending,

  /// Past the bound on a branch CI does not trigger on. Drop it silently —
  /// keeping it would grow the file forever waiting for a run that is never
  /// coming (ADR-0018: most branches get no CI until merged).
  staleExpected,
}

class ReconcileOutcome {
  final ReconcileAction action;
  final PendingEntry entry;
  final String? conclusion;
  final String? url;
  final int? runId;
  final int? ageHours;

  const ReconcileOutcome({
    required this.action,
    required this.entry,
    this.conclusion,
    this.url,
    this.runId,
    this.ageHours,
  });

  /// Whether this outcome produces user-visible output.
  bool get warns =>
      action == ReconcileAction.resolvedFailure ||
      action == ReconcileAction.staleNeverRan;

  /// Whether the entry stays in the state file for a later session.
  bool get keeps => action == ReconcileAction.stillPending;
}

/// Parses the JSONL state file.
///
/// Malformed lines are skipped, never fatal: this feeds a SessionStart hook,
/// and a half-written line from an interrupted append must not take the whole
/// session's output down with it.
List<PendingEntry> parsePendingEntries(String jsonl) {
  final out = <PendingEntry>[];
  for (final line in const LineSplitter().convert(jsonl)) {
    final t = line.trim();
    if (t.isEmpty) continue;
    try {
      final decoded = jsonDecode(t);
      if (decoded is! Map) continue;
      final entry = PendingEntry.tryFromJson(Map<String, dynamic>.from(decoded));
      if (entry != null) out.add(entry);
    } catch (_) {
      continue;
    }
  }
  return out;
}

String serializePendingEntries(List<PendingEntry> entries) {
  if (entries.isEmpty) return '';
  return '${entries.map((e) => jsonEncode(e.toJson())).join('\n')}\n';
}

/// Collapses repeat arms of the same `(branch, sha)`, keeping the earliest
/// `armedAt` so the staleness clock runs from the first landing, not the most
/// recent re-run of the arm script.
List<PendingEntry> dedupeKeepingEarliest(List<PendingEntry> entries) {
  final byKey = <String, PendingEntry>{};
  for (final e in entries) {
    final existing = byKey[e.key];
    if (existing == null || e.armedAt.isBefore(existing.armedAt)) {
      byKey[e.key] = e;
    }
  }
  return byKey.values.toList();
}

/// Folds entries that appeared on disk while this run was querying `gh` back
/// into the set about to be written.
///
/// [survivors] are the entries this run decided to keep. The merge adds ONLY
/// those [currentOnDisk] entries whose key was absent from [initialRead].
///
/// That restriction is the whole correctness argument. Merging everything
/// currently on disk instead would re-add every entry this run just resolved
/// and dropped — they are still physically in the file, since nothing has
/// rewritten it yet — turning classify-and-drop into a permanent no-op with no
/// concurrency required to trigger it. The two readings are not variants of the
/// same idea; one of them silently disables the tool.
List<PendingEntry> mergeConcurrentArrivals({
  required List<PendingEntry> initialRead,
  required List<PendingEntry> currentOnDisk,
  required List<PendingEntry> survivors,
}) {
  final seen = initialRead.map((e) => e.key).toSet();
  final merged = <PendingEntry>[...survivors];
  final survivorKeys = survivors.map((e) => e.key).toSet();
  for (final e in currentOnDisk) {
    if (seen.contains(e.key)) continue;
    if (survivorKeys.contains(e.key)) continue;
    merged.add(e);
    survivorKeys.add(e.key);
  }
  return merged;
}

/// Decides what to do with one pending entry given its CI lookup result.
///
/// [now] is injected so staleness is testable without waiting two days.
ReconcileOutcome classify({
  required PendingEntry entry,
  required GhRunQueryResult ghResult,
  required DateTime now,
  Duration staleBound = const Duration(hours: 48),
}) {
  if (ghResult.found) {
    switch (ghResult.conclusion) {
      case ConclusionClass.success:
        return ReconcileOutcome(
          action: ReconcileAction.resolvedSuccess,
          entry: entry,
        );
      case ConclusionClass.failure:
        return ReconcileOutcome(
          action: ReconcileAction.resolvedFailure,
          entry: entry,
          conclusion: ghResult.rawConclusion,
          url: ghResult.url,
          runId: ghResult.runId,
        );
      case ConclusionClass.pending:
        return ReconcileOutcome(
          action: ReconcileAction.stillPending,
          entry: entry,
        );
    }
  }

  // We could not ask. That is not evidence that CI never ran, however old the
  // entry is — keep waiting and say nothing about THIS entry. The orchestrator
  // reports the broken lookup once, globally, which is the honest message.
  if (ghResult.lookupFailed) {
    return ReconcileOutcome(
      action: ReconcileAction.stillPending,
      entry: entry,
    );
  }

  final age = now.difference(entry.armedAt);
  if (age <= staleBound) {
    return ReconcileOutcome(
      action: ReconcileAction.stillPending,
      entry: entry,
    );
  }

  // Past the bound with no run ever found. Whether that is worth saying
  // depends entirely on whether a run was ever going to happen.
  if (!ciTriggeringBranches.contains(entry.branch)) {
    return ReconcileOutcome(
      action: ReconcileAction.staleExpected,
      entry: entry,
      ageHours: age.inHours,
    );
  }
  return ReconcileOutcome(
    action: ReconcileAction.staleNeverRan,
    entry: entry,
    ageHours: age.inHours,
  );
}
