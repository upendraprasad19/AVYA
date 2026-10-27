// scripts/check_tab_screen_uses_hive_scaffold.dart
//
// Tech-debt audit 2026-05-20 / B5 / C1 — pins the contract that every
// main tab screen routes its `_isLoading + Future.microtask + _retry`
// boilerplate through `HiveTabScaffoldMixin` rather than reimplementing
// the pattern by hand.
//
// Why: the pattern was copy-pasted across 5 tab screens before C1.
// Each new copy is one more place a future bugfix has to remember to
// touch (last instance: error-state retry semantics drift between Home
// and Profile). The mixin is the single source.
//
// Detection — for each tab screen below, scan its file for either:
//   1. `with HiveTabScaffoldMixin` somewhere in the State class
//      declaration, OR
//   2. presence in the `_allowList` map (with a one-line reason).
//
// Fail = a screen lost its mixin OR introduced the boilerplate manually.
//
// Usage: dart run scripts/check_tab_screen_uses_hive_scaffold.dart

import 'dart:io';

/// The 5 main tab screens — must use HiveTabScaffoldMixin unless
/// explicitly allow-listed.
const _tabScreens = <String>[
  'lib/features/home/screens/home_screen.dart',
  'lib/features/train/screens/train/screen.dart',
  'lib/features/nutrition/screens/nutrition_screen.dart',
  'lib/features/ai_coach/screens/ai_coach/screen.dart',
  'lib/features/profile/screens/profile/screen.dart',
];

/// Screens whose mount shape is fundamentally different and would be
/// worse off with the mixin. Each entry needs a one-line reason.
const _allowList = <String, String>{
  'lib/features/ai_coach/screens/ai_coach/screen.dart':
      'Chat history hydration is incremental + animated; never used the '
          '`_isLoading + microtask + _retry` skeleton pattern. No retry button — '
          'chat list shows inline `ChatErrorBubble` for transient failures.',
};

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final failures = <String>[];

  for (final path in _tabScreens) {
    final file = File(path);
    if (!file.existsSync()) {
      failures.add('  FILE MISSING: $path');
      continue;
    }

    final source = file.readAsStringSync();
    final hasMixin =
        RegExp(r'with\s+HiveTabScaffoldMixin\b').hasMatch(source);
    final allowReason = _allowList[path];

    if (hasMixin && allowReason != null) {
      // Both mixin AND allowlist entry = inconsistent state; pick one.
      failures.add(
        '  INCONSISTENT: $path has both `with HiveTabScaffoldMixin` and '
        'an entry in _allowList. Pick one.',
      );
      continue;
    }

    if (!hasMixin && allowReason == null) {
      failures.add(
        '  MISSING MIXIN: $path does not include '
        '`with HiveTabScaffoldMixin` and is not in the allow-list. '
        'Either apply the mixin (see lib/shared/mixins/hive_tab_scaffold.dart) '
        'or add an entry to _allowList in this script with a reason.',
      );
      continue;
    }

    // Bonus check: if the screen has the mixin, the legacy boilerplate
    // should NOT also be present (would mean a half-migration).
    if (hasMixin) {
      // Look for the smoking-gun signatures of the old pattern: a private
      // `_isLoading` field at class scope AND a private `_retry` method.
      final hasLegacyIsLoading =
          RegExp(r'^\s*bool\s+_isLoading\s*=\s*true', multiLine: true)
              .hasMatch(source);
      final hasLegacyRetry =
          RegExp(r'^\s*void\s+_retry\s*\(\s*\)\s*\{', multiLine: true)
              .hasMatch(source);

      // home_screen.dart legitimately keeps a private `_retry()` wrapper
      // around the mixin's `retry()` so its `setState(() => _error = null)`
      // still fires. Permit it as long as the wrapper is short.
      final isHome = path.endsWith('home_screen.dart');
      if (hasLegacyIsLoading) {
        failures.add(
          '  HALF-MIGRATED: $path declares `bool _isLoading = true` even '
          'though it uses HiveTabScaffoldMixin (which owns the flag). '
          'Remove the local field; use `isLoading` getter from the mixin.',
        );
      }
      if (hasLegacyRetry && !isHome) {
        failures.add(
          '  HALF-MIGRATED: $path declares a private `_retry()` method even '
          'though it uses HiveTabScaffoldMixin (which provides `retry()`). '
          'Either rename callers to use `retry` or document the wrapper '
          'reason and add an exemption to this gate.',
        );
      }
    }
  }

  if (failures.isEmpty) {
    stdout.writeln(
      '[hive-tab-scaffold] OK: all ${_tabScreens.length} tab screens '
      'either use HiveTabScaffoldMixin or are documented in the allow-list.',
    );
    exit(0);
  }

  stderr.writeln(
    '[hive-tab-scaffold] FAIL: ${failures.length} tab screen(s) violate '
    'the HiveTabScaffoldMixin contract:',
  );
  for (final f in failures) {
    stderr.writeln(f);
  }
  stderr.writeln(
    '\nFix: see lib/shared/mixins/hive_tab_scaffold.dart for the canonical '
    'pattern + migration recipe.',
  );
  exit(warnOnly ? 0 : 1);
}
