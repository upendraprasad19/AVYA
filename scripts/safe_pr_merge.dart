// scripts/safe_pr_merge.dart -- merge a pull request ONLY when CI is green.
//
//   sh scripts/safe_pr_merge.sh <pr-number> [--allow-workflow-change]   (the sanctioned entry point)
//   dart scripts/safe_pr_merge.dart <pr-number> [--dry-run] [--allow-workflow-change] [--gh "<cmd>"]
//
// `main` has no required status checks, and pre-push no longer runs the local
// full suite for a branch push (OI-275). This script reads the GitHub-Actions
// check-runs for the PR head SHA and merges (`gh pr merge --merge
// --match-head-commit <sha>`) only if every required job is green. It FAILS
// CLOSED: a `gh` error, unparseable output or zero check-runs is a refusal.
//
// Also refused: a PR into a branch other than main/develop (CI does not run for it), and
// a PR that edits .github/ (CI configuration) unless --allow-workflow-change is passed
// after reading that diff -- the green checks ran the PR's OWN workflow.
//
// Exit: 0 merged (state read back as MERGED, or --dry-run would merge) · 1 refused / could
// not verify · 2 usage error, or `gh pr merge` exited 0 but the PR is not MERGED.
//
// `--gh` exists so the tests can substitute a fake `gh` (a PATH stub cannot work
// on Windows: Process.run resolves gh.exe, not an extensionless script). The
// shell wrapper never forwards it: scripts/safe_pr_merge.sh passes ONLY the PR
// number, so the one sanctioned entry point cannot be pointed at a fake.
// NOTE: dart_bin ("dart scripts/x.dart", not "dart run") -- `dart run` prepends
// a "Running build hooks..." preamble to stdout.

import 'dart:convert';
import 'dart:io';

import 'safe_pr_merge_lib.dart';

class _Gh {
  _Gh(String cmd) {
    final parts = cmd.trim().split(RegExp(r'\s+'));
    _exe = parts.first;
    _prefix = parts.skip(1).toList();
  }
  late final String _exe;
  late final List<String> _prefix;

  /// Runs gh; returns stdout, or null on ANY failure (non-zero exit, spawn error).
  ({String? out, String err, int code}) run(List<String> args) {
    try {
      final r = Process.runSync(_exe, [..._prefix, ...args], runInShell: false);
      return (out: r.exitCode == 0 ? r.stdout.toString() : null, err: r.stderr.toString(), code: r.exitCode);
    } on ProcessException catch (e) {
      return (out: null, err: e.message, code: 127);
    }
  }
}

Map<String, dynamic>? _jsonObject(String? raw) {
  if (raw == null) return null;
  try {
    final v = jsonDecode(raw);
    return v is Map ? Map<String, dynamic>.from(v) : null;
  } on FormatException {
    return null;
  }
}

