// scripts/check_code_review_pass_exists.dart
//
// Gate (Track 1 of the 2026-05-28 six-industry-gap closure batch).
//
// For staged commits whose max blast-radius is `catastrophic`, require a
// review-acceptance file at docs/reviews/<staging-hash>-review.md with
// `verdict: accepted` in the frontmatter.
//
// The staging hash is the SHA256 of the staged diff truncated to 12 chars.
//
// Exit 0 = pass (blast-radius < catastrophic, OR catastrophic + accepted review).
// Exit 1 = fail (catastrophic with no accepted review).
// --warn-only flag for the 24h soft-rollout window.
//
// BRANCH SYNC (landing C1 of the merge-conflict-treadmill plan, closes OI-413; plan
// docs/plans/sync-merge-scope.md, rule and trust argument in scripts/merge_scope_lib.dart).
// While a merge of an ancestor of refs/remotes/origin/main is pending, only the staged paths
// whose index entry equals NEITHER HEAD's NOR origin/main's entry are graded: the rest is
// either already in the branch or already on main. Every failed precondition falls back to the
// full staged list (the old rule) and says why in a NOTE; the pre-commit loop discards this
// gate's output, so read the NOTE by re-running `dart run scripts/check_code_review_pass_exists.dart`
// while the merge is pending. The hash and the review file name still derive from the FULL staged
// diff; the reviewer scopes the review to the graded paths the NOTE lists.

import 'dart:io';

import 'blast_radius_content_rules_lib.dart';
import 'merge_scope_lib.dart';

const _registryPath = 'docs/blast_radius.yaml';
const _reviewsDir = 'docs/reviews';

class TierRule {
  final String glob;
  final String tier;
  TierRule(this.glob, this.tier);
}

List<TierRule> parseRules(String content) {
  final rules = <TierRule>[];
  var inPaths = false;
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line == 'paths:') {
      inPaths = true;
      continue;
    }
    if (!inPaths) continue;
    if (!line.startsWith('-')) continue;
    final g = RegExp(r'glob:\s*"([^"]+)"').firstMatch(line);
    final t = RegExp(r'tier:\s*([a-z]+)').firstMatch(line);
    if (g != null && t != null) rules.add(TierRule(g.group(1)!, t.group(1)!));
  }
  return rules;
}

RegExp globToRegExp(String glob) {
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
  // dotAll: `.` must also match a line terminator, or a path with one in its name matches no glob and
  // falls to the default tier (check_plan_review_record_exists.dart has the same flag).
  return RegExp(buf.toString(), dotAll: true);
}

const _tierOrder = ['feature', 'account', 'platform', 'catastrophic'];
int tierRank(String t) => _tierOrder.indexOf(t);

/// Reads a path's STAGED (index) blob content via `git show :<path>` —
/// NOT the working-tree file. This gate inspects `git diff --cached`, so it
/// must judge the content that's actually about to be committed: staging a
/// SECURITY DEFINER migration then further editing the working copy
/// (without re-staging) before `git commit` would otherwise let the gate
/// read the edited-clean working file while the STAGED blob — the one that
/// actually lands in the commit — still carries the dangerous content.
bool _stagedFileExists(String path) =>
    Process.runSync('git', ['cat-file', '-e', ':$path']).exitCode == 0;

String _stagedFileContent(String path) {
  final r = Process.runSync('git', ['show', ':$path']);
  if (r.exitCode != 0) {
    throw StateError('git show :$path failed: ${r.stderr}');
  }
  return r.stdout as String;
}

/// Staged paths, or NULL when git could not answer.
///
/// B-pass finding 4: this returned `[]` on failure, which the caller read as
/// "no staged changes" and exited 0 — passing a catastrophic-tier commit
/// through untouched. Same class OI-72 fixes twice further down this very file
/// (the SECURITY DEFINER content read and the review-artifact read), left alone
/// at the earliest call site. Flagged as pre-existing rather than introduced
/// here; fixed anyway, because it sits three lines from its own cure.
Future<List<String>?> stagedPaths() async {
  // OI-337 for this gate: `-z` (no C-quoting), `--no-renames` (a rename out of a catastrophic path
  // lists its source), `--ignore-submodules=none` (a `.gitmodules` `ignore = all` must not hide a
  // gitlink) and a strict UTF-8 decode, all through merge_scope_lib.dart's one parser. A malformed
  // path returns null, which the caller turns into a FAIL.
  final result = await Process.run('git', stagedPathsArgv, stdoutEncoding: null);
  if (result.exitCode != 0) return null;
  return parseNulPaths(result.stdout as List<int>);
}

/// The production [GitRun]: the gate's own environment (a hook's `GIT_INDEX_FILE`, and `GIT_DIR` in
/// a linked worktree, are wanted so the diff reads the index `git diff --cached` reads) and raw bytes.
({int exitCode, List<int> stdout})? _runGit(List<String> args) {
  try {
    final r = Process.runSync('git', args, stdoutEncoding: null, stderrEncoding: null);
    return (exitCode: r.exitCode, stdout: r.stdout as List<int>);
  } on ProcessException {
    return null;
  }
}

