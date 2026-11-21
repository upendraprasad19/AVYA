// Pure reader for the safe_push.sh terminal push-result record (OI-172).
//
// No file or network I/O — every function here takes its inputs as values, so
// the whole file is unit-testable without a repo, a temp dir, or a remote. The
// WRITER is scripts/safe_push.sh; this is the only sanctioned READER.
//
// Record file: `$(git rev-parse --absolute-git-dir)/.safe_push_result`
//   NOT in the worktree, and NOT `--git-common-dir`:
//   * inside `.git`, so `git status --ignored` never reports it and it cannot
//     make a worktree unretirable — the class that has already fired three
//     times here (CLAUDE.md §5, diagnose b4d7e9, OI-128).
//   * `--absolute-git-dir` rather than `--git-dir`, because in the PRIMARY
//     worktree the latter returns a RELATIVE `.git` and a reader that is not
//     standing in the repo root would resolve it against its own cwd.
//   * per-worktree (not shared), which matches the scope of the lock in
//     scripts/_git_lock.sh, so the lock that already serialises pushes also
//     serialises writes to this file. `--git-common-dir` would be one shared
//     path with NO such serialisation — the lock is keyed on `--git-dir`, so
//     two linked worktrees can push concurrently.
//
// WHY THIS FILE EXISTS AS CODE AND NOT AS PROSE (plan review round 3, F2).
// The contract below was originally written as a paragraph in the plan, and the
// test for it had to invent its own reader — so the assertion only proved that
// a stand-in agreed with prose written by the same author. It could not fail
// for the right reason, and every future reader would have re-derived the rules
// from prose and some would have got the missing-file case backwards. The
// contract lives here, once, so there is exactly one place to be right.
// Closest precedent: scripts/ci_reconcile_state_lib.dart, the pure reader for
// the gitignored file scripts/arm_ci_reconcile.sh writes.

/// What a reader may conclude about a push.
///
/// There are THREE outcomes, never two. `unverified` is not a failure and not a
/// success — collapsing it into either is the defect this whole mechanism
/// exists to prevent (`safe_push.sh` exit 2; diagnose d4f9b2).
enum PushVerdict {
  /// The remote ref was OBSERVED at the sha the reader asked about.
  landed,

  /// The push definitively did not land what the reader asked about.
  failed,

  /// Genuinely unknown. **This is the answer for a MISSING record.**
  unverified,
}

/// One parsed `.safe_push_result` record.
///
/// Every field is a plain `String`; absent keys read as `''` rather than null,
/// because a partially-written record must degrade to "unknown" via
/// [classifyPushResult], never throw at a reader.
class PushResult {
  /// Raw `result=` value: `STARTED`, `LANDED`, `FAILED` or `UNVERIFIED`.
  ///
  /// Deliberately NOT parsed into [PushVerdict] here — `STARTED` is not a
  /// verdict at all, and mapping it to one at parse time would lose that.
  final String result;

  final String exitCode;
  final String branch;

  /// The fully-qualified ref this record is about, e.g. `refs/heads/main`.
  final String ref;

  final String remote;
  final String localSha;
  final String remoteSha;

  /// The ref `safe_push.sh` ACTUALLY probed on the remote.
  ///
  /// `probe_remote_sha()` hardcodes `refs/heads/$BRANCH`, so when `$BRANCH` is
  /// not a branch (a tag passed positionally) the probe looks in the wrong
  /// namespace, finds nothing, and the script reports FAILED for a push that
  /// landed. Recording what was probed makes that self-diagnosing instead of
  /// silently wrong — see [probedTheWrongNamespace].
  final String verifiedRef;

  final String pid;
  final String started;
  final String ended;
  final String worktree;
  final String reason;

  /// Every key/value actually present, including any this class does not name.
  ///
  /// Kept so a future field added by the writer is readable by an older reader
  /// instead of silently dropped.
  final Map<String, String> fields;

  const PushResult({
    required this.result,
    required this.exitCode,
    required this.branch,
    required this.ref,
    required this.remote,
    required this.localSha,
    required this.remoteSha,
    required this.verifiedRef,
    required this.pid,
    required this.started,
    required this.ended,
    required this.worktree,
    required this.reason,
    required this.fields,
  });

  /// True when the record says a push was STARTED and never reached a verdict.
  ///
  /// Pair with a liveness check on [pid]: alive ⇒ a push is in flight, do not
  /// start another; dead ⇒ it was interrupted and the landing is unknown.
  bool get isInFlight => result == 'STARTED';

  /// True when the recorded verdict rests on probing a DIFFERENT ref than the
  /// one the record is about — so the verdict is untrustworthy in either
  /// direction, regardless of what it says.
  bool get probedTheWrongNamespace =>
      verifiedRef.isNotEmpty && ref.isNotEmpty && verifiedRef != ref;
}