int _run(List<String> args) {
  String? pr;
  var dryRun = false;
  var allowWorkflowChange = false;
  var ghCmd = 'gh';
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--dry-run') {
      dryRun = true;
    } else if (a == '--allow-workflow-change') {
      allowWorkflowChange = true;
    } else if (a == '--gh' && i + 1 < args.length) {
      ghCmd = args[++i];
    } else if (pr == null && RegExp(r'^[0-9]+$').hasMatch(a)) {
      pr = a;
    } else {
      stderr.writeln('safe_pr_merge: unexpected argument "$a"');
      pr = null;
      break;
    }
  }
  if (pr == null) {
    stderr.writeln('usage: sh scripts/safe_pr_merge.sh <pr-number> [--allow-workflow-change]');
    return 2;
  }

  final gh = _Gh(ghCmd);

  final repoOut = gh.run(['repo', 'view', '--json', 'nameWithOwner']);
  final repo = _jsonObject(repoOut.out)?['nameWithOwner'];
  if (repo is! String || !RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(repo)) {
    stderr.writeln('safe_pr_merge: REFUSED -- could not determine the repository (gh: ${repoOut.err.trim()})');
    return 1;
  }

  const prFields = 'state,isDraft,headRefOid,mergeable,mergeStateStatus,baseRefName';
  final prObj = _jsonObject(gh.run(['pr', 'view', pr, '--json', prFields]).out);
  final sha = prObj?['headRefOid'];
  if (prObj == null || sha is! String || !RegExp(r'^[0-9a-f]{40}$').hasMatch(sha)) {
    stderr.writeln('safe_pr_merge: REFUSED -- could not read PR #$pr (head commit unknown)');
    return 1;
  }

  List<Map<String, dynamic>>? runs;
  final runsOut = gh.run(['api', 'repos/$repo/commits/$sha/check-runs', '--paginate']);
  if (runsOut.out != null) {
    try {
      runs = parseCheckRuns(runsOut.out!);
    } on FormatException catch (e) {
      stderr.writeln('safe_pr_merge: check-runs response unreadable: ${e.message}');
    }
  } else {
    stderr.writeln('safe_pr_merge: gh api failed: ${runsOut.err.trim()}');
  }

  // Re-read the PR AFTER the check-runs: the head could have moved while we were
  // looking, in which case the green we saw belongs to a commit that is no longer
  // the PR head. (`--match-head-commit` below closes the same window at merge time.)
  final prAfter = _jsonObject(gh.run(['pr', 'view', pr, '--json', prFields]).out);

  // The PR's changed files (paginated: `gh pr view --json files` is capped at 100).
  List<String>? files;
  final filesOut = gh.run(['api', 'repos/$repo/pulls/$pr/files', '--paginate']);
  if (filesOut.out != null) {
    try {
      files = parseChangedFiles(filesOut.out!);
    } on FormatException catch (e) {
      stderr.writeln('safe_pr_merge: changed-files response unreadable: ${e.message}');
    }
  } else {
    stderr.writeln('safe_pr_merge: gh api (files) failed: ${filesOut.err.trim()}');
  }

  final decision = combine(
      combine(evaluatePr(prAfter, checkedSha: sha), evaluateCheckRuns(runs)),
      evaluateChangedFiles(files, allowWorkflowChange: allowWorkflowChange));
  for (final w in decision.warnings) {
    stdout.writeln('safe_pr_merge: WARNING -- $w');
  }
  if (!decision.ok) {
    stderr.writeln('safe_pr_merge: REFUSED to merge PR #$pr (head ${sha.substring(0, 8)}):');
    for (final r in decision.reasons) {
      stderr.writeln('  - $r');
    }
    stderr.writeln('Wait for CI to finish green (gh pr checks $pr --watch), then re-run.');
    return 1;
  }

  stdout.writeln('safe_pr_merge: PR #$pr head ${sha.substring(0, 8)}: all required jobs green.');
  if (dryRun) {
    stdout.writeln('safe_pr_merge: --dry-run, not merging.');
    return 0;
  }

  final merge = gh.run(['pr', 'merge', pr, '--merge', '--match-head-commit', sha]);
  if (merge.out == null) {
    stderr.writeln('safe_pr_merge: gh pr merge FAILED (exit ${merge.code}): ${merge.err.trim()}');
    if (merge.err.toLowerCase().contains('conversation')) {
      stderr.writeln('safe_pr_merge: main requires every review conversation to be resolved '
          '(required_conversation_resolution) -- resolve them on the PR, then re-run.');
    }
    return 1;
  }
  stdout.write(merge.out);

  // `gh pr merge` exiting 0 is not proof the PR is merged (an auto-merge or merge
  // queue only ENQUEUES it). Read the state back; anything but MERGED is UNVERIFIED
  // (exit 2) -- never reported as landed (same rule as safe_push.sh).
  final after = _jsonObject(gh.run(['pr', 'view', pr, '--json', 'state']).out);
  if (after?['state'] != 'MERGED') {
    stderr.writeln('safe_pr_merge: UNVERIFIED -- gh pr merge exited 0 but PR #$pr state is '
        '${after?['state'] ?? 'unreadable'}, not MERGED. Check it before relying on it.');
    return 2;
  }
  stdout.writeln('safe_pr_merge: merged PR #$pr (state read back: MERGED).');
  return 0;
}

// `int main` would NOT set the process exit code in Dart; exit() must be called.
void main(List<String> args) => exit(_run(args));
