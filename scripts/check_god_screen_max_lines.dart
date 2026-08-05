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
  // REMOVED 2026-08-03 (Unit B, closes OI-84) —
  // lib/features/train/screens/graduation_screen.dart. It was the FIRST entry
  // this list ever took (2026-08-01, founder-authorized) and it is now gone, so
  // the one-way ratchet is back in the removal direction it has always had.
  //
  // The split that earned the removal: the ~120-line locked generate +
  // commitPhaseAdvance block moved to runGraduationPhaseAdvance in
  // lib/shared/services/pro_phase_advance.dart (beside the other three advance
  // paths), and the ~250-line phase-2 preview UI moved to
  // lib/features/train/widgets/phase2_preview_card.dart. 909 → 552 lines, under
  // the ceiling honestly rather than by exemption.
  //
  // The preview extraction was NOT in OI-84's recommended shape. The hoist
  // alone landed the file at ~791 — nine lines of margin, which is the same
  // condition that created OI-84 in the first place (it sat SIX under, so a fix
  // could not touch it at all). OI-84's own "~770" estimate had gone stale when
  // Unit A grew the file to 909.
  //
  // REMOVED 2026-08-05 (repo-gate-pattern-sweep, diagnose e7c3b9) —
  // lib/features/auth/screens/restoring_screen.dart. It was added 2026-08-03
  // (founder-authorized in chat, restore-onboarding-signin-fix batch) because
  // a3f6d9's fix pushed the file to 824. A further comment trim took it to
  // 791, so the exemption is no longer load-bearing and the gate protects the
  // file again on its own terms.
  //
  // This does NOT close OI-88, and the entry is deliberately not being
  // presented as if it did. OI-88's stated fix shape is a SPLIT into a sibling
  // folder (the key-migrator imports + _healAfterRestoreInBackground's
  // reconciler fan-out, and/or _AnimatedDotsState, which has no dependency on
  // _RestoringScreenState's fields), with the allow-list entry removed in the
  // same commit. What actually happened here is a comment trim: no code moved,
  // no file was created, and the structural debt is untouched. OI-88 stays
  // OPEN, narrowed to that residual.
  //
  // Note the margin: 791 leaves NINE lines. That is the same condition the
  // graduation_screen note above records as what created OI-84 in the first
  // place — a file so close to the ceiling that the next fix cannot touch it.
  // Removing the exemption is still strictly better than keeping it (the gate
  // now actually watches this file), but the next change to it will likely
  // have to do the split first rather than trim further.
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