/// The production [ReadMergeHead]: null when the file is absent, a thrown error when it is not
/// readable (a directory, a permission error): the lib turns that into a `Fallback`.
String? _readMergeHead(String path) {
  try {
    return File(path).readAsStringSync();
  } on PathNotFoundException {
    return null;
  }
}

/// At a FAIL in a branch sync the NOTE's 20-name cut is not enough: print every graded path, one per
/// line and escaped, so the reviewer scopes the review to exactly what was graded.
void _printGradedPaths(MergeScope scope) {
  if (scope is! Scoped) return;
  stderr.writeln('  Branch sync: ${scope.paths.length} graded path(s) (the review file is still named for the hash '
      'of the FULL staged diff):');
  for (final p in scope.paths) {
    stderr.writeln('    ${escapeForNote(p)}');
  }
}

Future<String> stagedDiffHash() async {
  // Pipe `git diff --cached` through `git hash-object --stdin` to get a stable
  // sha1 of the staged diff. No external Dart package needed.
  //
  // OI-72: `docs/reviews/**` is EXCLUDED from the hash. The review file is
  // named after this hash, so staging it — which is what makes it part of the
  // commit — would move the hash and rename the file it is meant to satisfy.
  // Excluding the directory breaks that circularity, and is what lets the
  // existence check below read the STAGED blob instead of the working tree.
  //
  // OI-162 slice 4 B-pass, Addendum (2026-09-11): `.claude/skills/code-review/
  // SKILL.md` is ALSO excluded, for the identical self-reference reason.
  // §5.1's own gate (`check_skill_tuning_history.dart`) REQUIRES a same-dated
  // Tuning-history entry in that file in the SAME commit as any new
  // `docs/reviews/**.md` — so staging the required entry moved this gate's
  // hash exactly the way staging the review itself would have, and there is
  // no clean iterative fix (renaming the review to match then re-editing the
  // SKILL.md entry to cite the new name moves the hash again, indefinitely).
  // Discovered live: a real B-pass dispatch on this exact batch staged its
  // required tuning entry and the gate demanded a DIFFERENT filename
  // (`0c077bc09fa2` vs the `12408db06b47` it was dispatched against) with no
  // indication why. Excluding the one file every catastrophic review is
  // mechanically required to edit closes the loop the same way OI-72 closed
  // it for the review file itself.
  //
  // A1 (2026-10-24): the required tuning entry now lives INSIDE the review file, a
  // path this hash already excludes, so a new review no longer stages any other file
  // for §5.1. All three exclusions stay (they are pinned by
  // review_gate_staged_content_not_working_tree_test.dart) because a legacy-shaped
  // commit and a SKILL.md template edit can still touch them.
  //
  // f4d1b7: capture the diff as RAW BYTES (`stdoutEncoding: null`) and feed them
  // verbatim. Pre-fix it decoded stdout to a String (via SystemEncoding — the
  // system code page, cp1252 on Windows) then hashed `.codeUnits` (UTF-16);
  // both steps corrupt non-ASCII bytes, so for any diff containing non-ASCII
  // (e.g. an emoji in a comment) the gate's hash diverged from
  // `git diff --cached | git hash-object --stdin` and the catastrophic review
  // file could NEVER be matched. Raw bytes are byte-identical to git's own hash.
  // `:(top)` (aka `:/`) makes both halves repo-root-relative.
  //
  // HONEST HISTORY (round-2 review P2-C corrected round-1's P3-2): the ORIGINAL
  // code passed no pathspec at all, and `git diff --cached` is NOT CWD-limited,
  // so there was no bug to fix. Adding the exclusion is what introduced a
  // pathspec — and a bare `.` WOULD have been CWD-relative. `:(top)` keeps the
  // exclusion without introducing that sensitivity. Recorded rather than left
  // reading as if it had fixed a real defect.
  final diff = await Process.run(
      'git',
      [
        'diff',
        '--cached',
        // The graded set is read with --ignore-submodules=none (stagedPathsArgv); the hash must see the same
        // gitlinks, or a staged gitlink hidden by `.gitmodules ignore = all` is graded catastrophic while the
        // hash is that of an EMPTY diff, the same review name for every gitlink value. Identical output to the
        // flagless call whenever no ignore configuration exists.
        '--ignore-submodules=none',
        '--',
        ':(top)',
        ':(top,exclude)$_reviewsDir',
        ':(top,exclude).claude/skills/code-review/SKILL.md',
        ':(top,exclude).claude/skills/code-review/tuning-history.md',
      ],
      stdoutEncoding: null);
  if (diff.exitCode != 0) return '';
  final bytes = (diff.stdout as List<int>);
  final hash = await Process.start('git', ['hash-object', '--stdin']);
  hash.stdin.add(bytes);
  await hash.stdin.close();
  final out = await hash.stdout.transform(const SystemEncoding().decoder).join();
  await hash.exitCode;
  final trimmed = out.trim();
  return trimmed.length >= 12 ? trimmed.substring(0, 12) : trimmed;
}

