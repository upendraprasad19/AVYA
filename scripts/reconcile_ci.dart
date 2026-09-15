// SessionStart hook script: reconciles pushes that landed against what CI
// actually concluded, and warns only when the answer is bad.
//
// Used by .claude/settings.json `hooks.SessionStart`.
//
// WHY THIS EXISTS
// ---------------
// scripts/safe_push.sh proves a push LANDED (the remote ref moved). It cannot
// know what CI concludes, because CI runs asynchronously after the push
// returns. Nothing else in the repo closed that gap: a red CI run on a pushed
// branch was only ever noticed by someone remembering to look.
//
// ARM + WARN, NEVER BLOCK
// -----------------------
//   arm   safe_push.sh appends {branch, sha, armed_at} to the state file on a
//         landed push, via scripts/arm_ci_reconcile.sh.
//   warn  this script, at session start, looks up each armed SHA's run and
//         emits a warning ONLY for a failing run, or for a run that never
//         happened on a branch where one was due.
//   never block
//         it is a SessionStart hook and nothing else. No gate calls it, no
//         exit code is consumed, and every error path exits 0. A session must
//         never fail to start because this file had a bad day.
//
// Output contract (JSON to stdout):
//   {"pending_ci_warnings": [ {kind, branch, sha, conclusion?, run_url?,
//                              failing_jobs?, age_hours?} ],
//    "count": N, "queried_at": "<IST ISO8601>"}

import 'dart:convert';
import 'dart:io';

import 'ci_reconcile_state_lib.dart';
import 'gh_run_lib.dart';

const _statePath = '.claude/.ci_reconcile_pending.jsonl';

/// Kill switch. `touch .claude/.reconcile_ci.disabled` and this hook does
/// nothing at all — no file read, no `gh` call, no output.
///
/// Platform tier's `requires:` in docs/blast_radius.yaml lists `feature_flag`,
/// and the B-pass correctly flagged that this batch had none: a SessionStart
/// hook is live from the next session after merge with no way to switch it off
/// short of editing `.claude/settings.json`. A marker file is the cheapest form
/// that actually works here — an env var would not survive across the sessions
/// this runs in. Deliberately default-ON (the file's absence): the tool is
/// warn-only, so the risk it needs a switch for is noise, not damage.
const _killSwitchPath = '.claude/.reconcile_ci.disabled';

/// Must match `.github/workflows/test.yml`'s workflow name, and the string
/// build-apk.md's Gate 3.5 already passes to `--workflow`.
const _workflowName = 'Test & Analyze';

void main() {
  try {
    stdout.writeln(_run());
  } catch (e) {
    // Belt and braces: _run() is already internally guarded, but a
    // SessionStart hook must never break session start, so nothing escapes.
    stdout.writeln(jsonEncode({
      'pending_ci_warnings': <Map<String, dynamic>>[],
      'count': 0,
      'error': e.toString(),
      'queried_at': nowIst(),
    }));
  }
}

String _run() {
  if (File(_killSwitchPath).existsSync()) {
    return jsonEncode({
      'pending_ci_warnings': <Map<String, dynamic>>[],
      'count': 0,
      'note': 'disabled by $_killSwitchPath',
      'queried_at': nowIst(),
    });
  }

  final file = File(_statePath);
  if (!file.existsSync()) return _empty();

  final raw = file.readAsStringSync();
  final initial = dedupeKeepingEarliest(parsePendingEntries(raw));
  // No armed pushes: return without ever invoking `gh`. This is the common
  // case for a session that has not pushed, and it must cost nothing.
  if (initial.isEmpty) return _empty();

  final now = DateTime.now().toUtc();
  final warnings = <Map<String, dynamic>>[];
  final survivors = <PendingEntry>[];
  var lookupFailed = false;

  for (final entry in initial) {
    final result = queryLatestRunForSha(
      workflow: _workflowName,
      branch: entry.branch,
      sha: entry.sha,
      lister: _ghLister,
    );
    if (result.lookupFailed) lookupFailed = true;
    final outcome = classify(entry: entry, ghResult: result, now: now);

    if (outcome.keeps) survivors.add(entry);
    if (!outcome.warns) continue;

    if (outcome.action == ReconcileAction.resolvedFailure) {
      warnings.add({
        'kind': 'ci_failed',
        'branch': entry.branch,
        'sha': entry.sha,
        'conclusion': outcome.conclusion,
        'run_url': outcome.url,
        'failing_jobs': outcome.runId == null
            ? <String>[]
            : fetchFailingJobNames(runId: outcome.runId!, lister: _ghLister),
      });
    } else {
      warnings.add({
        'kind': 'ci_never_ran',
        'branch': entry.branch,
        'sha': entry.sha,
        'age_hours': outcome.ageHours,
        'note': 'A push to ${entry.branch} should have triggered CI, but no '
            'run for this SHA was found. Check whether Actions is enabled '
            'and the workflow file is valid on this branch.',
      });
    }
  }

  // ONE global notice, not one per entry: the fault is the local `gh`, not any
  // individual push, and repeating it per pending entry would be noise about a
  // single cause.
  if (lookupFailed) {
    warnings.add({
      'kind': 'gh_unavailable',
      'note': 'Could not query GitHub Actions, so ${initial.length} armed '
          'push(es) could not be reconciled. This says NOTHING about whether '
          'those runs passed. Check `gh auth status`.',
      'pending_count': initial.length,
    });
  }

  _writeState(file: file, initialRead: initial, survivors: survivors);

  return jsonEncode({
    'pending_ci_warnings': warnings,
    'count': warnings.length,
    'queried_at': nowIst(),
  });
}

