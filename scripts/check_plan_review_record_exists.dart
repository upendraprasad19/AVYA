// scripts/check_plan_review_record_exists.dart
//
// P1.A keystone (discipline overhaul 2026-06-18) — the plan-quality forcing
// function. CLAUDE.md §4.12 requires every plan to be reviewed TWICE + a
// ground-truth audit BEFORE execution, but nothing enforced it: all gates fire
// at COMMIT time, and a `--no-ff` merge skips the local pre-commit hook. So
// plan-quality was 100% honor-system (founder Q: "why wasn't it carried out?").
//
// This gate makes the review a forcing function at the ONE point every >=account
// change must pass: the **merge-to-main commit, in CI** (a local pre-commit
// MERGE_HEAD check is `--no-verify`-bypassable, and CI is per-push — R1/R2).
//
// At a merge commit landing on `main`, for a merged branch whose aggregate
// blast-radius is >= account, require docs/plan-reviews/<branch>.md with:
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
// CI WIRING (R2 P0-1 / F1): runs ONLY in a DEDICATED CI job with
// `fetch-depth: 0` (the shared test jobs are shallow `fetch-depth:1` → HEAD^2
// absent → the three-dot diff fails). It is on the pre-commit + CI loop SKIP
// list so the shallow/local contexts never run it.
//
// Exit 0 = pass (not a merge-to-main / blast-radius < account / record present
//          & valid). Exit 1 = fail. `--warn-only` for the soft-rollout window.

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

class _TierRule {
  final String glob;
  final String tier;
  _TierRule(this.glob, this.tier);
}

