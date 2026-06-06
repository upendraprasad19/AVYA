import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';

/// Contract for the Home PRO-expiry banner (diagnose 2026-06-06).
///
/// Founder got no warning before/at his PRO expiry. The infra existed
/// (`isExpiringSoon`, `daysUntilExpiry`, `expiresAt`) but nothing read it. This
/// pins the new banner: the pure severity decision + the wiring (lapsed marker
/// stamped on expiry / cleared on renewal, once-per-day dismiss, kill-switch,
/// Home render + PaywallSheet).
String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('expiryBannerSeverity (pure decision)', () {
    test('PRO with <7 days left → expiringSoon', () {
      expect(
        SubscriptionService.expiryBannerSeverity(
            isPro: true, daysUntilExpiry: 6, isLapsed: false),
        ExpiryBannerSeverity.expiringSoon,
      );
      // Expires today (0 days) still counts.
      expect(
        SubscriptionService.expiryBannerSeverity(
            isPro: true, daysUntilExpiry: 0, isLapsed: false),
        ExpiryBannerSeverity.expiringSoon,
      );
    });

    test('PRO with ≥7 days left → none', () {
      expect(
        SubscriptionService.expiryBannerSeverity(
            isPro: true, daysUntilExpiry: 7, isLapsed: false),
        ExpiryBannerSeverity.none,
      );
      expect(
        SubscriptionService.expiryBannerSeverity(
            isPro: true, daysUntilExpiry: 30, isLapsed: false),
        ExpiryBannerSeverity.none,
      );
    });

    test('lapsed (expired, not renewed) → lapsed, and it WINS over expiringSoon',
        () {
      expect(
        SubscriptionService.expiryBannerSeverity(
            isPro: false, daysUntilExpiry: 0, isLapsed: true),
        ExpiryBannerSeverity.lapsed,
      );
      // Priority: lapsed beats any expiringSoon signal.
      expect(
        SubscriptionService.expiryBannerSeverity(
            isPro: true, daysUntilExpiry: 3, isLapsed: true),
        ExpiryBannerSeverity.lapsed,
      );
    });

    test('free user (not PRO, not lapsed) → none', () {
      expect(
        SubscriptionService.expiryBannerSeverity(
            isPro: false, daysUntilExpiry: -1, isLapsed: false),
        ExpiryBannerSeverity.none,
      );
    });
  });

  group('wiring', () {
    final subSrc = _strip(
        File('lib/core/services/subscription_service.dart').readAsStringSync());
    final providerSrc = _strip(
        File('lib/features/home/providers/home_provider.dart')
            .readAsStringSync());
    final homeSrc = _strip(
        File('lib/features/home/screens/home_screen.dart').readAsStringSync());
    final widgetSrc = File('lib/shared/widgets/subscription_expiry_banner.dart')
        .readAsStringSync();

    test('lapsed marker is stamped on the genuine-expiry path in isPro()', () {
      final slice = _methodSlice(subSrc, 'isPro');
      expect(slice, isNotNull);
      expect(slice!.contains('_proLapsedAtKey'), isTrue,
          reason: 'isPro must stamp pro_lapsed_at when it downgrades on expiry, '
              'so the banner survives the expiresAt wipe');
    });

    test('lapsed marker is cleared on renewal (writeSubscriptionState)', () {
      // writeSubscriptionState has named params ({...}) so brace-slicing is
      // unreliable; assert the method exists + the clear is present (the
      // `delete(_proLapsedAtKey)` appears only inside it).
      expect(subSrc.contains('Future<void> writeSubscriptionState('), isTrue);
      expect(subSrc.contains('delete(_proLapsedAtKey)'), isTrue,
          reason: 'renewal must clear pro_lapsed_at so the banner disappears');
    });

    test('SubscriptionService exposes proLapsedAt + isLapsed', () {
      expect(subSrc.contains('get proLapsedAt'), isTrue);
      expect(subSrc.contains('get isLapsed'), isTrue);
    });

    test('provider is severity-driven, dismiss-per-day + kill-switchable', () {
      expect(providerSrc.contains('expiryBannerSeverity('), isTrue);
      expect(providerSrc.contains('dismissForToday'), isTrue);
      expect(providerSrc.contains('_expiryBannerDismissedKey'), isTrue);
      expect(providerSrc.contains('_expiryBannerKillSwitchKey'), isTrue);
      // Once-per-day: dismissal keys off the IST date.
      expect(providerSrc.contains('istDateStr('), isTrue);
    });

    test('Home renders the banner + RENEW opens the PaywallSheet', () {
      expect(homeSrc.contains('_buildExpiryBanner('), isTrue);
      expect(homeSrc.contains('subscriptionExpiryBannerProvider'), isTrue);
      expect(homeSrc.contains('showPaywallSheet('), isTrue);
    });

    test('banner widget has a RENEW CTA + a dismiss control', () {
      expect(widgetSrc.contains("'RENEW'"), isTrue);
      expect(widgetSrc.contains('Icons.close'), isTrue);
      expect(widgetSrc.contains('onDismiss'), isTrue);
    });
  });
}

String? _methodSlice(String src, String methodName) {
  final sigRe = RegExp(
    r'\b(Future<[^>]+>\s+|void\s+|bool\s+|Map<[^>]+>\s+)?\s*' +
        RegExp.escape(methodName) +
        r'\s*\(',
  );
  final m = sigRe.firstMatch(src);
  if (m == null) return null;
  var i = m.end;
  while (i < src.length && src[i] != '{') {
    i++;
  }
  if (i >= src.length) return null;
  var depth = 0;
  final start = i;
  for (; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(start, i + 1);
    }
  }
  return null;
}
