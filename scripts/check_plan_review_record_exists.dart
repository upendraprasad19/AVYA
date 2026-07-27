// scripts/check_plan_review_record_exists.dart
//
// P1.A keystone (discipline overhaul 2026-06-18) — the plan-quality forcing
// function. CLAUDE.md §4.12 requires every plan to be reviewed TWICE + a
// ground-truth audit BEFORE execution, but nothing enforced it: all gates fire
// at COMMIT time, and a `--no-ff` merge skips the local pre-commit hook. So
// plan-quality was 100% honor-system (founder Q: "why wasn't it carried out?").
//
// This gate makes the review a forcing function at the ONE point every >=account
// change must pass: the **push to `main`, in CI** (a local pre-commit MERGE_HEAD
// check is `--no-verify`-bypassable, and CI is per-push — R1/R2).
//
// For every >=account branch landing in the pushed range, require
// docs/plan-reviews/<branch>.md with:
//   review_rounds: >= 2 · ground_truth_verified: true · verdict: converged
//   bpass: accepted        (>= platform — subsumes the old catastrophic-only
//                           code-review gate; P1.C "lower threshold to account")
//   hermes: accepted       (catastrophic only)
//
// SHIP-DARK EXCEPTION (CLAUDE.md §4.12.4, discipline-overhead batch
// 2026-07-19): a record may self-declare `tier: ship_dark_build` to accept
// `review_rounds: 1` instead of 2 -- but ONLY the round count is relaxed.
// `bpass: accepted` is still independently required at >= platform exactly as
// before (checked below, unconditionally on tier) -- a self-declared
// ship_dark_build tier cannot also skip B-pass. This is a minimal,
// self-attested opt-in (same trust model as every other field in this
// gate) -- NOT automatic detection of whether a diff really is default-OFF
// and byte-identical from the flag; that remains future work.
//
// KEYING (R2 P0-2): the record is keyed on the BRANCH NAME, not a diff hash —
// the file is authored DURING development, so its name must be stable at both
// author-time and merge-time. `stagedDiffHash` is empty at a merge commit; a
// branch-diff hash isn't known until the merge exists. The merge commit subject
// (`Merge branch 'X'`) recovers the branch name at merge time.
//
// ── 2026-07-27, the gate-input family (OI-70 / OI-71) ───────────────────────
// Inputs that were derived from author-controllable or post-merge state. The
// reasoning and the measurements are in docs/plan-reviews/gate-input-family.md.
//
// SCOPE NOTE: OI-58a (single-parent commits pushed straight to main skip the
// gate) and OI-58b (branch identity from the merge subject) were in this batch
// and were SPLIT OUT on 2026-07-27 per CLAUDE.md §4.12.1 — three independent
// review rounds each found a NEW material defect in that half, the last being a
// version-bump exemption that accepted any SUBSET of its path allow-list. Both
// remain OPEN. The range walk they motivated STAYS, because OI-70/OI-71 need it.
//
//   OI-70   The tier registry was read from the MERGED tree, so a commit
//           relaxing its own rules was judged by the relaxed rules. Now the tier
//           is `max(tier under the range base, tier under the merged tree)`.
//           Both directions matter: `904e6961` landed
//           `.github/workflows/test.yml` while the registry graded it only by a
//           BROADER `.github/** -> feature` rule; the narrower
//           `.github/workflows/test.yml -> platform` promotion arrived a batch
//           later in `9e3ce5d8`. Base-only would preserve that hole exactly as
//           merged-only preserves the self-exemption one.
//
//   OI-71   The changed set came from `HEAD^1...HEAD^2` — three-dot, i.e.
//           merge-base..branch-tip, which excludes whatever the merge commit
//           itself wrote while resolving conflicts. Now every diff is two-dot
//           over the actual range, so resolution content is inspected too.
//
// CI WIRING: runs ONLY in a DEDICATED CI job with `fetch-depth: 0` (the shared
// test jobs are shallow `fetch-depth:1` → the range base is unreachable). That
// job passes the pushed range's base as `PUSH_BEFORE`; the gate falls back to
// parsing `GITHUB_EVENT_PATH`, then to `HEAD^1`. It is on the pre-commit + CI
// loop SKIP list so the shallow/local contexts never run it.
//
// Exit 0 = pass (not landing on main / blast-radius < account / every landing
//          carries a valid record). Exit 1 = fail. `--warn-only` for the soft-
//          rollout window.

