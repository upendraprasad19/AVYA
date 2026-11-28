// scripts/blast_radius_from_diff.dart
//
// Track 2 helper: compute the max blast-radius tier from staged paths.
// Reads docs/blast_radius.yaml (declaration-order, first-match-wins).
//
// Usage:
//   # default — reads `git diff --cached --name-only` from the current repo
//   dart run scripts/blast_radius_from_diff.dart
//
//   # explicit path list (one per line on stdin)
//   git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -
//
//   # arbitrary file list as args
//   dart run scripts/blast_radius_from_diff.dart lib/features/auth/foo.dart
//
// Output: a single line — `Blast-radius: <tier>` — or empty if no paths.
// Exit 0 always (informational helper, not a gate).

import 'dart:convert';
import 'dart:io';

import 'blast_radius_content_rules_lib.dart';

const _registryPath = 'docs/blast_radius.yaml';
const _tierOrder = ['feature', 'account', 'platform', 'catastrophic'];

class TierRule {
  final String glob;
  final String tier;
  TierRule(this.glob, this.tier);
}

/// Minimal YAML reader — we control the registry format, so this avoids a
/// dependency on package:yaml.
({String defaultTier, List<TierRule> rules}) parseRegistry(String content) {
  final lines = content.split('\n');
  String defaultTier = 'feature';
  final rules = <TierRule>[];
  var inPaths = false;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('default_tier:')) {
      defaultTier = line.split(':')[1].trim();
      continue;
    }
    if (line == 'paths:') {
      inPaths = true;
      continue;
    }
    if (!inPaths) continue;
    if (!line.startsWith('-')) continue;
    // Expected: - { glob: "...", tier: ... }
    final globMatch = RegExp(r'glob:\s*"([^"]+)"').firstMatch(line);
    final tierMatch = RegExp(r'tier:\s*([a-z]+)').firstMatch(line);
    if (globMatch != null && tierMatch != null) {
      rules.add(TierRule(globMatch.group(1)!, tierMatch.group(1)!));
    }
  }
  return (defaultTier: defaultTier, rules: rules);
}

/// Shell-style glob → RegExp. `*` matches one path segment; `**` matches any.
RegExp globToRegExp(String glob) {
  final buf = StringBuffer('^');
  var i = 0;
  while (i < glob.length) {
    final ch = glob[i];
    if (ch == '*' && i + 1 < glob.length && glob[i + 1] == '*') {
      buf.write('.*');
      i += 2;
      // Skip a following slash so `lib/**` matches `lib/foo`.
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

String tierFor(String path, ({String defaultTier, List<TierRule> rules}) reg) {
  for (final rule in reg.rules) {
    if (globToRegExp(rule.glob).hasMatch(path)) return rule.tier;
  }
  return reg.defaultTier;
}

int tierRank(String tier) => _tierOrder.indexOf(tier);

Future<List<String>> stagedPaths() async {
  final result = await Process.run('git', ['diff', '--cached', '--name-only']);
  if (result.exitCode != 0) return [];
  return (result.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

Future<List<String>> stdinPaths() async {
  final lines = <String>[];
  await for (final line in stdin.transform(SystemEncoding().decoder).transform(const LineSplitter())) {
    final t = line.trim();
    if (t.isNotEmpty) lines.add(t);
  }
  return lines;
}

void main(List<String> args) async {
  final reg = parseRegistry(File(_registryPath).readAsStringSync());

  List<String> paths;
  if (args.length == 1 && args[0] == '-') {
    paths = await stdinPaths();
  } else if (args.isNotEmpty) {
    // Positional args are FILE PATHS, not git refs. Passing commit SHAs
    // (e.g. `blast_radius_from_diff.dart <base> <head>`) silently treated them
    // as nonexistent filenames → each matched no glob → fell to default_tier
    // (feature), masking a real >=account range (the 2026-06-25 Unit-C miss).
    // Detect commit-ish args and FAIL LOUD with the correct stdin-range usage.
    final refLike = args
        .where((a) => Process.runSync(
                'git', ['rev-parse', '--verify', '--quiet', '$a^{commit}'])
            .exitCode ==
            0)
        .toList();
    if (refLike.isNotEmpty) {
      stderr.writeln(
          'blast_radius_from_diff: positional args are FILE PATHS, not git refs. '
          'These resolve to commits: ${refLike.join(', ')}.\n'
          'To classify a commit/branch range, pipe the changed file list:\n'
          '  git diff --name-only <base> <head> | dart run scripts/blast_radius_from_diff.dart -');
      exit(2);
    }
    paths = args;
  } else {
    paths = await stagedPaths();
  }

  if (paths.isEmpty) {
    // No staged changes; emit nothing (helper, not gate).
    return;
  }

  var maxTier = 'feature';
  for (final p in paths) {
    var t = tierFor(p, reg);
    if (tierRank('catastrophic') > tierRank(t) && contentForcesCatastrophic(p)) {
      // Prints to STDOUT rather than stderr (this script is invoked with
      // `2>/dev/null` by prepare-commit-msg/pre-commit/pre-push). Note those
      // three sites ALSO pipe stdout through `grep -oE 'Blast-radius: ...'`
      // to extract just the tier, so this NOTE line is visible in a raw
      // `dart run` but stripped in the local-hook pipelines — the escalated
      // TIER itself still propagates correctly either way, which is what
      // those hooks act on; this line is a diagnostic nicety, not a gate.
      stdout.writeln('[blast-radius content-rule] $p: SECURITY DEFINER '
          'content forces catastrophic (path-tier was $t)');
      t = 'catastrophic';
    }
    if (tierRank(t) > tierRank(maxTier)) maxTier = t;
  }
  stdout.writeln('Blast-radius: $maxTier');
}
