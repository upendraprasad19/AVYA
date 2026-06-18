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
  final subject = _git(['log', '-1', '--format=%s', 'HEAD']);
  final bm = RegExp(r"Merge branch '([^']+)'").firstMatch(subject);
  if (bm == null) {
    exit(die("could not recover merged branch from subject: '$subject' "
        "(expected \"Merge branch 'X'\"). Use --no-ff merges with the default subject."));
  }
  final branch = bm.group(1)!.split('/').last; // strip any remote/ prefix

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
    final t = _tierFor(p, reg);
    if (_tierRank(t) > _tierRank(maxTier)) maxTier = t;
  }

  if (_tierRank(maxTier) < _tierRank('account')) {
    stdout.writeln('$tag PASS: branch `$branch` blast-radius=$maxTier (< account; no record required).');
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

  final rounds = int.tryParse(field('review_rounds') ?? '') ?? 0;
  if (rounds < 2) {
    exit(die('${recFile.path}: review_rounds=$rounds (need >= 2).'));
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

  stdout.writeln('$tag PASS: branch `$branch` ($maxTier) has a converged plan-review record '
      '($rounds rounds, ground-truth-verified).');
  exit(0);
}