({String defaultTier, List<_TierRule> rules}) _parseRules(String content) {
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

String _tierFor(String path, ({String defaultTier, List<_TierRule> rules}) reg) {
  for (final rule in reg.rules) {
    if (_globToRegExp(rule.glob).hasMatch(path)) return rule.tier;
  }
  return reg.defaultTier;
}

String _git(List<String> args) {
  final r = Process.runSync('git', args);
  return r.exitCode == 0 ? (r.stdout as String).trim() : '';
}

bool _gitOk(List<String> args) =>
    Process.runSync('git', args).exitCode == 0;

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[plan-review-record WARN]' : '[plan-review-record]';
  int die(String msg) {
    stderr.writeln('$tag FAIL: $msg');
    return warnOnly ? 0 : 1;
  }

  // 1. Merge commit? A merge has a second parent.
  if (!_gitOk(['rev-parse', '--verify', '--quiet', 'HEAD^2'])) {
    stdout.writeln('$tag PASS: HEAD is not a merge commit (gate applies only to merge-to-main).');
    exit(0);
  }

  // 2. Landing on main? Local: symbolic-ref. CI (detached): GITHUB_REF.
  final localBranch = _git(['rev-parse', '--abbrev-ref', 'HEAD']);
  final ciRef = Platform.environment['GITHUB_REF'] ?? '';
  final onMain = localBranch == 'main' || ciRef == 'refs/heads/main';
  if (!onMain) {
    stdout.writeln('$tag PASS: merge not landing on main (branch=$localBranch ref=$ciRef).');
    exit(0);
  }

  // 3. Recover the merged branch name from the merge commit subject.
  //    Handles three real shapes (see plan_review_record_lib.dart):
  //      - `Merge branch 'X'`                      local --no-ff merge
  //      - `Merge pull request #N from owner/X`    GitHub PR merge (owner-guarded)
  //      - `Merge branch 'X' of <url>`             git pull — remote sync, not a landing
  final subject = _git(['log', '-1', '--format=%s', 'HEAD']);
  final repoOwner =
      Platform.environment['GITHUB_REPOSITORY_OWNER'] ?? _ownerFromRemote();
  final ms = classifyMergeSubject(subject, repoOwner: repoOwner);

  switch (ms.kind) {
    case MergeSubjectKind.remoteSyncMerge:
      // `git pull` on main with divergent local history. The incoming commits
      // were already gated when they were originally pushed; treating this as a
      // branch landing makes the gate demand docs/plan-reviews/main.md and
      // reddens main for doing nothing but syncing.
      //
      // ONLY a same-branch sync qualifies. `git pull origin <feature>` while on
      // main produces this same shape but IS a feature landing, and passing it
      // unconditionally was a craftable bypass: any subject ending `' of x'`
      // exited 0 before blast-radius was computed (round-2 review, P1-2).
      // Anything else falls through to the normal record requirement.
      if (ms.branch == 'main') {
        stdout.writeln('$tag PASS: remote-sync merge (git pull) of '
            "'main' — syncing main with its own remote, not a landing.");
        exit(0);
      }
      break;
    case MergeSubjectKind.foreignPullRequest:
      exit(die("PR merge from owner '${ms.owner}' does not match this repo's "
          "owner '${repoOwner ?? '<unknown>'}' (branch '${ms.branch}'). This "
          'repo is public: a fork branch whose short name collides with an '
          'existing approved record must never be treated as reviewed.'));
    case MergeSubjectKind.unrecognized:
      exit(die("could not recover merged branch from subject: '$subject' "
          "(expected \"Merge branch 'X'\" or "
          '"Merge pull request #N from owner/X").'));
    case MergeSubjectKind.branchMerge:
    case MergeSubjectKind.pullRequestMerge:
      break;
  }

  final rawBranch = ms.branch!;
  final branch = recordSlug(rawBranch);

  // 4. Blast-radius of the branch's changes (three-dot = merge-base..branch-tip).
  final regFile = File(_registryPath);
  if (!regFile.existsSync()) {
    stdout.writeln('$tag SKIP: $_registryPath not found (cannot compute blast-radius).');
    exit(0);
  }
  final reg = _parseRules(regFile.readAsStringSync());
  final diff = _git(['diff', '--name-only', 'HEAD^1...HEAD^2']);
  if (diff.isEmpty) {
    // fetch-depth:1 would make HEAD^2/merge-base unreachable → empty. Fail loud
    // in the dedicated job (it MUST use fetch-depth:0); warn-only elsewhere.
    exit(die('empty merge diff (HEAD^1...HEAD^2). The dedicated CI job MUST '
        'use actions/checkout fetch-depth:0 — the shallow default hides HEAD^2.'));
  }
  final paths = diff.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty);
  var maxTier = reg.defaultTier;
  for (final p in paths) {
    var t = _tierFor(p, reg);
    if (_tierRank('catastrophic') > _tierRank(t) && contentForcesCatastrophic(p)) {
      stdout.writeln('$tag NOTE: $p: SECURITY DEFINER content forces '
          'catastrophic (path-tier was $t).');
      t = 'catastrophic';
    }
    if (_tierRank(t) > _tierRank(maxTier)) maxTier = t;
  }

  if (_tierRank(maxTier) < _tierRank('account')) {
    stdout.writeln('$tag PASS: branch `$branch` blast-radius=$maxTier (< account; no record required).');
    exit(0);
  }

  // 4b. Dependabot exemption — CONTENT-verified, not name-trusted.
  //
  // pubspec.yaml/lock are platform tier, so every automated bump would demand a
  // plan-review record no bot can author. Founder decision 2026-07-26: exempt
  // the RECORD requirement for genuine dependency bumps, because the real
  // control for a bump is the full CI suite, not a hand-written plan.
  //
  // The branch NAME alone earns nothing (anyone with push access can name a
  // branch `dependabot/x`), so two further conditions apply:
  //   (1) every commit on the merged side must be authored by Dependabot, AND
  //   (2) the diff must touch ONLY dependency manifests.
  //
  // Be honest about the strength of (1): git author email is self-asserted and
  // NOT cryptographically verified, so `GIT_AUTHOR_EMAIL=...dependabot...`
  // defeats it. It raises the bar rather than sealing it. Condition (2) is the
  // load-bearing one — it bounds any abuse to a pubspec-only diff, which the
  // full CI suite still runs. Both require push access, so this sits at the
  // same trust level as the known-open single-parent bypass, not below it.
  // `.github/workflows/**` is deliberately NOT allowed — letting a bot rewrite
  // the CI that enforces every other gate would contradict promoting test.yml
  // to platform tier in this same batch. Action bumps still need a record.
  //
  // Tested on rawBranch (pre-slug), since recordSlug() maps the slashes away.
  if (isDependabotBranch(rawBranch)) {
    final authors = _git(['log', '--format=%ae', 'HEAD^1..HEAD^2']).split('\n');
    if (!allCommitsAuthoredByDependabot(authors)) {
      exit(die("branch '$rawBranch' is named like a Dependabot branch but its "
          'commits are not authored by Dependabot (authors: '
          "${authors.where((a) => a.trim().isNotEmpty).toSet().join(', ')}). "
          'The exemption is content-verified; a branch name alone earns nothing.'));
    }
    final offending = paths.where((p) => !dependabotAllowedPaths.contains(p));
    if (!dependabotDiffIsManifestOnly(paths)) {
      exit(die("Dependabot branch '$rawBranch' touches paths outside the "
          'dependency manifests: ${offending.join(', ')}. Allowed: '
          '${dependabotAllowedPaths.join(', ')}. An Actions-version bump edits '
          'CI workflow files and therefore still requires a plan-review record '
          '— a bot must not rewrite the CI that enforces every other gate.'));
    }
    stdout.writeln('$tag PASS (Dependabot exemption): branch `$rawBranch` '
        'blast-radius=$maxTier, but every commit is authored by Dependabot and '
        'the diff touches only ${paths.join(', ')}. Record requirement waived; '
        'the CI suite is the control. §4.12 founder decision 2026-07-26.');
    exit(0);
  }

  // 5. Require + validate the record.
  final recFile = File('$_recordsDir/$branch.md');
  if (!recFile.existsSync()) {
    exit(die('branch `$branch` is blast-radius=$maxTier (>= account) but has no '
        'plan-review record at $_recordsDir/$branch.md. §4.12: every >=account plan '
        'needs ×2 context-blind review + a ground-truth audit, recorded here.'));
  }
  final content = recFile.readAsStringSync();
  String? field(String k) =>
      RegExp('^$k:\\s*(.+)\$', multiLine: true).firstMatch(content)?.group(1)?.trim();

  // 5a. The record must NAME the branch it reviewed.
  //
  // recordSlug() maps `/` → `-`, which is not injective: a branch `hold/mechanic`
  // slugs to `hold-mechanic`, an EXISTING converged + bpass-accepted record for
  // unrelated work. Without this cross-check that merge would pass the gate on
  // someone else's review. 68 of the 69 tracked records already carry `branch:`; the one
  // that does not (free-tier-hold-findings.md) is a findings doc no branch
  // resolves to.
  if (!recordBranchFieldMatches(content, rawBranch)) {
    exit(die("${recFile.path}: its `branch:` field does not name '$rawBranch' "
        "(found: '${field('branch') ?? '<absent>'}'). A record vouches for ONE "
        'branch — slug collisions (e.g. `a/b` and `a-b` both → `a-b.md`) must '
        'not let one branch ride another branch\'s review.'));
  }

  final rounds = int.tryParse(field('review_rounds') ?? '') ?? 0;
  final shipDarkBuild = field('tier') == 'ship_dark_build';
  final minRounds = shipDarkBuild ? 1 : 2;
  if (rounds < minRounds) {
    exit(die('${recFile.path}: review_rounds=$rounds (need >= $minRounds'
        '${shipDarkBuild ? ' for tier: ship_dark_build' : ', or tier: ship_dark_build '
            'for a flag-gated build-only commit -- CLAUDE.md §4.12.4'}).'));
  }
  if (field('ground_truth_verified') != 'true') {
    exit(die('${recFile.path}: ground_truth_verified must be true.'));
  }
  if (field('verdict') != 'converged') {
    exit(die('${recFile.path}: verdict must be "converged" (got "${field('verdict')}").'));
  }
  // P1.C: >= platform needs an accepted B-pass; catastrophic also needs Hermes.
  if (_tierRank(maxTier) >= _tierRank('platform') && field('bpass') != 'accepted') {
    exit(die('${recFile.path}: blast-radius=$maxTier requires bpass: accepted.'));
  }
  if (maxTier == 'catastrophic' && field('hermes') != 'accepted') {
    exit(die('${recFile.path}: catastrophic requires hermes: accepted.'));
  }

  // P1.H / F3 (anti-fabrication): when bpass/hermes claim "accepted", require
  // a corresponding reference file that EXISTS and carries `verdict: accepted`.
  // This stops a fabricated `bpass: accepted` with no real review behind it.
  //
  // bpass_review: → path under docs/reviews/ (e.g. docs/reviews/<id>-review.md)
  // hermes_report: → path under docs/audit/ (e.g. docs/audit/<id>-hermes.md)
  if (field('bpass') == 'accepted') {
    final bpassRef = field('bpass_review');
    if (bpassRef == null || bpassRef.isEmpty) {
      exit(die('${recFile.path}: bpass: accepted requires a bpass_review: field '
          'naming a file under docs/reviews/ that exists and contains '
          '`verdict: accepted`.'));
    }
    final bpassFile = File(bpassRef);
    if (!bpassFile.existsSync()) {
      exit(die('${recFile.path}: bpass_review: $bpassRef does not exist on disk.'));
    }
    final bpassContent = bpassFile.readAsStringSync();
    if (!RegExp(r'^verdict:\s*accepted\s*$', multiLine: true).hasMatch(bpassContent)) {
      exit(die('${recFile.path}: bpass_review file $bpassRef does not contain '
          '`verdict: accepted` (line-anchored). Fabricated acceptance is not allowed.'));
    }
  }

  if (field('hermes') == 'accepted') {
    final hermesRef = field('hermes_report');
    if (hermesRef == null || hermesRef.isEmpty) {
      exit(die('${recFile.path}: hermes: accepted requires a hermes_report: field '
          'naming a file under docs/audit/ that exists and contains '
          '`verdict: accepted`.'));
    }
    final hermesFile = File(hermesRef);
    if (!hermesFile.existsSync()) {
      exit(die('${recFile.path}: hermes_report: $hermesRef does not exist on disk.'));
    }
    final hermesContent = hermesFile.readAsStringSync();
    if (!RegExp(r'^verdict:\s*accepted\s*$', multiLine: true).hasMatch(hermesContent)) {
      exit(die('${recFile.path}: hermes_report file $hermesRef does not contain '
          '`verdict: accepted` (line-anchored). Fabricated acceptance is not allowed.'));
    }
  }

  stdout.writeln('$tag PASS: branch `$branch` ($maxTier) has a converged plan-review record '
      '($rounds rounds, ground-truth-verified).');
  exit(0);
}
