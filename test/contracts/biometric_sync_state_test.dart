import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Obs 5 (2026-06-05): tapping CONNECT on the Health-sync sheet left it showing
/// "Tap to enable" until you navigated away + back. Root cause: the bottom
/// sheet rendered a CAPTURED `BiometricData` snapshot instead of
/// `ref.watch(biometricProvider)`, so `toggleSync`'s `invalidateSelf()` rebuilt
/// the provider but the open sheet never re-read it. Fix: wrap the card in a
/// `Consumer` that watches the provider + `await` toggleSync. The "watch, don't
/// snapshot" structure is the load-bearing contract (Riverpod guarantees the
/// rebuild once the widget watches).

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final sheet = _strip(File(
          'lib/features/profile/screens/profile/health_sync_sheet.dart')
      .readAsStringSync());
  final sheetNoWs = sheet.replaceAll(RegExp(r'\s'), '');
  final provider = _strip(
      File('lib/features/profile/providers/profile_provider.dart')
          .readAsStringSync());

  group('Obs 5 — sheet reacts to biometricProvider (no stale snapshot)', () {
    test('card is wrapped in a Consumer', () {
      expect(sheet.contains('Consumer('), isTrue,
          reason: 'the sheet card must be wrapped in a Consumer so it rebuilds '
              'when toggleSync invalidates the provider');
    });

    test('builder watches biometricProvider', () {
      expect(sheetNoWs.contains('.watch(biometricProvider)'), isTrue,
          reason: 'must ref.watch(biometricProvider) — not render a captured '
              'BiometricData snapshot (Obs 5 root cause)');
    });

    test('toggleSync is awaited, not fire-and-forget', () {
      expect(
        sheetNoWs
            .contains('awaitref.read(biometricProvider.notifier).toggleSync'),
        isTrue,
        reason: 'await so the permission result + invalidateSelf settle before '
            'the handler returns',
      );
      expect(
        sheetNoWs.contains(
            'unawaited(ref.read(biometricProvider.notifier).toggleSync'),
        isFalse,
        reason: 'the pre-fix unawaited() toggleSync call must be gone',
      );
    });
  });

  group('Obs 5 — provider rebuilds + IST read', () {
    test('toggleSync invalidates itself so watchers rebuild', () {
      expect(provider.contains('ref.invalidateSelf()'), isTrue);
    });
    test('biometric build keys health data by the IST date', () {
      expect(provider.contains('istDateStr(now)'), isTrue,
          reason: 'biometric build must key by IST (matches HealthWriteService '
              'writer) — was device-local y/m/d');
    });
  });
}
