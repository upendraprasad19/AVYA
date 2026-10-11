// scripts/safe_pr_merge_lib.dart
//
// Pure decision core for scripts/safe_pr_merge.dart (the "merge a PR only when
// CI is green" wrapper). No I/O: every function takes already-fetched data, so
// the whole file is unit-testable with canned JSON.
//
// WHY THIS EXISTS (OI-275, docs/plans/2026-10-10-release-cycle-speedup.md B1).
// `main` has NO required status checks (strict:true, contexts:[]), and
// scripts/pre-push.sh no longer runs the ~39-minute local suite for a BRANCH
// push. Nothing server-side therefore stops a red PR from being merged; this
// wrapper is the compensating control. It must FAIL CLOSED: anything it cannot
// read, or any required job it cannot see green, is a refusal -- never a merge.
//
// The job-name lists below are EXACT strings copied from the `name:` fields of
// .github/workflows/test.yml (test/scripts/safe_pr_merge_lib_test.dart parses
// that file and fails if a required name stops existing, so a renamed job
// reddens a test instead of silently making every merge refuse or, worse,
// silently ignoring the job).

import 'dart:convert';

/// Jobs that MUST have concluded `success` on the PR head SHA.
const List<String> requiredSuccessJobs = <String>[
  'Analyze',
  'Unit Tests',
  'Deno Edge-Function tests',
  'Audit Gates',
  'Build Check (APK)',
];

/// Jobs that run only on a push to main (`if: github.event_name == 'push' &&
/// github.ref == 'refs/heads/main'`), so they are `skipped` on a pull_request
/// run. `success` or `skipped` both pass; failure/cancelled/pending refuse; a
/// missing check-run is tolerated (it is not a PR-time job).
const List<String> skippedOkJobs = <String>[
  'Plan-review record (>=account merge-to-main)',
  'Supabase Integration Tests',
];

/// Only check-runs created by GitHub Actions are judged. A real PR also carries
/// third-party checks (e.g. "Vercel Preview Comments", app slug `vercel`)
/// that say nothing about the test suite.
const String githubActionsSlug = 'github-actions';

/// The outcome of a safety evaluation.
class MergeDecision {
  const MergeDecision(this.ok, this.reasons, [this.warnings = const <String>[]]);

  /// True only when every condition for merging holds.
  final bool ok;

  /// Why it was refused (empty when [ok]).
  final List<String> reasons;

  /// Non-blocking notes (e.g. the PR is behind main).
  final List<String> warnings;
}

/// Splits `gh api --paginate` output -- which for an object response is the
/// pages' JSON texts concatenated back to back (`{...}{...}`) -- into decoded
/// values. A brace-depth scan that honours string literals and escapes; throws
/// [FormatException] on truncated or unbalanced input (the caller treats that
/// as "could not read", i.e. fail closed).
List<Object?> splitJsonValues(String raw) {
  final out = <Object?>[];
  var depth = 0;
  var inString = false;
  var escaped = false;
  var start = -1;
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '{' || c == '[') {
      if (depth == 0) start = i;
      depth++;
    } else if (c == '}' || c == ']') {
      depth--;
      if (depth < 0) throw const FormatException('unbalanced JSON (extra closer)');
      if (depth == 0) out.add(jsonDecode(raw.substring(start, i + 1)));
    }
  }
  if (depth != 0 || inString) throw const FormatException('truncated JSON');
  return out;
}

/// Flattens the `check_runs` arrays of every page in [raw] (the text printed by
/// `gh api repos/{repo}/commits/{sha}/check-runs --paginate`). Throws
/// [FormatException] when the shape is not the expected one.
List<Map<String, dynamic>> parseCheckRuns(String raw) {
  final pages = splitJsonValues(raw);
  if (pages.isEmpty) throw const FormatException('empty check-runs response');
  final runs = <Map<String, dynamic>>[];
  int? total;
  for (final page in pages) {
    if (page is! Map || page['check_runs'] is! List) {
      throw const FormatException('response page has no check_runs array');
    }
    if (page['total_count'] is int) total = page['total_count'] as int;
    for (final r in page['check_runs'] as List) {
      if (r is! Map) throw const FormatException('check_runs entry is not an object');
      runs.add(Map<String, dynamic>.from(r));
    }
  }
  // GitHub states how many check-runs exist; if we parsed fewer (a dropped or
  // duplicated page), some job may be missing from view -- never judge on that.
  if (total != null && total != runs.length) {
    throw FormatException('total_count is $total but ${runs.length} check-runs were parsed');
  }
  return runs;
}

