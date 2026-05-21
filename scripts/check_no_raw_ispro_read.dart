// scripts/check_no_raw_ispro_read.dart
//
// Gate 34 (Tech-debt audit 2026-05-20, finding C6 prep): assert that no
// production code reads `configBox.get('isPro')` / `config.get('isPro')`
// outside the canonical SubscriptionService.
//
// The audit precedent: `ai_coach_repository.dart:1788` had a raw
// `config.get('isPro') == true` bypass — the only path that wouldn't
// invoke `SubscriptionService.verifyFromServer()` per CLAUDE.md rule 19.
// Silent expiry / forged isPro states would not be caught.
//
// Allowed locations:
//   - lib/core/services/subscription_service.dart (the canonical reader)
//   - test/ + integration_test/ (fixtures)
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final patterns = [
    RegExp(r"""(?:configBox|config)\.get\(['"]isPro['"]\)"""),
    RegExp(r"""Hive\.box\(['"][^'"]*config[^'"]*['"]\)\.get\(['"]isPro['"]\)"""),
  ];

  final violations = <String>[];
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stdout.writeln('[Gate 34] SKIP: lib/ not present.');
    exit(0);
  }

  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Canonical reader is allowed.
    if (entity.path.replaceAll('\\', '/').endsWith('lib/core/services/subscription_service.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
      for (final p in patterns) {
        if (p.hasMatch(line)) {
          violations.add('${entity.path}:${i + 1} → ${line.trim()}');
        }
      }
    }
  }

  final tag = warnOnly ? '[Gate 34 WARN]' : '[Gate 34]';
  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: no raw isPro reads outside SubscriptionService.');
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${violations.length} raw isPro read(s) outside SubscriptionService:');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  stderr.writeln('');
  stderr.writeln('Fix: replace with `SubscriptionService.instance.getStateSnapshot().isPro`.');
  exit(warnOnly ? 0 : 1);
}
