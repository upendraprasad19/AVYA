// scripts/check_device_tests_exist.dart
//
// Gate: 54
//
// Gate 54 (tech-debt audit 2026-05-20 / T1): assert that the 4 named
// Patrol device-CI flow files exist in `integration_test/device/` and
// each contains its named feature keyword.
//
// The 4 flows pin critical end-to-end paths that vanilla flutter_test
// cannot cover (Razorpay WebView, OAuth consent, system permission
// dialogs). Deleting one without explicit replacement is a regression
// and a pre-commit fail.
//
// What this gate checks (intentionally shallow — Patrol bodies are
// stubs until the founder runs them once on the Pixel):
//   1. Each of the 4 named files exists.
//   2. Each file mentions its feature keyword in a comment or code.
//   3. Each file imports `package:patrol/patrol.dart` (proves we
//      didn't accidentally replace Patrol with flutter_test stubs —
//      that would lose the native-driving capability).
//
// Exit 0 = pass.
// Exit 1 = fail (with the offending file + reason).
//
// Wired from scripts/pre-commit.sh dynamic loop. Allowlist not needed
// (gate has no live-state dependency).

import 'dart:io';

const _expectedFlows = <String, List<String>>{
  // file basename -> list of keywords that MUST appear (case-insensitive)
  'razorpay_payment_patrol_test.dart': ['razorpay'],
  'cross_device_restore_patrol_test.dart': ['restore'],
  'signup_onboarding_patrol_test.dart': ['onboarding'],
  'delete_account_patrol_test.dart': ['delete'],
};

void main() {
  final deviceDir = Directory('integration_test/device');
  if (!deviceDir.existsSync()) {
    stderr.writeln(
      '[device-tests-exist] FAIL: integration_test/device/ missing. '
      'See docs/operations/DEVICE_TESTING.md.',
    );
    exit(1);
  }

  var failures = 0;
  for (final entry in _expectedFlows.entries) {
    final path = 'integration_test/device/${entry.key}';
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('[device-tests-exist] FAIL: $path missing.');
      failures++;
      continue;
    }
    final content = file.readAsStringSync().toLowerCase();
    for (final keyword in entry.value) {
      if (!content.contains(keyword.toLowerCase())) {
        stderr.writeln(
          '[device-tests-exist] FAIL: $path missing keyword "$keyword". '
          'File should reference its named feature in code or comment.',
        );
        failures++;
      }
    }
    if (!content.contains('package:patrol/patrol.dart')) {
      stderr.writeln(
        '[device-tests-exist] FAIL: $path does not import '
        'package:patrol/patrol.dart. Native-driving capability lost; '
        'revert to Patrol or update this gate intentionally.',
      );
      failures++;
    }
  }

  if (failures > 0) {
    stderr.writeln(
      '[device-tests-exist] $failures failure(s). Fix by restoring the '
      'flow file(s) per docs/operations/DEVICE_TESTING.md §6.',
    );
    exit(1);
  }

  stdout.writeln(
    '[device-tests-exist] OK — all 4 Patrol device flows present.',
  );
}