/// Flattens the file list of `gh api repos/{repo}/pulls/{n}/files --paginate`
/// (pages of JSON arrays; each file object has `filename` and, for a rename,
/// `previous_filename`). Throws [FormatException] on any unexpected shape.
List<String> parseChangedFiles(String raw) {
  final pages = splitJsonValues(raw);
  if (pages.isEmpty) throw const FormatException('empty files response');
  final out = <String>[];
  for (final page in pages) {
    if (page is! List) throw const FormatException('files response page is not an array');
    for (final f in page) {
      if (f is! Map || f['filename'] is! String) {
        throw const FormatException('files entry has no filename');
      }
      out.add(f['filename'] as String);
      if (f['previous_filename'] is String) out.add(f['previous_filename'] as String);
    }
  }
  return out;
}

String _name(Map<String, dynamic> r) => (r['name'] ?? '').toString();
String? _conclusion(Map<String, dynamic> r) => r['conclusion']?.toString();
bool _completed(Map<String, dynamic> r) => r['status'] == 'completed';
int _id(Map<String, dynamic> r) => r['id'] is int ? r['id'] as int : 0;

/// Judges the GitHub-Actions check-runs of a PR head SHA. [runs] null means the
/// lookup itself failed -- NOT evidence the checks passed.
MergeDecision evaluateCheckRuns(List<Map<String, dynamic>>? runs) {
  if (runs == null) {
    return const MergeDecision(
        false, ['could not read the check-runs for the PR head (refusing: unknown is not green)']);
  }
  final actions = runs
      .where((r) => (r['app'] is Map ? (r['app'] as Map)['slug'] : null) == githubActionsSlug)
      .toList();
  if (actions.isEmpty) {
    return const MergeDecision(false, [
      'no GitHub Actions check-runs exist for the PR head SHA (CI has not run on this '
          'commit yet, or the PR is conflicted and never got a run)'
    ]);
  }

  // Latest non-cancelled check-run per job name; a name that has ONLY cancelled
  // runs is tracked separately (a superseded run followed by a good one is fine,
  // a lone cancelled run is not a result).
  final latest = <String, Map<String, dynamic>>{};
  final onlyCancelled = <String>{};
  for (final r in actions) {
    final n = _name(r);
    if (_completed(r) && _conclusion(r) == 'cancelled') {
      if (!latest.containsKey(n)) onlyCancelled.add(n);
      continue;
    }
    onlyCancelled.remove(n);
    final cur = latest[n];
    if (cur == null || _id(r) > _id(cur)) latest[n] = r;
  }

  final reasons = <String>[];

  String describe(Map<String, dynamic> r) =>
      _completed(r) ? 'concluded ${_conclusion(r)}' : 'is ${r['status']} (not finished)';

  for (final n in requiredSuccessJobs) {
    final r = latest[n];
    if (r == null) {
      reasons.add(onlyCancelled.contains(n)
          ? '"$n" has only cancelled runs'
          : '"$n" has no check-run (required)');
    } else if (!_completed(r) || _conclusion(r) != 'success') {
      reasons.add('"$n" ${describe(r)} (required: success)');
    }
  }

  for (final n in skippedOkJobs) {
    final r = latest[n];
    if (r == null) continue; // push-only job; absence is not a PR-time failure
    if (!_completed(r) || (_conclusion(r) != 'success' && _conclusion(r) != 'skipped')) {
      reasons.add('"$n" ${describe(r)} (allowed: success or skipped)');
    }
  }

  // Any OTHER GitHub-Actions check (a matrix shard, a job added later) must not
  // be red or still running either -- the five names above are a floor, not a
  // ceiling.
  for (final entry in latest.entries) {
    final n = entry.key;
    if (requiredSuccessJobs.contains(n) || skippedOkJobs.contains(n)) continue;
    final r = entry.value;
    final c = _conclusion(r);
    final fine = _completed(r) && (c == 'success' || c == 'skipped' || c == 'neutral');
    if (!fine) reasons.add('"$n" ${describe(r)}');
  }
  // The mirror of the required-job rule above: an unlisted job (a matrix shard, a
  // job added later) whose ONLY runs were cancelled -- a timed-out job is reported
  // as cancelled -- is not a result either. `latest` excludes cancelled runs, so
  // the loop above never sees such a job; without this it would be ignored.
  for (final n in onlyCancelled) {
    if (requiredSuccessJobs.contains(n) || skippedOkJobs.contains(n)) continue;
    reasons.add('"$n" has only cancelled runs');
  }

  return MergeDecision(reasons.isEmpty, reasons);
}