/// Rewrites the state file, folding back anything that arrived while we were
/// querying `gh`.
///
/// Failure here is swallowed deliberately: a state file we could not rewrite
/// costs a repeated lookup next session, which is strictly better than an
/// exception on the session-start path.
void _writeState({
  required File file,
  required List<PendingEntry> initialRead,
  required List<PendingEntry> survivors,
}) {
  try {
    // Re-read as late as possible: another session may have armed a push while
    // this one was waiting on the network.
    final raw = file.existsSync() ? file.readAsStringSync() : '';
    final current = dedupeKeepingEarliest(parsePendingEntries(raw));

    final merged = mergeConcurrentArrivals(
      initialRead: initialRead,
      currentOnDisk: current,
      survivors: survivors,
    );

    // Compare-and-swap. Between the re-read above and the write below there is
    // still a window in which another session can append — the B-pass proved a
    // concurrent arm is lost there, on BOTH the delete and the rename path
    // (rename is not safer: it replaces the destination with a snapshot decided
    // before the append). Re-reading immediately before acting and bailing if
    // the bytes moved does not close the window either, but it shrinks it to
    // the width of the write call and costs one stat. Bailing is always safe:
    // the file keeps its entries and the next session reconciles them.
    if (_bytesChangedSince(file, raw)) return;

    if (merged.isEmpty) {
      if (file.existsSync()) file.deleteSync();
      return;
    }

    // The temp file MUST live in the same directory as its destination.
    // renameSync removes an existing target, but cannot cross filesystems —
    // a systemTemp file could land on another volume and silently degrade to
    // a non-atomic copy+delete, which is the whole thing this avoids.
    final tmp = File('$_statePath.tmp');
    tmp.writeAsStringSync(serializePendingEntries(merged), flush: true);
    tmp.renameSync(_statePath);
  } catch (_) {
    // Leave the file as-is; next session reconciles again.
  }
}

/// True when the file's bytes differ from [expected] — i.e. somebody wrote to
/// it since we read it. A read failure counts as "changed", so the caller backs
/// off rather than overwriting something it cannot see.
bool _bytesChangedSince(File file, String expected) {
  try {
    final now = file.existsSync() ? file.readAsStringSync() : '';
    return now != expected;
  } catch (_) {
    return true;
  }
}

/// The real `gh` shell-out. Kept here, out of the pure libs, so those stay
/// testable without a subprocess.
///
/// Returns `null` — NOT an empty list — whenever gh could not answer. An empty
/// list is a real answer ("no such run"); null is the absence of one.
List<Map<String, dynamic>>? _ghLister(List<String> args) {
  final ProcessResult res;
  try {
    res = Process.runSync('gh', args, runInShell: true);
  } catch (_) {
    return null; // gh not installed / not on PATH
  }
  if (res.exitCode != 0) return null; // unauthenticated, network, bad args
  final out = res.stdout;
  if (out is! String) return null;
  // gh exited 0, so a blank body is a real (empty) answer — that is what
  // `gh run list` emits when nothing matches.
  return parseGhJson(out);
}

String _empty() => jsonEncode({
      'pending_ci_warnings': <Map<String, dynamic>>[],
      'count': 0,
      'queried_at': nowIst(),
    });

/// IST = UTC+5:30, no DST. Matches check_alerts.dart's `_nowIst`.
String nowIst() {
  final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
  return '${p(ist.year, 4)}-${p(ist.month)}-${p(ist.day)}'
      'T${p(ist.hour)}:${p(ist.minute)}:${p(ist.second)}+05:30';
}
