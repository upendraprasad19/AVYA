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
    final t = tierFor(p, reg);
    if (tierRank(t) > tierRank(maxTier)) maxTier = t;
  }
  stdout.writeln('Blast-radius: $maxTier');
}