import 'dart:convert';
import 'dart:io';

import 'blast_radius_content_rules_lib.dart';
import 'plan_review_record_lib.dart';

/// Repo owner for the PR-merge subject guard, when `GITHUB_REPOSITORY_OWNER`
/// is absent (local runs). Derived from origin's URL; returns null if it cannot
/// be determined, which makes the PR form fail closed rather than trust an
/// unverifiable owner.
String? _ownerFromRemote() {
  final url = _git(['remote', 'get-url', 'origin']);
  if (url.isEmpty) return null;
  // git@github.com:owner/repo.git  |  https://github.com/owner/repo.git
  final m = RegExp(r'[:/]([^/:]+)/[^/]+?(?:\.git)?$').firstMatch(url);
  return m?.group(1);
}

const _registryPath = 'docs/blast_radius.yaml';
const _recordsDir = 'docs/plan-reviews';
const _tierOrder = ['feature', 'account', 'platform', 'catastrophic'];
int _tierRank(String t) => _tierOrder.indexOf(t);
String _maxTier(String a, String b) => _tierRank(a) >= _tierRank(b) ? a : b;

class _TierRule {
  final String glob;
  final String tier;
  _TierRule(this.glob, this.tier);
}

typedef _Registry = ({String defaultTier, List<_TierRule> rules});

_Registry _parseRules(String content) {
  final rules = <_TierRule>[];
  var defaultTier = 'feature';
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('default_tier:')) {
      final m = RegExp(r'default_tier:\s*([a-z]+)').firstMatch(line);
      if (m != null) defaultTier = m.group(1)!;
      continue;
    }
    if (!line.startsWith('-')) continue;
    final g = RegExp(r'glob:\s*"([^"]+)"').firstMatch(line);
    final t = RegExp(r'tier:\s*([a-z]+)').firstMatch(line);
    if (g != null && t != null) rules.add(_TierRule(g.group(1)!, t.group(1)!));
  }
  return (defaultTier: defaultTier, rules: rules);
}

RegExp _globToRegExp(String glob) {
  final buf = StringBuffer('^');
  var i = 0;
  while (i < glob.length) {
    final ch = glob[i];
    if (ch == '*' && i + 1 < glob.length && glob[i + 1] == '*') {
      buf.write('.*');
      i += 2;
      if (i < glob.length && glob[i] == '/') i += 1;
    } else if (ch == '*') {
      buf.write('[^/]*');
      i += 1;
    } else if (ch == '?') {
      buf.write('.');
      i += 1;
    } else if ('.()[]{}+^\$|\\'.contains(ch)) {
      buf.write('\\$ch');
      i += 1;
    } else {
      buf.write(ch);
      i += 1;
    }
  }
  buf.write(r'$');
  return RegExp(buf.toString());
}

String _tierFor(String path, _Registry reg) {
  for (final rule in reg.rules) {
    if (_globToRegExp(rule.glob).hasMatch(path)) return rule.tier;
  }
  return reg.defaultTier;
}

/// Runs git and returns its stdout, or NULL when git itself failed.
///
/// Round-1 review P1-2: the first draft returned `''` on any non-zero exit, so
/// callers could not tell "no output" from "git could not answer". Three sites
/// then failed OPEN — most damagingly a per-merge diff that errored produced an
/// empty path list, which resolved to `feature` and waved the merge through
/// with a reassuring NOTE. Verified reachable: in a `--depth 2` clone
/// `git diff --name-only <unfetched>^1..<sha>` exits 128 with
/// `fatal: ambiguous argument`, not empty output.
String? _gitOrNull(List<String> args) {
  final r = Process.runSync('git', args);
  return r.exitCode == 0 ? (r.stdout as String).trim() : null;
}

/// Convenience for the sites where an empty answer is genuinely benign.
String _git(List<String> args) => _gitOrNull(args) ?? '';

bool _gitOk(List<String> args) => Process.runSync('git', args).exitCode == 0;

bool _isCommit(String rev) =>
    rev.isNotEmpty &&
    !RegExp(r'^0{7,64}$').hasMatch(rev) &&
    _gitOk(['rev-parse', '--verify', '--quiet', '$rev^{commit}']);

/// The tier registry as of [rev]. Null when the file did not exist there —
/// which is normal for old revisions and must not be treated as "no rules".
_Registry? _registryAt(String rev) {
  final r = Process.runSync('git', ['show', '$rev:$_registryPath']);
  if (r.exitCode != 0) return null;
  return _parseRules(r.stdout as String);
}

