// scripts/check_god_screen_max_lines.dart
//
// Gate 43 — God-screen line ceiling.
//
// Tech-debt audit 2026-05-20 (Code C3/C4) identified multiple
// `lib/**/screens/*_screen.dart` files exceeding 2000 lines. Pure
// monoliths increase merge-conflict surface, mask widget extraction
// opportunities, and slow Riverpod/Hive cognitive load on bug repro.
//
// Rule: no `lib/**/screens/*_screen.dart` file may exceed 800 lines.
// When a screen grows past the ceiling, split it into a sibling
// folder per `screens/<feature>/screen.dart` + sibling `part`-style
// files (see `lib/features/train/screens/active_workout/` for the
// reference layout). The ceiling protects against silent regressions.
//
// Allow-list: screens explicitly tracked for the C4 phase of the same
// audit. The allow-list shrinks by removing entries as their split
// commits land. Once empty, the audit ladder is closed.
//
// Usage: dart run scripts/check_god_screen_max_lines.dart
//
// Wired automatically into pre-commit (scripts/pre-commit.sh dynamic
// loop) and CI via scripts/check_gate_scripts_wired.dart.

import 'dart:io';

/// Maximum line count permitted for any `lib/**/screens/*_screen.dart` file.
const int _maxLines = 800;

/// Transitional allow-list: screens whose split is scheduled for tech-debt
/// audit 2026-05-20 task C4 (and follow-on sweeps). Remove an entry as soon
/// as its split commit lands. The list MUST shrink to empty when the audit
/// ladder closes.
///
/// The original C4 targets (`train_screen.dart`, `profile_screen.dart`,
/// `ai_coach_screen.dart`) landed as sibling folders before C3 ran, so the
/// remaining outliers below are the next ladder up.
///
/// Each entry is the path **relative to repo root**, forward-slash style.
const Set<String> _allowList = <String>{
  'lib/features/auth/screens/sign_in_screen.dart',
  'lib/features/home/screens/home_screen.dart',
  'lib/features/nutrition/screens/nutrition_screen.dart',
  'lib/features/onboarding/screens/onboarding_chat_screen.dart',
  'lib/features/profile/screens/edit_profile_screen.dart',
  'lib/features/profile/screens/reports_screen.dart',
};

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[god-screen-max-lines] FAIL: lib/ does not exist');
    exit(1);
  }

  final violations = <_Violation>[];
  final unusedAllows = Set<String>.from(_allowList);

  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relPath = entity.path.replaceAll(r'\', '/');
    // Only check files named `*_screen.dart` directly under a `screens/` dir.
    if (!relPath.contains('/screens/')) continue;
    if (!relPath.endsWith('_screen.dart')) continue;

    final relFromRoot = relPath.startsWith('./') ? relPath.substring(2) : relPath;
    final lineCount = entity.readAsLinesSync().length;

    if (_allowList.contains(relFromRoot)) {
      unusedAllows.remove(relFromRoot);
      // Allow-listed — still report but do not fail.
      stdout.writeln(
          '[god-screen-max-lines] ALLOW $relFromRoot ($lineCount lines) — '
          'transitional, tracked by tech-debt audit 2026-05-20 / C4.');
      continue;
    }

    if (lineCount > _maxLines) {
      violations.add(_Violation(relFromRoot, lineCount));
    }
  }

  // Stale allow-list entries (file deleted or already split) — surface so
  // the gate hygiene stays clean.
  for (final stale in unusedAllows) {
    stderr.writeln(
        '[god-screen-max-lines] WARN: allow-list entry $stale no longer '
        'matches any file. Remove it from _allowList in this script.');
  }

  if (violations.isEmpty) {
    stdout.writeln('[god-screen-max-lines] OK — no screen exceeds '
        '$_maxLines lines.');
    exit(0);
  }

  stderr.writeln(
      '[god-screen-max-lines] FAIL: ${violations.length} screen(s) exceed '
      '$_maxLines lines. Split each into a sibling folder under '
      '`screens/<feature>/screen.dart` + part files. Reference layout: '
      '`lib/features/train/screens/active_workout/`.');
  for (final v in violations) {
    stderr.writeln('  - ${v.path} (${v.lines} lines)');
  }
  exit(1);
}

class _Violation {
  final String path;
  final int lines;
  _Violation(this.path, this.lines);
}
