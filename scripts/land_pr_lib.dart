// scripts/land_pr_lib.dart
//
// The pure decisions of `sh scripts/land_pr.sh <pr>` (landing D of the merge-conflict-treadmill plan,
// docs/plans/merge-train.md, OI-309). No File, no Process, no clock: the CLI (scripts/land_pr.dart) owns every
// side effect and asks this library what a result means. Every function here is table-tested.
library;

import 'safe_pr_merge_lib.dart';

/// The words `scripts/sync_with_main.dart` can print on its last line (its header, line 14). A source pin keeps this
/// list and that header equal; an unknown word is `error`, never "continue".
const List<String> syncResultWords = <String>[
  'ready',
  'pending',
  'committed',
  'fast-forwarded',
  'up-to-date',
  'refused',
  'commit-failed',
  'error',
];

/// A `result:` word and the process exit code that goes with it (plan section 3.1).
typedef LandResult = ({String word, int code});

const LandResult resMerged = (word: 'merged', code: 0);
const LandResult resNeedsHuman = (word: 'needs-human', code: 1);
const LandResult resRefused = (word: 'refused', code: 2);
const LandResult resCiFailed = (word: 'ci-failed', code: 3);
const LandResult resCiTimeout = (word: 'ci-timeout', code: 3);
const LandResult resError = (word: 'error', code: 4);
const LandResult resRecordFailed = (word: 'record-failed', code: 5);
const LandResult resMergeRefused = (word: 'merge-refused', code: 6);
const LandResult resMergeUnverified = (word: 'merge-unverified', code: 7);

/// The highest status the CLI itself returns; the wrapper maps a higher status (or a signal) to `result: error`.
const int maxCliStatus = 7;

/// The exit statuses that are the CLI's own, by `result:` word (the table of plan section 3.1).
const Map<String, int> exitCodeByWord = <String, int>{
  'merged': 0,
  'needs-human': 1,
  'refused': 2,
  'ci-failed': 3,
  'ci-timeout': 3,
  'error': 4,
  'record-failed': 5,
  'merge-refused': 6,
  'merge-unverified': 7,
};

/// The word of the LAST line of [stdout] that starts with `result:`, but only when that line is the last
/// non-empty line (anything printed after it makes the protocol unreadable). Null when absent. CRLF and trailing
/// blanks are tolerated; a line like `result: a b` (two words) is not a word.
String? parseResultWord(String stdout) {
  final lines = stdout.split('\n').map((l) => l.replaceAll('\r', '').trimRight()).toList();
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  if (lines.isEmpty) return null;
  final last = lines.last;
  const prefix = 'result:';
  if (!last.startsWith(prefix)) return null;
  final word = last.substring(prefix.length).trim();
  if (word.isEmpty || word.contains(RegExp(r'\s'))) return null;
  return word;
}

/// What the loop does after the sync step printed [word] (null = no result line).
enum SyncNext { proceed, needsHuman, refused, error }

SyncNext syncNext(String? word) {
  switch (word) {
    case 'up-to-date':
    case 'fast-forwarded':
    case 'committed':
      return SyncNext.proceed;
    case 'pending':
    case 'commit-failed':
    case 'ready': // `--commit` never prints it; if it does, a merge is left pending for a person
      return SyncNext.needsHuman;
    case 'refused':
      return SyncNext.refused;
    default: // 'error', an unknown word, no word
      return SyncNext.error;
  }
}

/// The result of the merge step: [status] is the exit status of `safe_pr_merge.sh`; [merged] is what
/// `gh pr view --json state` says AFTER it (true = MERGED, false = not, null = the read itself failed).
/// MERGED wins over any status; an unreadable state is `merge-unverified`, never `merge-refused`; a status of
/// 1 (refused) with a readable not-merged state is `merge-refused`; anything else is `merge-unverified`.
LandResult mergeOutcome({required int status, required bool? merged}) {
  if (merged == true) return resMerged;
  if (merged == null) return resMergeUnverified;
  if (status == 1) return resMergeRefused;
  return resMergeUnverified;
}