/// Max tier of [paths] evaluated under EVERY supplied registry (OI-70).
///
/// A commit cannot escape by deleting a rule (the base registry still has it)
/// nor by landing content no rule covers yet (the merged registry adds it).
/// Content rules read the working tree deliberately: they inspect the content
/// that actually LANDED, which is the merged tree.
/// Max tier of [paths] under every registry, escalating on content.
///
/// [atRev] is the revision whose TREE the content rules read. Round-1 review
/// P2-2: the first draft let `contentForcesCatastrophic` fall back to
/// `File(path)` — the merged HEAD checkout — so a `SECURITY DEFINER` migration
/// added by one merge and removed later in the same push read as absent, the
/// shared library "fails OPEN" on a missing file, and that merge never had to
/// carry `hermes: accepted`. Reading `git show <rev>:<path>` judges each
/// landing by the tree it actually introduced.
String _maxTierAcross(
    Iterable<String> paths, List<_Registry> registries, String atRev) {
  // No floor from `default_tier` on its own: an empty change set is `feature`.
  // Each registry's default is already applied per-path by `_tierFor`.
  var maxTier = 'feature';
  for (final p in paths) {
    var t = 'feature';
    for (final reg in registries) {
      t = _maxTier(t, _tierFor(p, reg));
    }
    // Round-2 review P2-A: an earlier draft passed a `readFile` that THREW on
    // failure, believing that would surface loudly. It does not —
    // blast_radius_content_rules_lib.dart:61-65 wraps the call in
    // `try { ... } catch (_) { return false; }`, so the throw was swallowed into
    // "no SECURITY DEFINER here": a silent fail-OPEN dressed up as a defence.
    // Read the blob FIRST, then decide explicitly.
    if (_tierRank('catastrophic') > _tierRank(t) &&
        _gitOk(['cat-file', '-e', '$atRev:$p'])) {
      final blob = _gitOrNull(['show', '$atRev:$p']);
      if (blob == null) {
        stdout.writeln('[plan-review-record] NOTE: $p exists at $atRev but '
            'could not be read; treating as catastrophic rather than clean.');
        t = 'catastrophic';
      } else if (contentForcesCatastrophic(p,
          fileExists: (_) => true, readFile: (_) => blob)) {
        stdout.writeln('[plan-review-record] NOTE: $p: SECURITY DEFINER content '
            'forces catastrophic at $atRev (path-tier was $t).');
        t = 'catastrophic';
      }
    }
    maxTier = _maxTier(maxTier, t);
  }
  return maxTier;
}

/// Changed paths between two revs, or NULL when git could not answer (P1-2).
List<String>? _diffPaths(String from, String to) => _gitOrNull(
        ['diff', '--name-only', '$from..$to'])
    ?.split('\n')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// Outcome of resolving the pushed range's base.
///
/// Three states, not two. Round-1 review P2-1: the first draft collapsed
/// "no base was supplied" and "a base WAS supplied and could not be resolved"
/// into the same silent `HEAD^1` fallback, so a force-push to main — where
/// `github.event.before` names a commit no ref reaches, and `actions/checkout`
/// fetches refs, not orphans — inspected only the tip and printed a clean PASS.
/// `feedback_mistake_branch_protection_semantics` records that
/// `enforce_admins: false` reopens force-push on this repo, so that is a live
/// shape rather than a hypothetical.
enum _BaseKind { resolved, none, suppliedButUnresolvable }

typedef _RangeBase = ({_BaseKind kind, String? rev, String? supplied});

