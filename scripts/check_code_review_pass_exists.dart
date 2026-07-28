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

import 'dart:io';

import 'blast_radius_content_rules_lib.dart';

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
  return RegExp(buf.toString());
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
  final result = await Process.run('git', ['diff', '--cached', '--name-only']);
  if (result.exitCode != 0) return null;
  return (result.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
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
      ['diff', '--cached', '--', ':(top)', ':(top,exclude)$_reviewsDir'],
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
    stderr.writeln('$tag FAIL: `git diff --cached --name-only` failed. Refusing '
        'to read a git error as "no staged changes" — that exits 0 and waves a '
        'catastrophic-tier commit through.');
    exit(warnOnly ? 0 : 1);
  }
  if (paths.isEmpty) {
    stdout.writeln('$tag SKIP: no staged changes.');
    exit(0);
  }

  var maxTier = 'feature';
  for (final p in paths) {
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
    stdout.writeln('$tag PASS: max blast-radius = $maxTier (review-acceptance gate only applies to catastrophic).');
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
    exit(warnOnly ? 0 : 1);
  }

  final content = _stagedFileContent(reviewPath);
  final verdictMatch = RegExp(r'^verdict:\s*([a-z_]+)', multiLine: true).firstMatch(content);
  if (verdictMatch == null || verdictMatch.group(1) != 'accepted') {
    stderr.writeln('$tag FAIL: staged review file $reviewPath exists but verdict is not "accepted".');
    stderr.writeln('  Triage all findings then change frontmatter to `verdict: accepted` AND re-stage it.');
    exit(warnOnly ? 0 : 1);
  }

  stdout.writeln('$tag PASS: catastrophic commit has an accepted, STAGED review at $reviewPath.');
  exit(0);
}
