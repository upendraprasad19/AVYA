// test/contracts/singleton_provider_invariant_test.dart
//
// Tech-debt audit 2026-05-20 / A7 regression test.
//
// Pins the contract that the 7 singleton services have a corresponding
// Riverpod Provider at `lib/core/services/service_providers.dart`, and
// each service's static `instance` getter is `@Deprecated`.
//
// Source-grep level (presence + semantics of the declaration). Behavioral
// validation that `ref.listen(authUserIdTokenProvider, …)` fires
// SingletonLifecycleRegistry.notifyUserChanged() is covered by
// `singleton_lifecycle_registry_test.dart` (existing).
//
// closes-diagnose: 2026-05-22-a7-singleton-provider-migration-7f2a8c

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _services = <String>[
  'SubscriptionService',
  'SyncService',
  'WorkoutScheduleService',
  'UsageCounterService',
  'AiService',
  'RazorpayService',
  'SeedService',
];

String _toFileName(String className) {
  // SubscriptionService -> subscription_service
  return className
      .replaceAllMapped(RegExp(r'([A-Z])'),
          (m) => '_${m.group(1)!.toLowerCase()}')
      .substring(1);
}

String _toProviderName(String className) {
  // SubscriptionService -> subscriptionServiceProvider
  return '${className[0].toLowerCase()}${className.substring(1)}Provider';
}

void main() {
  group('A7 singleton-provider invariant', () {
    late String providerSrc;

    setUpAll(() {
      final f = File('lib/core/services/service_providers.dart');
      expect(f.existsSync(), isTrue,
          reason: 'service_providers.dart must exist (A7 deliverable)');
      providerSrc = f.readAsStringSync().replaceAll('\r\n', '\n');
    });

    for (final svc in _services) {
      group(svc, () {
        test('has Riverpod provider in service_providers.dart', () {
          final providerName = _toProviderName(svc);
          expect(providerSrc, contains(providerName),
              reason: 'service_providers.dart missing $providerName');
          // Provider returns the service type.
          expect(
            RegExp(r'Provider<' + svc + r'>').hasMatch(providerSrc),
            isTrue,
            reason: 'provider should be typed Provider<$svc>',
          );
        });

        test('static instance is @Deprecated', () {
          final fileName = _toFileName(svc);
          final f = File('lib/core/services/$fileName.dart');
          expect(f.existsSync(), isTrue,
              reason: 'service file lib/core/services/$fileName.dart not found');
          final src = f.readAsStringSync().replaceAll('\r\n', '\n');

          // Find the public `instance` declaration.
          final declRe = RegExp(
            r'static\s+(?:final\s+)?(?:\w+\s+)?(?:get\s+)?instance\b',
            multiLine: true,
          );
          final match = declRe.firstMatch(src);
          expect(match, isNotNull,
              reason: '$svc has no `static … instance` declaration');

          // Check 200 chars before for @Deprecated annotation.
          final start = (match!.start - 200).clamp(0, src.length);
          final prefix = src.substring(start, match.start);
          expect(RegExp(r'@[Dd]eprecated\b').hasMatch(prefix), isTrue,
              reason:
                  '$svc.instance is NOT @Deprecated — A7 migration incomplete. Add @Deprecated(...) annotation pointing to the Provider.');
        });
      });
    }

    test('SingletonLifecycleRegistry.notifyUserChanged is wired in provider file',
        () {
      expect(providerSrc, contains('SingletonLifecycleRegistry.notifyUserChanged'),
          reason:
              'service_providers.dart should fire SingletonLifecycleRegistry.notifyUserChanged() on auth user change.');
      expect(providerSrc, contains('authUserIdTokenProvider'),
          reason:
              'service_providers.dart should listen authUserIdTokenProvider to detect user swap.');
    });
  });
}