/// CI configuration paths. A pull_request run executes the PR's OWN version of
/// `.github/workflows/test.yml`, so a PR that edits it can make a required job
/// green without proving anything. Merging such a PR needs a deliberate
/// acknowledgement (`--allow-workflow-change`) after its diff has been read.
bool isCiConfigPath(String path) => path.startsWith('.github/');

/// Judges the changed-file list. [files] null (unreadable) refuses.
MergeDecision evaluateChangedFiles(List<String>? files, {required bool allowWorkflowChange}) {
  if (files == null) {
    return const MergeDecision(
        false, ['could not read the PR\'s changed files (refusing: unknown is not safe)']);
  }
  final ci = files.where(isCiConfigPath).toSet().toList()..sort();
  if (ci.isEmpty) return const MergeDecision(true, []);
  const why = 'the green checks ran THIS PR\'s own version of the workflow, so they may prove '
      'nothing about the jobs they cover. Read the .github/ diff, then re-run with '
      '--allow-workflow-change.';
  if (!allowWorkflowChange) {
    return MergeDecision(false, ['the PR changes CI configuration (${ci.join(', ')}): $why']);
  }
  return MergeDecision(true, const [], ['merging with --allow-workflow-change; the PR edits ${ci.join(', ')}']);
}

/// Judges the PR object (`gh pr view --json state,isDraft,headRefOid,mergeable,
/// mergeStateStatus,baseRefName`). Returns the decision AND is told the head SHA
/// the check-runs were read for, so a head that moved between the two reads is
/// refused here (GitHub re-checks via `--match-head-commit` at merge time too).
MergeDecision evaluatePr(Map<String, dynamic>? pr, {required String checkedSha}) {
  if (pr == null) {
    return const MergeDecision(false, ['could not read the pull request']);
  }
  final reasons = <String>[];
  final warnings = <String>[];
  if (pr['state'] != 'OPEN') reasons.add('the PR is ${pr['state']}, not OPEN');
  if (pr['isDraft'] == true) reasons.add('the PR is a draft');
  // CI (.github/workflows/test.yml) triggers only for pull requests INTO main or
  // develop; a PR into anything else has no check-runs to judge.
  if (pr['baseRefName'] != 'main' && pr['baseRefName'] != 'develop') {
    reasons.add('the PR targets "${pr['baseRefName']}", not main/develop: CI does not run for it');
  }
  if (pr['mergeable'] == 'CONFLICTING') reasons.add('the PR has merge conflicts');
  if (pr['headRefOid'] != checkedSha) {
    reasons.add('the PR head moved from $checkedSha to ${pr['headRefOid']} while checking');
  }
  if (pr['mergeStateStatus'] == 'BEHIND') {
    warnings.add('the PR is behind its base branch: the checks ran on an older merge '
        'base. Main CI re-runs in full on the merged tree; consider `gh pr update-branch`.');
  }
  return MergeDecision(reasons.isEmpty, reasons, warnings);
}

/// Combines the PR and check-run decisions.
MergeDecision combine(MergeDecision a, MergeDecision b) => MergeDecision(
    a.ok && b.ok, [...a.reasons, ...b.reasons], [...a.warnings, ...b.warnings]);