/// The plan-review-record replay verdict (plan section 3.5). PASS only for exit 0 AND the gate's FINAL pass line,
/// `[plan-review-record] PASS: every landing in <range> is accounted for ... 1 merge(s)`. The gate also prints
/// `PASS: not landing on main` and `PASS: nothing landed in ...`, which prove nothing: they are not accepted.
bool replayVerdict(int exitCode, String stdout) {
  if (exitCode != 0) return false;
  final finalPass = RegExp(r'^\[plan-review-record\] PASS: every landing in .*\s1 merge\(s\)', multiLine: true);
  return finalPass.hasMatch(stdout);
}

/// What to do after the CI wait and the fetch of main: [mainIsAncestor] = origin/main is an ancestor of HEAD.
enum RoundNext { replayAndMerge, nextRound, giveUp }

const int maxRounds = 3;

RoundNext roundNext({required int round, required bool mainIsAncestor}) {
  if (mainIsAncestor) return RoundNext.replayAndMerge;
  return round >= maxRounds ? RoundNext.giveUp : RoundNext.nextRound;
}

const String mainMovedMessage =
    'main moved three times while this branch waited for CI; run the command again';

/// What one CI poll means to the waiting loop.
enum CiTickState { green, red, pending, ghFailing }

typedef CiTick = ({CiTickState state, String note});

/// Tracks the polls of one CI wait: consecutive `gh` failures (ten end the wait) and the jobs whose only runs are
/// cancelled on consecutive polls (three make the poll red: a timed-out job is reported as cancelled and only a
/// rerun fixes it).
class CiWatch {
  CiWatch({this.maxGhFailures = 10, this.maxCancelledPolls = 3});

  final int maxGhFailures;
  final int maxCancelledPolls;
  int _ghFailures = 0;
  final Map<String, int> _cancelledStreak = <String, int>{};

  /// [judgement] is null when the `gh` read (or its parse) failed.
  CiTick update(CiJudgement? judgement) {
    if (judgement == null) {
      _ghFailures++;
      if (_ghFailures >= maxGhFailures) {
        return (state: CiTickState.ghFailing, note: 'gh failed $maxGhFailures times in a row');
      }
      return (state: CiTickState.pending, note: 'gh read failed ($_ghFailures in a row)');
    }
    _ghFailures = 0;
    final seen = judgement.cancelledOnly;
    _cancelledStreak.removeWhere((name, _) => !seen.contains(name));
    for (final n in seen) {
      _cancelledStreak[n] = (_cancelledStreak[n] ?? 0) + 1;
    }
    switch (judgement.state) {
      case CiState.green:
        return (state: CiTickState.green, note: '');
      case CiState.red:
        return (state: CiTickState.red, note: 'a job concluded with a refused result');
      case CiState.pending:
        final stuck = _cancelledStreak.entries.where((e) => e.value >= maxCancelledPolls).map((e) => e.key).toList()
          ..sort();
        if (stuck.isNotEmpty) {
          return (state: CiTickState.red, note: 'only cancelled runs for ${stuck.join(', ')} ($maxCancelledPolls polls in a row)');
        }
        return (state: CiTickState.pending, note: '');
    }
  }
}

/// The reason the PR (the object of `gh pr view --json state,isDraft,headRefName,headRefOid,baseRefName,
/// isCrossRepository`) is not landable from [branch], or null. The head branch and fork checks come BEFORE the
/// MERGED short-circuit (plan 3.2 item 3), which the caller applies with [prIsMerged].
String? prRefusal(Map<String, dynamic> pr, String branch, {required bool allowMerged}) {
  final head = pr['headRefName'];
  if (head != branch) return 'the PR head branch is "$head", this worktree is on "$branch"';
  if (pr['isCrossRepository'] != false) return 'the PR comes from a fork (isCrossRepository=${pr['isCrossRepository']})';
  final state = pr['state'];
  if (state == 'MERGED' && allowMerged) return null;
  if (state != 'OPEN') return 'the PR is $state, not OPEN';
  if (pr['isDraft'] != false) return 'the PR is a draft';
  final base = pr['baseRefName'];
  if (base != 'main') return 'the PR base is "$base", not main';
  return null;
}

