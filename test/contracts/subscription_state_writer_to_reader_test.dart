import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `subscription_state`
/// from docs/sot_registry.yaml.
///
/// Writer: SubscriptionService (markPaymentInFlight + verifyFromServer + _downgradeLocally)
/// Readers: SubscriptionService.isPro + gate, subscriptionInfoProvider (in profile_provider.dart)
///
/// Forbidden patterns:
/// - configBox.get('isPro') — never read directly
/// - if (isPro) { ... } — always use gate()
void main() {
  late String subSvcSrc;
  late String profileProvSrc;

  setUpAll(() {
    final sf = File('lib/core/services/subscription_service.dart');
    expect(sf.existsSync(), isTrue,
        reason: 'subscription_service.dart must exist (writer for subscription_state)');
    subSvcSrc = sf.readAsStringSync();

    // subscriptionInfoProvider lives in profile_provider.dart (NOT a separate file)
    final pf = File('lib/features/profile/providers/profile_provider.dart');
    expect(pf.existsSync(), isTrue,
        reason: 'profile_provider.dart must exist (hosts subscriptionInfoProvider)');
    profileProvSrc = pf.readAsStringSync();
  });

  group('subscription_state writer↔reader source contract', () {
    test('writer markPaymentInFlight exists in subscription_service', () {
      expect(subSvcSrc.contains('markPaymentInFlight'), isTrue,
          reason:
              'subscription_service must define markPaymentInFlight (Test #12 grace window writer)');
    });

    test('writer verifyFromServer exists in subscription_service', () {
      expect(subSvcSrc.contains('verifyFromServer'), isTrue,
          reason: 'subscription_service must define verifyFromServer');
    });

    test('writer _downgradeLocally exists in subscription_service', () {
      expect(subSvcSrc.contains('_downgradeLocally'), isTrue,
          reason: 'subscription_service must define _downgradeLocally');
    });

    test('reader isPro exists in subscription_service', () {
      expect(subSvcSrc.contains('bool isPro'), isTrue,
          reason: 'subscription_service must define isPro() reader');
    });

    test('reader gate() exists in subscription_service', () {
      expect(subSvcSrc.contains('Future gate') || subSvcSrc.contains('void gate'),
          isTrue,
          reason: 'subscription_service must define gate() method');
    });

    test('subscriptionInfoProvider defined in profile_provider', () {
      expect(profileProvSrc.contains('subscriptionInfoProvider'), isTrue,
          reason:
              'profile_provider.dart must define subscriptionInfoProvider so widgets '
              'can watch and rebuild on payment success');
    });

    test('subscriptionInfoProvider exposes isVerifying field', () {
      expect(profileProvSrc.contains('isVerifying'), isTrue,
          reason:
              'SubscriptionInfoData.isVerifying must be present for the '
              '"CONFIRMING ⟳ AWAITING WEBHOOK CONFIRMATION" UI copy');
    });

    test('high-value features list contains phases_2_to_12 + ai_coach_unlimited + progress_photos',
        () {
      expect(subSvcSrc.contains('featurePhases2To12'), isTrue,
          reason: 'phases_2_to_12 must be in _highValueFeatures');
      expect(subSvcSrc.contains('featureAiCoachUnlimited'), isTrue,
          reason: 'ai_coach_unlimited must be in _highValueFeatures');
      expect(subSvcSrc.contains('featureProgressPhotos'), isTrue,
          reason: 'progress_photos must be in _highValueFeatures');
    });

    test('forbidden: configBox.get(isPro) absent from subscription_service', () {
      expect(subSvcSrc.contains("configBox.get('isPro')"), isFalse,
          reason:
              "subscription_service itself must not read configBox.get('isPro') directly; "
              "use the MigratedKey pattern");
    });

    test('grace window checks isPaymentInFlight in verifyFromServer', () {
      expect(subSvcSrc.contains('isPaymentInFlight'), isTrue,
          reason:
              'verifyFromServer must check isPaymentInFlight to suppress downgrade during grace window');
    });
  });
}
