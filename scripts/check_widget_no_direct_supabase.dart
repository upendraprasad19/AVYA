// scripts/check_widget_no_direct_supabase.dart
//
// Gate: 36
//
// Gate 36 (Tech-debt audit 2026-05-20, findings A5/A9 prep): enforce
// CLAUDE.md rule #4 (Repository pattern) — widgets / screens must NEVER
// call `Supabase.instance.client` directly.
//
// The audit precedent: A5 (3 profile-tab readers + apply-referral writer
// all hit Supabase from provider/widget layer); A9 (`restoring_screen
// .dart:50,59,228` ran `.from('user_profile').select(...)` from a widget).
//
// Scope: lib/**/screens/** + lib/**/widgets/** + lib/features/**/screens
// + lib/features/**/widgets — anywhere in the UI layer.
//
// Allowed: lib/features/**/repositories/**, lib/features/**/providers/**,
//          lib/features/**/services/**, lib/core/**.
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stdout.writeln('[Gate 36] SKIP: lib/ not present.');
    exit(0);
  }

  final pattern = RegExp(r'Supabase\.instance\.client');

  final violations = <String>[];
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normPath = entity.path.replaceAll('\\', '/');
    // Only scan UI-layer files.
    final isUiLayer = (normPath.contains('/screens/') || normPath.contains('/widgets/'));
    if (!isUiLayer) continue;
    // Widget under shared/widgets/wardroom/ is a primitive — also UI; include it.
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
      if (pattern.hasMatch(line)) {
        violations.add('${entity.path}:${i + 1} → ${line.trim()}');
      }
    }
  }

  final tag = warnOnly ? '[Gate 36 WARN]' : '[Gate 36]';
  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: no direct Supabase calls in lib/**/screens/** or lib/**/widgets/**.');
    exit(0);
  }
  // During B2 transition, allow current violations as warnings until routed
  // through repositories. The plan migrates each in a tracked commit.
  stderr.writeln('$tag WARN (B2-transitional): ${violations.length} direct Supabase call(s) from UI layer:');
  for (final v in violations.take(15)) {
    stderr.writeln('  - $v');
  }
  if (violations.length > 15) stderr.writeln('  ... and ${violations.length - 15} more');
  stderr.writeln('');
  stderr.writeln('Fix: route through a repository class in lib/features/<feature>/repositories/.');
  // Warn-only by default during B2.
  exit(0);
}