Future<void> main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[Gate WARN]' : '[Gate]';

  final regFile = File(_registryPath);
  if (!regFile.existsSync()) {
    // No registry — can't compute blast-radius. PASS (advisory).
    stdout.writeln('$tag SKIP: $_registryPath not found.');
    exit(0);
  }
  final rules = parseRules(regFile.readAsStringSync());

  final paths = await stagedPaths();
  if (paths == null) {
    stderr.writeln('$tag FAIL: could not read the staged paths (`git diff --cached --name-only -z` '
        'failed, or a path is not valid UTF-8). Refusing to read that as "no staged changes" — that '
        'exits 0 and waves a catastrophic-tier commit through.');
    exit(warnOnly ? 0 : 1);
  }
  if (paths.isEmpty) {
    stdout.writeln('$tag SKIP: no staged changes.');
    exit(0);
  }

  // Branch sync: while a merge of origin/main is pending, grade only the paths that match neither
  // HEAD nor origin/main. Decided AFTER the "no staged changes" skip (a `-s ours` merge stages
  // nothing and has always skipped) and used ONLY for the tier loop below: the hash and the review
  // path still come from the full staged diff.
  final scope = computeMergeScope(_runGit, readMergeHead: _readMergeHead, staged: paths);
  final scopeNote = formatScopeNote(scope, paths.length);
  if (scopeNote != null) stdout.writeln('$tag NOTE: $scopeNote');
  final classified = scope is Scoped ? scope.paths : paths;

  var maxTier = 'feature';
  for (final p in classified) {
    String tier = 'feature';
    for (final rule in rules) {
      if (globToRegExp(rule.glob).hasMatch(p)) {
        tier = rule.tier;
        break;
      }
    }
    if (tier != 'catastrophic' &&
        contentForcesCatastrophic(p,
            fileExists: _stagedFileExists, readFile: _stagedFileContent)) {
      stdout.writeln('$tag NOTE: $p: SECURITY DEFINER content forces '
          'catastrophic (path-tier was $tier).');
      tier = 'catastrophic';
    }
    if (tierRank(tier) > tierRank(maxTier)) maxTier = tier;
  }

  if (maxTier != 'catastrophic') {
    final what = scope is Scoped ? 'max blast-radius of the graded set' : 'max blast-radius';
    stdout.writeln('$tag PASS: $what = $maxTier (review-acceptance gate only applies to catastrophic).');
    exit(0);
  }

  final hash = await stagedDiffHash();
  if (hash.isEmpty) {
    stderr.writeln('$tag FAIL: could not compute staged diff hash.');
    exit(warnOnly ? 0 : 1);
  }

  // OI-72: read the review from the STAGED blob, not the working tree.
  //
  // The asymmetry this closes: the hash came from `git diff --cached` (the
  // index) while the file was checked with `File(...).existsSync()` (the working
  // tree). An UNTRACKED docs/reviews/<hash>-review.md therefore satisfied the
  // catastrophic gate without ever entering history — and because it was
  // untracked it contributed nothing to the staged diff, so the hash it was
  // named after never moved. Three untracked `docs/reviews/*-review.md` files
  // were sitting in the working tree when this was found.
  //
  // The helpers used here already exist a few lines up, with a comment
  // describing exactly this class — they were applied to the SECURITY DEFINER
  // content check and not to the review file itself.
  final reviewPath = '$_reviewsDir/$hash-review.md';
  if (!_stagedFileExists(reviewPath)) {
    final untracked = File(reviewPath).existsSync();
    stderr.writeln('$tag FAIL: blast-radius=catastrophic requires a STAGED review file at $reviewPath');
    if (untracked) {
      stderr.writeln('  The file exists in the working tree but is not staged. '
          '`git add $reviewPath` — an unstaged review does not enter history, '
          'so nothing records that this commit was reviewed.');
    } else {
      stderr.writeln('  Run `/review` to generate it, then triage findings, then mark `verdict: accepted` in the frontmatter.');
    }
    stderr.writeln('  (The hash excludes $_reviewsDir/, so staging the review does not rename it.)');
    _printGradedPaths(scope);
    exit(warnOnly ? 0 : 1);
  }

  final content = _stagedFileContent(reviewPath);
  final verdictMatch = RegExp(r'^verdict:\s*([a-z_]+)', multiLine: true).firstMatch(content);
  if (verdictMatch == null || verdictMatch.group(1) != 'accepted') {
    stderr.writeln('$tag FAIL: staged review file $reviewPath exists but verdict is not "accepted".');
    stderr.writeln('  Triage all findings then change frontmatter to `verdict: accepted` AND re-stage it.');
    _printGradedPaths(scope);
    exit(warnOnly ? 0 : 1);
  }

  stdout.writeln('$tag PASS: catastrophic commit has an accepted, STAGED review at $reviewPath.');
  exit(0);
}