bool prIsMerged(Map<String, dynamic> pr) => pr['state'] == 'MERGED';

/// Git state files whose presence means an operation is in progress (each is resolved with `git rev-parse
/// --git-path`, which is right in a linked worktree). The same list `scripts/sync_with_main.dart` checks.
const List<String> inProgressStateFiles = <String>[
  'MERGE_HEAD',
  'rebase-merge',
  'rebase-apply',
  'CHERRY_PICK_HEAD',
  'REVERT_HEAD',
  'BISECT_LOG',
  'sequencer',
];

/// The `.github/` refusal of the merge wrapper, applied early to a list of changed paths.
/// Returns a refusal message or null.
String? workflowChangeRefusal(List<String> changedPaths, {required bool allowWorkflowChange}) {
  final d = evaluateChangedFiles(changedPaths, allowWorkflowChange: allowWorkflowChange);
  return d.ok ? null : d.reasons.join('; ');
}

/// Splits a `--gh` / `--record-gate` command exactly like scripts/safe_pr_merge.dart: whitespace-separated, the first
/// token is the executable and the rest are leading arguments.
({String exe, List<String> prefix}) splitCommand(String cmd) {
  final parts = cmd.trim().split(RegExp(r'\s+'));
  return (exe: parts.first, prefix: parts.skip(1).toList());
}

/// Child output is passed through line by line with `<name>> ` in front so only the CLI's own line starts with
/// `result:` (plan section 3.1).
String prefixLines(String name, String text) {
  if (text.isEmpty) return '';
  final body = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  return body.split('\n').map((l) => '$name> ${l.replaceAll('\r', '')}').join('\n');
}

/// The `land_pr_replay-<pid>-<epochMs>` directory name of one replay clone.
const String replayDirPrefix = 'land_pr_replay-';

String replayDirName(int pid, int epochMs) => '$replayDirPrefix$pid-$epochMs';

/// True for an entry of the git common dir that is a replay clone older than a day (left by a killed run). An entry
/// without the prefix, or with a name that does not parse, is NEVER stale (the sweep touches only its own).
bool staleReplayDir(String entryName, int nowEpochMs, {int maxAgeMs = 24 * 60 * 60 * 1000}) {
  final m = RegExp(r'^land_pr_replay-(\d+)-(\d+)$').firstMatch(entryName);
  if (m == null) return false;
  final created = int.tryParse(m.group(2)!);
  if (created == null) return false;
  return nowEpochMs - created > maxAgeMs;
}

/// The message of the merge commit GitHub will create (what the plan-review-record gate classifies).
String replayMergeMessage(String pr, String owner, String branch) =>
    'Merge pull request #$pr from $owner/$branch';

/// "owner" of "owner/name".
String? ownerOf(String nameWithOwner) {
  final i = nameWithOwner.indexOf('/');
  if (i <= 0 || i == nameWithOwner.length - 1) return null;
  return nameWithOwner.substring(0, i);
}

/// One printable block for the commits that will be pushed: the count and up to [max] subjects.
String unpushedSummary(List<String> subjects, {int max = 20}) {
  if (subjects.isEmpty) return 'no local commits to push';
  final shown = subjects.take(max).map((s) => '  $s').join('\n');
  final more = subjects.length > max ? '\n  ... and ${subjects.length - max} more' : '';
  return '${subjects.length} commit(s) will be pushed:\n$shown$more';
}
