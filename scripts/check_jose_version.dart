// scripts/check_jose_version.dart
//
// Gate 28 (Tech-debt audit 2026-05-20, finding D12): assert `jose` is at
// or above the configured minimum version across every Edge Function.
// Crypto lib; minor releases ship CVE fixes; lag is a security smell.
//
// Strategy: grep every supabase/functions/**/*.ts for `deno.land/x/jose@`
// and assert the version is >= MIN_JOSE.
//
// Bump MIN_JOSE here when a new stable lands. Last bump: 5.9.x (audit 2026-05-20).
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:io';

const _minMajor = 5;
const _minMinor = 9;

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final dir = Directory('supabase/functions');
  if (!dir.existsSync()) {
    stdout.writeln('[Gate 28] SKIP: supabase/functions not present.');
    exit(0);
  }

  final pattern = RegExp(r'deno\.land/x/jose@v?(\d+)\.(\d+)(?:\.(\d+))?');
  final violations = <String>[];
  var found = 0;

  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.ts')) continue;
    final content = entity.readAsStringSync();
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final m = pattern.firstMatch(lines[i]);
      if (m == null) continue;
      found++;
      final major = int.parse(m.group(1)!);
      final minor = int.parse(m.group(2)!);
      if (major < _minMajor || (major == _minMajor && minor < _minMinor)) {
        violations.add('${entity.path}:${i + 1} → jose@$major.$minor (need >= $_minMajor.$_minMinor)');
      }
    }
  }

  final tag = warnOnly ? '[Gate 28 WARN]' : '[Gate 28]';
  if (found == 0) {
    stdout.writeln('$tag SKIP: no jose imports detected.');
    exit(0);
  }
  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: $found jose import(s), all >= $_minMajor.$_minMinor.');
    exit(0);
  }
  stderr.writeln('$tag FAIL:');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  exit(warnOnly ? 0 : 1);
}
