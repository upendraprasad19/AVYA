// Pure query/classification core for GitHub Actions run lookups.
//
// No I/O of its own: every function takes an injected [GhRunLister], so the
// whole file is unit-testable with canned JSON and no network. The real
// `gh` shell-out lives in the caller (scripts/reconcile_ci.dart).
//
// This is the FIRST shared implementation of the `gh run list --json
// headSha,conclusion,...` idiom, which is otherwise copy-pasted inline in
// .claude/commands/build-apk.md (Gate 3.5 and the --from-green fast path).
// Migrating those two is OI-107 — deliberately not done here, because Gate 3.5
// gates every APK release and this tool only warns.

import 'dart:convert';

/// Coarse classification of a run's `conclusion` field.
enum ConclusionClass {
  /// The run finished and passed.
  success,

  /// The run finished and did NOT pass — includes cancelled and timed_out,
  /// because from a "did my push verify" standpoint they are all
  /// "no green result", and a cancelled run is exactly how a CI timeout
  /// presents (feedback_local_ci_env_divergence: cancelled != failure when
  /// diagnosing, but both mean unverified here).
  failure,

  /// Queued, in progress, or no conclusion recorded yet.
  pending,
}

/// Maps a raw `conclusion` string to its class.
///
/// A null/empty conclusion means the run exists but has not finished, which is
/// [ConclusionClass.pending] — NOT a failure. Anything unrecognised is treated
/// as pending rather than failure: inventing a red result from a string we do
/// not understand would cry wolf.
ConclusionClass classifyConclusion(String? conclusion) {
  switch (conclusion?.trim().toLowerCase()) {
    case 'success':
      return ConclusionClass.success;
    case 'failure':
    case 'cancelled':
    case 'canceled':
    case 'timed_out':
    case 'startup_failure':
      return ConclusionClass.failure;
    default:
      return ConclusionClass.pending;
  }
}

/// Runs a `gh` subcommand and returns its parsed JSON rows, or `null` if the
/// lookup could not be performed at all.
///
/// The null-vs-empty distinction is load-bearing:
///   `[]`   — gh ran, answered, and there are no matching runs.
///   `null` — gh could not be asked (missing, unauthenticated, network down,
///            unparseable output). This is NOT evidence about any run.
///
/// Implementations should prefer returning `null` to throwing, but
/// [queryLatestRunForSha] treats a thrown exception as `null` too, so a lister
/// that throws is handled rather than fatal.
typedef GhRunLister = List<Map<String, dynamic>>? Function(List<String> args);

/// The result of looking up one SHA's most recent workflow run.
class GhRunQueryResult {
  /// True when a run for this SHA was located and its conclusion read.
  final bool found;

  /// True when the lookup itself could not be performed — `gh` missing,
  /// unauthenticated, an expired token, network down, unparseable output.
  ///
  /// SEPARATE from `found: false`, and the separation is the entire point.
  /// "No run exists for this SHA" and "I could not ask" are opposite claims:
  /// the first justifies telling the user CI never ran, the second means we
  /// know nothing at all. Collapsing them is exactly the defect this batch's
  /// sibling fix removed from `safe_push.sh` a day earlier — an empty
  /// `ls-remote` meaning both "ref absent" and "probe unreachable". Found by
  /// the B-pass, which ran the real script with `gh` stripped from PATH and
  /// got a confident, wrong "check whether Actions is enabled" out of it.
  final bool lookupFailed;

  final ConclusionClass conclusion;
  final String? rawConclusion;
  final String? url;
  final int? runId;

  const GhRunQueryResult({
    required this.found,
    this.lookupFailed = false,
    this.conclusion = ConclusionClass.pending,
    this.rawConclusion,
    this.url,
    this.runId,
  });

  /// The lookup succeeded and there is genuinely no run for this SHA.
  static const notFound = GhRunQueryResult(found: false);

  /// The lookup could not be performed. Says nothing about whether a run exists.
  static const unavailable =
      GhRunQueryResult(found: false, lookupFailed: true);
}

/// Finds the most recent workflow run for [sha] on [branch].
///
/// Ordering is NOT left to `gh`: `gh run list` documents no sort guarantee, and
/// a re-run produces several runs for one SHA. We request `createdAt` and sort
/// on it descending, so "latest" in the method name is something the code
/// actually enforces. (build-apk.md:357-358 relies on gh's default order today;
/// not repeating that here.)
GhRunQueryResult queryLatestRunForSha({
  required String workflow,
  required String branch,
  required String sha,
  required GhRunLister lister,
  int limit = 20,
}) {
  List<Map<String, dynamic>>? rows;
  try {
    rows = lister([
      'run',
      'list',
      '--branch',
      branch,
      '--workflow',
      workflow,
      '--limit',
      '$limit',
      '--json',
      'headSha,conclusion,status,url,databaseId,createdAt',
    ]);
  } catch (_) {
    rows = null;
  }

  // Could not ask. Says nothing about whether a run exists — must not be
  // reported as "CI never ran".
  if (rows == null) return GhRunQueryResult.unavailable;

  final matches = rows.where((r) => r['headSha'] == sha).toList();
  if (matches.isEmpty) return GhRunQueryResult.notFound;

  matches.sort((a, b) {
    final av = _createdAtKey(a);
    final bv = _createdAtKey(b);
    return bv.compareTo(av); // newest first
  });

  final latest = matches.first;
  final raw = latest['conclusion'] as String?;
  return GhRunQueryResult(
    found: true,
    conclusion: classifyConclusion(raw),
    rawConclusion: raw,
    url: latest['url'] as String?,
    runId: (latest['databaseId'] as num?)?.toInt(),
  );
}

/// Sort key for a run's creation time.
///
/// Falls back to the empty string when `createdAt` is missing or unparseable,
/// which sorts such rows last — a row we cannot date should never win the
/// "latest" slot over one we can.
String _createdAtKey(Map<String, dynamic> row) {
  final v = row['createdAt'];
  if (v is! String) return '';
  // ISO8601 UTC timestamps from the GitHub API sort correctly as strings.
  return v;
}

/// Names of the jobs that did not succeed in [runId], for the warning detail.
///
/// Only called once a run is already known to have failed, so the extra `gh`
/// round-trip is paid on the rare path, never the common one.
List<String> fetchFailingJobNames({
  required int runId,
  required GhRunLister lister,
}) {
  try {
    final rows = lister(['run', 'view', '$runId', '--json', 'jobs']);
    if (rows == null || rows.isEmpty) return const [];
    final jobs = rows.first['jobs'];
    if (jobs is! List) return const [];
    return jobs
        .whereType<Map>()
        .where((j) => classifyConclusion(j['conclusion'] as String?) ==
            ConclusionClass.failure)
        .map((j) => (j['name'] ?? '?').toString())
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Parses `gh --json` stdout into the row list a [GhRunLister] must return.
///
/// `gh run list --json` emits a top-level array; `gh run view --json` emits a
/// single object. Both are normalised to a list here so callers have one shape.
/// Returns an empty list rather than throwing on anything unexpected.
List<Map<String, dynamic>> parseGhJson(String stdout) {
  if (stdout.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(stdout);
    if (decoded is List) {
      return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
    }
    if (decoded is Map) return [Map<String, dynamic>.from(decoded)];
    return const [];
  } catch (_) {
    return const [];
  }
}
