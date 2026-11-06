// scripts/check_blast_radius_coverage.dart
//
// Gate (Track 2 of the six-industry-gap closure batch).
//
// Asserts that every top-level directory under `lib/features/`,
// `lib/core/services/`, `supabase/functions/`, and `supabase/migrations/`
// has at least one glob in `docs/blast_radius.yaml` that matches it.
//
// Without this gate, new feature directories silently inherit the
// `default_tier: feature` — which is wrong for new auth / payment / sync code.
//
// Exit 0 = pass. Exit 1 = fail (uncovered directories). `--warn-only` = report only.

import 'dart:io';

const _registryPath = 'docs/blast_radius.yaml';
const _watchedRoots = [
  'lib/features',
  'lib/core/services',
  'supabase/functions',
  'supabase/migrations',
];

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

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final file = File(_registryPath);
  if (!file.existsSync()) {
    stderr.writeln('[Gate] FAIL: $_registryPath not found');
    exit(warnOnly ? 0 : 1);
  }
  final rules = parseRules(file.readAsStringSync());
  final regexes = rules.map((r) => globToRegExp(r.glob)).toList();

  final uncovered = <String>[];
  for (final root in _watchedRoots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync()) {
      if (entity is! Directory && entity is! File) continue;
      // Build a representative path inside this entry.
      final rel = entity.path.replaceAll('\\', '/');
      final probe = entity is Directory ? '$rel/probe.dart' : rel;
      final matched = regexes.any((re) => re.hasMatch(probe));
      if (!matched) {
        uncovered.add(rel);
      }
    }
  }

  final tag = warnOnly ? '[Gate WARN]' : '[Gate]';
  if (uncovered.isEmpty) {
    stdout.writeln('$tag PASS: blast_radius.yaml covers all top-level entries under ${_watchedRoots.join(", ")}.');
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${uncovered.length} path(s) lack any rule in $_registryPath:');
  for (final p in uncovered.take(20)) {
    stderr.writeln('  - $p');
  }
  if (uncovered.length > 20) {
    stderr.writeln('  ... and ${uncovered.length - 20} more');
  }
  stderr.writeln('');
  stderr.writeln('Fix: add a glob entry in $_registryPath for each uncovered path.');
  exit(warnOnly ? 0 : 1);
}
