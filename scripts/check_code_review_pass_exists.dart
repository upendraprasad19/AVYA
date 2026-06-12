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

Future<List<String>> stagedPaths() async {
  final result = await Process.run('git', ['diff', '--cached', '--name-only']);
  if (result.exitCode != 0) return [];
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
  // f4d1b7: capture the diff as RAW BYTES (`stdoutEncoding: null`) and feed them
  // verbatim. Pre-fix it decoded stdout to a String (via SystemEncoding — the
  // system code page, cp1252 on Windows) then hashed `.codeUnits` (UTF-16);
  // both steps corrupt non-ASCII bytes, so for any diff containing non-ASCII
  // (e.g. an emoji in a comment) the gate's hash diverged from
  // `git diff --cached | git hash-object --stdin` and the catastrophic review
  // file could NEVER be matched. Raw bytes are byte-identical to git's own hash.
  final diff = await Process.run('git', ['diff', '--cached'],
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

  final reviewFile = File('$_reviewsDir/$hash-review.md');
  if (!reviewFile.existsSync()) {
    stderr.writeln('$tag FAIL: blast-radius=catastrophic requires a review file at $_reviewsDir/$hash-review.md');
    stderr.writeln('  Run `/review` to generate it, then triage findings, then mark `verdict: accepted` in the frontmatter.');
    exit(warnOnly ? 0 : 1);
  }

  final content = reviewFile.readAsStringSync();
  final verdictMatch = RegExp(r'^verdict:\s*([a-z_]+)', multiLine: true).firstMatch(content);
  if (verdictMatch == null || verdictMatch.group(1) != 'accepted') {
    stderr.writeln('$tag FAIL: review file ${reviewFile.path} exists but verdict is not "accepted".');
    stderr.writeln('  Triage all findings then change frontmatter to `verdict: accepted`.');
    exit(warnOnly ? 0 : 1);
  }

  stdout.writeln('$tag PASS: catastrophic commit has accepted review at ${reviewFile.path}.');
  exit(0);
}
