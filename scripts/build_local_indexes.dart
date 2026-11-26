// scripts/build_local_indexes.dart
//
// Builds BOTH local indexes, docs/audit/OPEN_INDEX.md and docs/diagnoses/INDEX.md (landing A2 of
// the merge-conflict-treadmill plan; the stamp, the staleness predicate and the atomic write
// are in scripts/local_indexes_lib.dart).
//
// Both are gitignored, untracked build products: a fresh clone or worktree has neither until
// this runs, and the SessionStart nudge (scripts/discipline_hook.dart) says so. CI runs this
// bare (strict) before the gate loop and before the unit-test shards, so a PR that breaks an
// index input fails there.
//
// Usage: dart run scripts/build_local_indexes.dart [--lenient]
//   (strict, the default: any doc or board problem fails and nothing is written for that index;
//    --lenient: skip or flag the offending docs and rows, say so, write the rest. A duplicate
//    `## OI-N` still fails: it corrupts every pointer below it.)
//
// Exit codes: the WORST of the two builders (1 validation failure, then 3 write failure, then
// 0), and 1 when the self-check below fails. Both builders always run, so one bad index does
// not hide the state of the other.
//
// SELF-CHECK: after both builds report success, `isStale(root)` must be false. An orchestrator
// that "succeeded" and left a stale or unreadable stamp would send every later reader down the
// wrong path while looking fine, the failure class this repo tracks hardest.
//
// ROOT: the git toplevel of the working directory when it holds this script, else the parent
// of this script's directory (a `git archive` tree has no .git).

import 'dart:io';

import 'build_bug_index.dart' show runBugIndex;
import 'build_oi_index.dart' show runOiIndex;
import 'local_indexes_lib.dart';

void main(List<String> args) {
  exit(runLocalIndexes(resolveLocalIndexesRoot(),
      strict: !args.contains('--lenient')));
}

/// 1 beats 3 beats 0: a validation failure blocks a hook, a failed write only warns. Any code
/// other than 0 and 3 is treated as a validation failure.
int worstExit(Iterable<int> codes) {
  var worst = 0;
  for (final c in codes) {
    if (c == 0) continue;
    if (c == kWriteFailedExit) {
      if (worst == 0) worst = kWriteFailedExit;
    } else {
      worst = 1;
    }
  }
  return worst;
}

/// One index builder: builds under [root] and returns the exit code. [runOiIndex] and
/// [runBugIndex] are the production ones; the type exists as a test seam.
typedef IndexBuilder = int Function(String root, {bool strict});

/// One builder under the orchestrator's contract: it returns a code and never throws. A builder
/// that throws anyway (an unreadable directory, a bug) is named on stderr, counts as a validation
/// failure and does NOT stop the other builder, so one broken index never hides the state of the
/// other (the header promise "both builders always run").
int _guarded(String id, IndexBuilder build, String root, bool strict) {
  try {
    return build(root, strict: strict);
  } catch (e) {
    stderr.writeln('[local-indexes] the $id builder crashed: $e');
    return 1;
  }
}

/// Runs both builders under [root], then the self-check. Returns the exit code. [staleCheck] is a
/// test seam for the self-check (a real stale-after-build cannot be provoked from outside);
/// [oiBuilder] and [bugBuilder] are test seams for a builder that throws.
int runLocalIndexes(String root,
    {bool strict = true,
    bool Function(String root) staleCheck = isStale,
    IndexBuilder oiBuilder = runOiIndex,
    IndexBuilder bugBuilder = runBugIndex}) {
  final oi = _guarded('oi', oiBuilder, root, strict);
  final bug = _guarded('bug', bugBuilder, root, strict);
  final worst = worstExit([oi, bug]);
  if (worst != 0) return worst;
  if (staleCheck(root)) {
    stderr.writeln('[local-indexes] SELF-CHECK FAIL: both builders reported success but an '
        'index is still stale or unreadable (stamp does not match its inputs).');
    for (final r in localIndexReports(root)) {
      if (r.state != IndexState.fresh) {
        stderr.writeln('  - ${r.spec.outputPath}: ${r.state.name}');
      }
    }
    return 1;
  }
  return 0;
}

/// Builds the OPEN_INDEX (lenient) when it is missing; a no-op when it exists. For a caller
/// that needs the OI index on disk and nothing else (the full-suite test
/// `context_artifact_tracked_list_test.dart` measures it). Returns the exit code of the build,
/// 0 when nothing had to be built.
int ensureLocalIndexes(String root) {
  if (File('$root/$kOiIndexPath').existsSync()) return 0; // file-only: a generated FILE
  return runOiIndex(root, strict: false);
}

/// Builds the diagnose index (lenient) when it is missing or stale; a no-op when it is fresh.
/// For `check_regression_catalog.dart`, the merge-commit walk that READS the index: an installed
/// pre-commit hook that predates A2 does not build it before the walk, and hooks are COPIES that
/// a machine updates only when it re-runs the installer, so the consumer makes sure of its own
/// input instead of relying on the hook (B-pass seat 2, F2). Lenient on purpose: a diagnose doc
/// the strict build would refuse is the author's to fix at its own commit, not a reason to stop a
/// merge. Returns the exit code of the build, 0 when nothing had to be built.
int ensureBugIndexFresh(String root) {
  if (indexState(root, kBugIndexSpec) == IndexState.fresh) return 0;
  return runBugIndex(root, strict: false);
}

/// The checkout root: [cwd]'s git toplevel when that holds this script, else the parent of the
/// script's directory. [cwd] and [script] are test seams.
String resolveLocalIndexesRoot({String? cwd, Uri? script}) {
  try {
    final r = Process.runSync('git', ['rev-parse', '--show-toplevel'],
        workingDirectory: cwd ?? Directory.current.path);
    if (r.exitCode == 0) {
      final top = (r.stdout as String).trim();
      if (top.isNotEmpty &&
          File('$top/scripts/build_local_indexes.dart').existsSync()) { // file-only: this script
        return top;
      }
    }
  } catch (_) {
    // No git on PATH, or cwd is not a directory: fall through to the script's own location.
  }
  return File.fromUri(script ?? Platform.script).parent.parent.path;
}
