// scripts/check_profile_write_service_only.dart
//
// Gate 35 (Tech-debt audit 2026-05-20, finding A4 prep): assert that no
// production code outside `ProfileWriteService` writes to userBox under
// the `profile` key (or its sub-keys).
//
// The audit precedent: `userBox.put('profile', ...)` was scattered across
// home_provider.dart:773, tool_dispatcher.dart:901, auth_provider.dart
// :604, :627, :742. No `ProfileWriteService` existed — goal/weight writes
// could silently bypass any future invariant (BMR recompute, badge
// revalidation, etc.).
//
// Allowed locations:
//   - lib/features/profile/services/profile_write_service.dart
//   - lib/core/services/body_fat_default_healer.dart (Unit 4 c3f2d8) — a one-time
//     boot heal that nulls the fabricated onboarding body_fat 18.0 default. It is
//     a DELIBERATE exception: it must NOT route through ProfileWriteService's
//     sync/recompute fan-out (founder-locked: no daily_calories backfill), must
//     NOT bump updated_at (a system heal, not a user edit), and uses a specific
//     cloud-first ordering. Fully tested (body_fat_default_heal_test.dart); the
//     profile READ is registered in the user_full_name reader manifest.
//   - test/ + integration_test/ (fixtures only; production lib/ excluded)
//
// Exit 0 = pass / no ProfileWriteService yet (initial warn mode).
// Exit 1 = fail: write outside canonical service.

import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stdout.writeln('[Gate 35] SKIP: lib/ not present.');
    exit(0);
  }

  final canonical = File('lib/features/profile/services/profile_write_service.dart');
  final canonicalExists = canonical.existsSync();

  // Pattern: any `userBox.put('profile', ...)` or `.put("profile", ...)`.
  final pattern = RegExp(r"""userBox\.put\(\s*['"]profile['"]""");

  final violations = <String>[];
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normPath = entity.path.replaceAll('\\', '/');
    // Canonical writer + the documented body-fat heal exception (see header).
    const allowed = <String>[
      'lib/features/profile/services/profile_write_service.dart',
      'lib/core/services/body_fat_default_healer.dart',
    ];
    if (allowed.any(normPath.endsWith)) continue;
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

  final tag = warnOnly ? '[Gate 35 WARN]' : '[Gate 35]';
  if (violations.isEmpty) {
    if (!canonicalExists) {
      stdout.writeln('$tag PASS (transitional): no profile writes detected; ProfileWriteService not yet created. Will tighten once the service lands.');
    } else {
      stdout.writeln('$tag PASS: all `userBox.put(\'profile\')` writes go through ProfileWriteService.');
    }
    exit(0);
  }
  if (!canonicalExists) {
    // ProfileWriteService doesn't exist yet — surfaced as advisory during B2 transition.
    stderr.writeln('$tag WARN (B2-transitional): ProfileWriteService not yet created; ${violations.length} profile write(s) outside canonical service. Routing in B2 step 3.');
    for (final v in violations.take(10)) {
      stderr.writeln('  - $v');
    }
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${violations.length} profile write(s) outside ProfileWriteService:');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  exit(warnOnly ? 0 : 1);
}