_RangeBase _rangeBase() {
  String? supplied = Platform.environment['PUSH_BEFORE'];
  if (supplied == null || supplied.trim().isEmpty) {
    final eventPath = Platform.environment['GITHUB_EVENT_PATH'] ?? '';
    if (eventPath.isNotEmpty && File(eventPath).existsSync()) {
      try {
        final payload = jsonDecode(File(eventPath).readAsStringSync());
        if (payload is Map && payload['before'] is String) {
          supplied = payload['before'] as String;
        }
      } on FormatException {
        // Malformed payload — treat as "not supplied" rather than crash.
      } on FileSystemException {
        // Unreadable payload (permissions, race with the runner) — same.
        // Round-2 review P3-6: catching only FormatException let this crash.
      }
    }
  }
  supplied = supplied?.trim();

  if (supplied != null && supplied.isNotEmpty) {
    if (_isCommit(supplied)) {
      return (kind: _BaseKind.resolved, rev: supplied, supplied: supplied);
    }
    // An all-zero `before` is git's "this ref did not exist" sentinel — a
    // brand-new branch, not a lost commit. Nothing earlier exists to diff
    // against, so HEAD^1 is the honest fallback rather than an error.
    if (RegExp(r'^0{7,64}$').hasMatch(supplied)) {
      if (_gitOk(['rev-parse', '--verify', '--quiet', 'HEAD^1'])) {
        return (kind: _BaseKind.resolved, rev: 'HEAD^1', supplied: supplied);
      }
      return (kind: _BaseKind.none, rev: null, supplied: supplied);
    }
    return (
      kind: _BaseKind.suppliedButUnresolvable,
      rev: null,
      supplied: supplied
    );
  }

  if (_gitOk(['rev-parse', '--verify', '--quiet', 'HEAD^1'])) {
    return (kind: _BaseKind.resolved, rev: 'HEAD^1', supplied: null);
  }
  return (kind: _BaseKind.none, rev: null, supplied: null);
}

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[plan-review-record WARN]' : '[plan-review-record]';
  final failures = <String>[];
  void fail(String msg) => failures.add(msg);

  // 1. Landing on main? Local: symbolic-ref. CI (detached): GITHUB_REF.
  //    Checked FIRST now — the old code tested "is HEAD a merge?" before this,
  //    which is exactly the single-parent bypass (OI-58a).
  final localBranch = _gitOrNull(['rev-parse', '--abbrev-ref', 'HEAD']);
  if (localBranch == null) {
    stderr.writeln('$tag FAIL: `git rev-parse --abbrev-ref HEAD` failed. Cannot '
        'establish whether this is landing on main, and refusing to assume it '
        'is not (round-2 review P1-B: this site returned an empty string on '
        'failure, which read as "not main" and PASSED).');
    exit(warnOnly ? 0 : 1);
  }
  final ciRef = Platform.environment['GITHUB_REF'] ?? '';
  if (localBranch != 'main' && ciRef != 'refs/heads/main') {
    stdout.writeln('$tag PASS: not landing on main (branch=$localBranch ref=$ciRef).');
    exit(0);
  }

  // 2. The pushed range.
  final baseInfo = _rangeBase();
  switch (baseInfo.kind) {
    case _BaseKind.none:
      stdout.writeln('$tag SKIP: no usable range base (no PUSH_BEFORE / event '
          'payload, and HEAD has no first parent — shallow clone or root commit).');
      exit(0);
    case _BaseKind.suppliedButUnresolvable:
      // Do NOT silently narrow to HEAD^1 here (P2-1): a force-push landing N
      // commits would then have only its tip inspected, and report PASS.
      stderr.writeln("$tag FAIL: PUSH_BEFORE='${baseInfo.supplied}' was supplied "
          'but does not resolve to a commit in this clone. Refusing to narrow '
          'the range to HEAD^1 — that would inspect only the tip of a push that '
          'may have landed many commits. Causes: a force-push (the old tip is '
          'now unreachable, and actions/checkout fetches refs, not orphans), or '
          'a shallow checkout. The dedicated CI job MUST use fetch-depth: 0.');
      exit(warnOnly ? 0 : 1);
    case _BaseKind.resolved:
      break;
  }
  final base = baseInfo.rev!;

  // 3. Registries as of BOTH ends of the range (OI-70).
  final registries = <_Registry>[];
  for (final rev in {base, 'HEAD'}) {
    final r = _registryAt(rev);
    if (r != null) registries.add(r);
  }
  if (registries.isEmpty) {
    stdout.writeln('$tag SKIP: $_registryPath not found at $base or HEAD '
        '(cannot compute blast-radius).');
    exit(0);
  }

  // 4. Walk the first-parent commits actually landing in this push.
  //
  // B-pass finding 3: both git calls below used `_git` (empty-on-failure) while
  // this file's own stated invariant is "fail loud whenever git cannot answer".
  // An errored `rev-list` produced an empty list and reported
  // `PASS: nothing landed`; an errored `log --format=%P` produced no parents, so
  // `parents.length >= 2` was false and a genuine MERGE was silently filed as a
  // direct commit — which, after the OI-58a scope cut, means it is never checked
  // for a record at all. Neither has a crafted trigger (both operate on revs
  // just confirmed to exist), which is exactly why they survived three rounds
  // that were hunting reachable bypasses.
  final landedRaw = _gitOrNull(['rev-list', '--first-parent', '$base..HEAD']);
  if (landedRaw == null) {
    stderr.writeln('$tag FAIL: `git rev-list --first-parent $base..HEAD` '
        'failed. Refusing to report "nothing landed" for a range git could not '
        'walk.');
    exit(warnOnly ? 0 : 1);
  }
  final landed = landedRaw
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (landed.isEmpty) {
    stdout.writeln('$tag PASS: nothing landed in $base..HEAD.');
    exit(0);
  }

  final repoOwner =
      Platform.environment['GITHUB_REPOSITORY_OWNER'] ?? _ownerFromRemote();
  final directCommits = <String>[];
  final merges = <String>[];
  for (final sha in landed) {
    final parentsRaw = _gitOrNull(['log', '-1', '--format=%P', sha]);
    if (parentsRaw == null) {
      final short = sha.length >= 8 ? sha.substring(0, 8) : sha;
      fail('$short: `git log -1 --format=%P` failed, so this commit cannot be '
          'classified as a merge or a direct landing. Refusing to guess — '
          'guessing "direct" would skip the record requirement entirely.');
      continue;
    }
    final parents =
        parentsRaw.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    (parents.length >= 2 ? merges : directCommits).add(sha);
  }

  // DIRECT-TO-MAIN COMMITS ARE NOT JUDGED HERE — deliberately, and OI-58a stays
  // OPEN because of it.
  //
  // Judging them is a real and demonstrated need: `be3b4baf` and `8c38c855` are
  // account-tier auth commits that landed straight on main, unreviewed, because
  // the pre-2026-07-27 gate exited at `rev-parse HEAD^2` before looking. But
  // three independent review rounds each found a NEW material defect in the
  // enforcement built for it, every one in the same place — first a per-PUSH
  // union that broke the standard release flow, then, in the fix for that, a
  // version-bump exemption that accepted any SUBSET of its allow-list. That last
  // one let a direct commit rewriting `monthlyPriceInr` and
  // `freeAiMessagesPerDay` in app_constants.dart pass at account tier with a
  // reassuring "version-bump exemption" note (confirmed by execution).
  //
  // CLAUDE.md §4.12.1: when successive rounds keep surfacing new material
  // issues, the unit is too large — split it and ship the smallest converged
  // piece. Founder approved the split 2026-07-27. The range walk below stays
  // (OI-70/OI-71 need it and were stable across two rounds); the direct-commit
  // judgement and the one-record-one-landing rule come out and get their own
  // unit, where the exemption can be CONTENT-verified — every changed LINE must
  // be a version line — instead of path-verified, matching the Dependabot
  // exemption's standard in this same file.
  //
  // Net effect vs today: strictly better for merges, unchanged for direct
  // commits. No behaviour regresses.
  if (directCommits.isNotEmpty) {
    stdout.writeln('$tag NOTE: ${directCommits.length} direct-to-main commit(s) '
        'in this range are NOT judged (OI-58a, still open — see the closure '
        'ledger). Merges below are.');
  }

  // Every merge in the range needs a valid record for its own tier.
  for (final sha in merges) {
    final short = sha.length >= 8 ? sha.substring(0, 8) : sha;
    // Two-dot: includes what the merge commit itself wrote resolving conflicts
    // (OI-71). The old three-dot `HEAD^1...HEAD^2` stopped at the branch tip.
    final paths = _diffPaths('$sha^1', sha);
    if (paths == null) {
      // P1-2: the deleted `diff.isEmpty` guard used to shout exactly here.
      fail('$short: could not diff $sha^1..$sha (git failed — typically an '
          'object missing from a shallow clone). The dedicated CI job MUST use '
          'actions/checkout fetch-depth: 0. Refusing to treat an unreadable '
          'merge as feature-tier.');
      continue;
    }
    final tier = _maxTierAcross(paths, registries, sha);

    final subject = _git(['log', '-1', '--format=%s', sha]);
    final ms = classifyMergeSubject(subject, repoOwner: repoOwner);

    if (ms.kind == MergeSubjectKind.remoteSyncMerge && ms.branch == 'main') {
      // `git pull` on main with divergent local history. The incoming commits
      // were already gated when originally pushed; demanding
      // docs/plan-reviews/main.md would redden main for doing nothing but
      // syncing. ONLY a same-branch sync qualifies — `git pull origin <feature>`
      // has this shape too but IS a landing, and passing it unconditionally was
      // a craftable bypass (round-2 review, P1-2).
      stdout.writeln('$tag NOTE: $short is a remote-sync merge of main; not a landing.');
      continue;
    }

    if (_tierRank(tier) < _tierRank('account')) {
      stdout.writeln('$tag NOTE: $short blast-radius=$tier (< account; no record required).');
      continue;
    }

    switch (ms.kind) {
      case MergeSubjectKind.foreignPullRequest:
        fail("$short: PR merge from owner '${ms.owner}' does not match this "
            "repo's owner '${repoOwner ?? '<unknown>'}' (branch '${ms.branch}'). "
            'This repo is public: a fork branch whose short name collides with '
            'an existing approved record must never be treated as reviewed.');
        continue;
      case MergeSubjectKind.unrecognized:
        fail("$short: could not recover merged branch from subject: '$subject' "
            '(expected "Merge branch \'X\'" or '
            '"Merge pull request #N from owner/X").');
        continue;
      case MergeSubjectKind.remoteSyncMerge:
      case MergeSubjectKind.branchMerge:
      case MergeSubjectKind.pullRequestMerge:
        break;
    }

    final rawBranch = ms.branch!;
    final branch = recordSlug(rawBranch);

    // Dependabot exemption — CONTENT-verified, not name-trusted. The branch NAME
    // earns nothing (anyone with push access can name a branch `dependabot/x`),
    // so every commit on the merged side must be authored by Dependabot AND the
    // diff must touch only dependency manifests. Condition (2) is the
    // load-bearing one: git author email is self-asserted, so (1) raises the bar
    // rather than sealing it. `.github/workflows/**` is deliberately NOT
    // allowed — a bot must not rewrite the CI enforcing every other gate.
    if (isDependabotBranch(rawBranch)) {
      final authors = _git(['log', '--format=%ae', '$sha^1..$sha^2']).split('\n');
      if (!allCommitsAuthoredByDependabot(authors)) {
        fail("$short: branch '$rawBranch' is named like a Dependabot branch but "
            'its commits are not authored by Dependabot (authors: '
            "${authors.where((a) => a.trim().isNotEmpty).toSet().join(', ')}). "
            'The exemption is content-verified; a branch name alone earns nothing.');
        continue;
      }
      if (!dependabotDiffIsManifestOnly(paths)) {
        final offending = paths.where((p) => !dependabotAllowedPaths.contains(p));
        fail("$short: Dependabot branch '$rawBranch' touches paths outside the "
            'dependency manifests: ${offending.join(', ')}. Allowed: '
            '${dependabotAllowedPaths.join(', ')}. An Actions-version bump edits '
            'CI workflow files and therefore still requires a plan-review record '
            '— a bot must not rewrite the CI that enforces every other gate.');
        continue;
      }
      stdout.writeln('$tag NOTE (Dependabot exemption): $short `$rawBranch` '
          'blast-radius=$tier, manifest-only, bot-authored. Record waived; the '
          'CI suite is the control. §4.12 founder decision 2026-07-26.');
      continue;
    }

    // One-record-one-landing (OI-58b) is NOT enforced here — it ships with
    // OI-58a in the split unit. A branch re-landing at >=account can still
    // satisfy the gate with the record from its first landing.
    final err = _validateRecord(
        '$_recordsDir/$branch.md', rawBranch, branch, tier, short, sha);
    if (err != null) fail(err);
  }

  if (failures.isEmpty) {
    stdout.writeln('$tag PASS: every merge in $base..HEAD carries a valid record '
        '(${merges.length} merge(s); ${directCommits.length} direct commit(s) '
        'not judged — OI-58a).');
    exit(0);
  }
  for (final f in failures) {
    stderr.writeln('$tag FAIL: $f');
  }
  exit(warnOnly ? 0 : 1);
}


