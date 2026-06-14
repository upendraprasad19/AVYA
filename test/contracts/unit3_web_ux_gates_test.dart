// Source-grep contracts for Unit 3 web-UX gates (comment-stripped so a
// describing comment can't satisfy an assertion).
//
// obs 2b — Health Connect is native-only; gated on web (HealthSyncService
//          no-op in all 4 native methods + the profile CONNECT toggle disabled).
// obs 6  — the PWA install banner is web-only (kIsWeb + JS-interop conditional
//          import) and its dismiss flag is registered as intentionally-shared.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  group('Unit 3 obs 2b — Health Connect gated on web', () {
    final svc = _strip(
        File('lib/core/services/health_sync_service.dart').readAsStringSync());
    final card = _strip(
        File('lib/features/profile/widgets/biometric_sync_card.dart')
            .readAsStringSync());

    test('all 4 native HealthSyncService methods early-return on kIsWeb', () {
      // requestPermissions / fetchStepsToday / fetchLatestWeight / syncToHive
      expect(
        RegExp(r'if \(kIsWeb\) return').allMatches(svc).length,
        greaterThanOrEqualTo(4),
        reason: 'each native-touching method must no-op on web so the CONNECT '
            'flow never dead-ends (MissingPluginException)',
      );
    });

    test('the profile CONNECT toggle is disabled on web', () {
      expect(card.contains('kIsWeb'), isTrue);
      expect(RegExp(r'onTap:\s*kIsWeb\s*\?\s*null').hasMatch(card), isTrue,
          reason: 'tapping CONNECT on web must be inert (no native call)');
    });
  });

  group('Unit 3 obs 6 — PWA install banner (web-only)', () {
    test('index.html captures beforeinstallprompt + exposes the JS hooks', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html.contains('beforeinstallprompt'), isTrue);
      expect(html.contains('avyaPwaCanInstall'), isTrue);
      expect(html.contains('avyaPwaPromptInstall'), isTrue);
      expect(html.contains('avyaPwaIsIosSafari'), isTrue);
    });

    test('banner is kIsWeb-gated + uses the modern js_interop conditional import',
        () {
      final banner = _strip(
          File('lib/shared/widgets/pwa_install/pwa_install_banner.dart')
              .readAsStringSync());
      expect(banner.contains('if (!kIsWeb'), isTrue,
          reason: 'must render nothing on Android/iOS');
      expect(banner.contains('dart.library.js_interop'), isTrue,
          reason: 'modern web interop key (NOT the deprecated dart.library.html)');
    });

    test('dismiss flag is registered as intentionally-shared (not user-scoped)',
        () {
      final mig = File('lib/core/services/user_config_migrator.dart')
          .readAsStringSync();
      expect(mig.contains('pwa_banner_dismissed'), isTrue);
    });
  });
}