/// Parse the contents of a `.safe_push_result` file.
///
/// Returns `null` for input that is empty, whitespace-only, or carries no
/// `result=` key at all — i.e. anything a reader must treat exactly like a
/// missing file. Never throws: a torn or foreign file is "no information", and
/// an exception here would tempt a caller into a catch-all that turns unknown
/// into failed.
PushResult? parsePushResult(String? text) {
  if (text == null) return null;

  final fields = <String, String>{};
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue; // no key, or a leading '=' — not a field
    final key = line.substring(0, eq).trim();
    if (key.isEmpty) continue;
    // FIRST occurrence wins. The writer publishes each record atomically via
    // `mv -T`, so duplicate keys cannot arise from a normal write; if they do,
    // the file is not one this protocol produced and the earliest value is as
    // good a guess as any. Stated so the behaviour is deliberate, not incidental.
    fields.putIfAbsent(key, () => line.substring(eq + 1).trim());
  }

  if (!fields.containsKey('result')) return null;
  final result = fields['result']!;
  if (result.isEmpty) return null;

  String at(String k) => fields[k] ?? '';
  return PushResult(
    result: result,
    exitCode: at('exit'),
    branch: at('branch'),
    ref: at('ref'),
    remote: at('remote'),
    localSha: at('local_sha'),
    remoteSha: at('remote_sha'),
    verifiedRef: at('verified_ref'),
    pid: at('pid'),
    started: at('started'),
    ended: at('ended'),
    worktree: at('worktree'),
    reason: at('reason'),
    fields: Map.unmodifiable(fields),
  );
}

/// What may a reader conclude about `wantRef` at `wantSha`, given [record]?
///
/// THE FOUR RULES, in the order they are applied. Each one exists because
/// getting it wrong produces a confident wrong answer rather than an error:
///
/// 1. **A missing or unparseable record is [PushVerdict.unverified], NEVER
///    [PushVerdict.failed].** No record means no attempt was recorded, or the
///    writer died before writing one. Reading absent as failed re-creates the
///    bad-news-vs-no-news inversion this mechanism exists to kill
///    (`feedback_bad_news_vs_no_news`, 3 prior instances).
/// 2. **`STARTED` is not a verdict** — it is unverified until a terminal record
///    replaces it.
/// 3. **BOTH `ref` AND `local_sha` must match.** Not the sha alone: two refs
///    legitimately share a tip right after a fast-forward merge, or on a
///    freshly-cut branch, so a sha-only check lets one ref's LANDED verdict be
///    read as proof about a different ref. This is also what makes the four
///    silent pre-push aborts in `safe_push.sh` harmless — a stale record cannot
///    pass as a fresh verdict.
/// 4. **An unrecognised `result=` value is unverified**, not an error and not a
///    success. A future writer state must degrade to "I don't know" in an older
///    reader.
///
/// ⚠ [PushVerdict.landed] means the ref was observed on the remote. It says
/// NOTHING about CI, which runs afterwards — that is what
/// scripts/arm_ci_reconcile.sh and scripts/reconcile_ci.dart are for.
PushVerdict classifyPushResult(
  PushResult? record, {
  required String wantRef,
  required String wantSha,
}) {
  // Rule 1.
  if (record == null) return PushVerdict.unverified;

  // Rule 2.
  if (record.isInFlight) return PushVerdict.unverified;

  // Rule 3. Both legs, and both fail closed when the record does not carry the
  // field at all — an empty `ref` cannot be shown to match, so it does not.
  if (record.ref != wantRef) return PushVerdict.unverified;
  if (record.localSha != wantSha) return PushVerdict.unverified;

  // Rule 4.
  switch (record.result) {
    case 'LANDED':
      return PushVerdict.landed;
    case 'FAILED':
      return PushVerdict.failed;
    case 'UNVERIFIED':
      return PushVerdict.unverified;
    default:
      return PushVerdict.unverified;
  }
}

/// One-line human summary for a reader that just wants to be told.
///
/// Deliberately names the verdict AND why it is not stronger, because the whole
/// failure mode here is a reader over-reading a weak answer.
String describePushResult(
  PushResult? record, {
  required String wantRef,
  required String wantSha,
}) {
  final verdict = classifyPushResult(record, wantRef: wantRef, wantSha: wantSha);
  if (record == null) {
    return 'UNVERIFIED: no push record found — nothing was recorded, or the '
        'writer died before recording. This is NOT evidence the push failed.';
  }
  if (record.isInFlight) {
    return 'UNVERIFIED: a push was STARTED (pid ${record.pid.isEmpty ? "?" : record.pid}) '
        'and has not reached a verdict. Check whether that pid is alive before '
        'starting another push.';
  }
  if (record.ref != wantRef) {
    return 'UNVERIFIED: the record is about ${record.ref.isEmpty ? "<no ref>" : record.ref}, '
        'not $wantRef.';
  }
  if (record.localSha != wantSha) {
    return 'UNVERIFIED: the record is about sha ${record.localSha.isEmpty ? "<none>" : record.localSha}, '
        'not $wantSha.';
  }
  final caveat = record.probedTheWrongNamespace
      ? ' ⚠ the verdict rests on probing ${record.verifiedRef}, which is not '
          '${record.ref} — treat it as unreliable in either direction.'
      : '';
  switch (verdict) {
    case PushVerdict.landed:
      return 'LANDED: $wantRef observed on the remote at $wantSha. '
          'This says nothing about CI.$caveat';
    case PushVerdict.failed:
      return 'FAILED: $wantRef did not land at $wantSha'
          '${record.reason.isEmpty ? "" : " — ${record.reason}"}.$caveat';
    case PushVerdict.unverified:
      return 'UNVERIFIED: the push could not be confirmed either way'
          '${record.reason.isEmpty ? "" : " — ${record.reason}"}.$caveat';
  }
}