/// Validates one record file. Returns null on success, or the failure message.
/// Validates the record AS OF [atRev], not as of the working tree.
///
/// Round-2 review P3-7: reading `File(recordPath)` is right only for the LAST
/// merge in a range — for any earlier merge it judges a record the working tree
/// may have since changed. The neighbouring OI-70/P2-2 fixes in this same
/// rewrite already read per-rev; this one did not.
String? _validateRecord(String recordPath, String rawBranch, String branch,
    String tier, String short, String atRev) {
  String? readAt(String path) => _gitOrNull(['show', '$atRev:$path']);
  final content0 = readAt(recordPath);
  if (content0 == null) {
    return '$short: branch `$branch` is blast-radius=$tier (>= account) but has no '
        'plan-review record at $recordPath. §4.12: every >=account plan needs '
        '×2 context-blind review + a ground-truth audit, recorded here.';
  }
  final content = content0;
  // Scoped to the leading `---` frontmatter, matching recordBranchFieldMatches.
  // Round-1 review P3-1: every other field (review_rounds, verdict, bpass,
  // tier, …) was matched against the WHOLE file, while `branch:` alone was
  // scoped — and plan_review_record_lib.dart:158-163 spells out why scoping
  // matters. A record whose frontmatter omits a field but whose prose discusses
  // one (e.g. quoting another batch's `verdict: converged`) could satisfy it.
  // Pre-existing rather than introduced here, but the asymmetry now sits in one
  // rewritten function, so it is closed rather than carried.
  final scope = recordFrontmatter(content) ?? content;
  String? field(String k) =>
      RegExp('^$k:\\s*(.+)\$', multiLine: true).firstMatch(scope)?.group(1)?.trim();

  // The record must NAME the branch it reviewed. recordSlug() maps `/` → `-`,
  // which is not injective: `hold/mechanic` slugs to `hold-mechanic`, an
  // EXISTING converged record for unrelated work.
  if (!recordBranchFieldMatches(content, rawBranch)) {
    return "$short: $recordPath: its `branch:` field does not name '$rawBranch' "
        "(found: '${field('branch') ?? '<absent>'}'). A record vouches for ONE "
        'branch — slug collisions must not let one branch ride another\'s review.';
  }

  final rounds = int.tryParse(field('review_rounds') ?? '') ?? 0;
  final shipDarkBuild = field('tier') == 'ship_dark_build';
  final minRounds = shipDarkBuild ? 1 : 2;
  if (rounds < minRounds) {
    return '$short: $recordPath: review_rounds=$rounds (need >= $minRounds'
        '${shipDarkBuild ? ' for tier: ship_dark_build' : ', or tier: ship_dark_build '
            'for a flag-gated build-only commit -- CLAUDE.md §4.12.4'}).';
  }
  if (field('ground_truth_verified') != 'true') {
    return '$short: $recordPath: ground_truth_verified must be true.';
  }
  if (field('verdict') != 'converged') {
    return '$short: $recordPath: verdict must be "converged" (got "${field('verdict')}").';
  }
  if (_tierRank(tier) >= _tierRank('platform') && field('bpass') != 'accepted') {
    return '$short: $recordPath: blast-radius=$tier requires bpass: accepted.';
  }
  if (tier == 'catastrophic' && field('hermes') != 'accepted') {
    return '$short: $recordPath: catastrophic requires hermes: accepted.';
  }

  // Anti-fabrication (P1.H / F3): when bpass/hermes claim "accepted", require a
  // referenced file that EXISTS and itself carries `verdict: accepted`.
  final refs = <String, ({String field, String dir})>{
    'bpass': (field: 'bpass_review', dir: 'docs/reviews/'),
    'hermes': (field: 'hermes_report', dir: 'docs/audit/'),
  };
  for (final entry in refs.entries) {
    if (field(entry.key) != 'accepted') continue;
    final refPath = field(entry.value.field);
    if (refPath == null || refPath.isEmpty) {
      return '$short: $recordPath: ${entry.key}: accepted requires a '
          '${entry.value.field}: field naming a file under ${entry.value.dir} '
          'that exists and contains `verdict: accepted`.';
    }
    final refContent = readAt(refPath);
    if (refContent == null) {
      return '$short: $recordPath: ${entry.value.field}: $refPath does not '
          'exist at $atRev. The referenced review must be committed, not just '
          'present in the working tree.';
    }
    if (!RegExp(r'^verdict:\s*accepted\s*$', multiLine: true)
        .hasMatch(refContent)) {
      return '$short: $recordPath: ${entry.value.field} file $refPath does not '
          'contain `verdict: accepted` (line-anchored). Fabricated acceptance is '
          'not allowed.';
    }
  }
  return null;
}
