// ADR-0022 / plan section 3 and 7.1: the truth table of the purchase-mode
// resolver, and what each mode lets a surface do.
//
// Pure: no widget, no Hive. The WIRING of `PurchaseMode.current` (which reads
// the real `kIsWeb`, `dart.vm.product` and define) is pinned separately in
// `purchase_mode_current_wiring_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';

PurchaseMode _r({bool web = false, bool release = false, String raw = ''}) =>
    resolvePurchaseMode(isWeb: web, isRelease: release, raw: raw);

void main() {
  group('web is always razorpay', () {
    for (final release in [true, false]) {
      for (final raw in ['', 'none', 'play_billing', 'razorpay', 'junk']) {
        test('web, release=$release, raw="$raw"', () {
          expect(_r(web: true, release: release, raw: raw),
              PurchaseMode.razorpay);
        });
      }
    }
  });

  group('non-web with a valid define wins over the build type', () {
    for (final release in [true, false]) {
      test('release=$release', () {
        expect(_r(release: release, raw: 'razorpay'), PurchaseMode.razorpay);
        expect(_r(release: release, raw: 'none'), PurchaseMode.none);
        expect(_r(release: release, raw: 'play_billing'),
            PurchaseMode.playBilling);
      });
    }
    test('trimmed and case-insensitive', () {
      expect(_r(release: true, raw: ' PLAY_BILLING '), PurchaseMode.playBilling);
      expect(_r(release: true, raw: 'None'), PurchaseMode.none);
      expect(_r(release: true, raw: 'RAZORPAY'), PurchaseMode.razorpay);
    });
  });

  group('non-web, define absent or unrecognised', () {
    test('a RELEASE build has no purchase UI (a forgotten define is safe)', () {
      expect(_r(release: true), PurchaseMode.none);
      expect(_r(release: true, raw: 'junk'), PurchaseMode.none);
      expect(_r(release: true, raw: 'play-billing'), PurchaseMode.none);
      // Near misses of a real wire name must not match by prefix / suffix /
      // containment (B-pass F7): each would be a mutant of the matcher.
      for (final near in [
        'razorpay2',
        'nonexistent',
        'play_billing_x',
        'xnone',
        'none ok',
        'razor',
      ]) {
        expect(_r(release: true, raw: near), PurchaseMode.none, reason: near);
        expect(_r(release: false, raw: near), PurchaseMode.razorpay,
            reason: near);
      }
    });
    test('debug, profile and tests keep the Razorpay behaviour', () {
      expect(_r(release: false), PurchaseMode.razorpay);
      expect(_r(release: false, raw: 'junk'), PurchaseMode.razorpay);
    });
  });

  group('what each mode lets a surface do', () {
    test('only razorpay starts a Razorpay order or links to the website', () {
      expect(PurchaseMode.razorpay.showsPurchaseUi, isTrue);
      expect(PurchaseMode.razorpay.showsRazorpay, isTrue);
      expect(PurchaseMode.razorpay.showsWebLinks, isTrue);
      expect(PurchaseMode.razorpay.showsPlayBilling, isFalse);
      expect(PurchaseMode.none.showsPurchaseUi, isFalse);
      expect(PurchaseMode.none.showsRazorpay, isFalse);
      expect(PurchaseMode.none.showsWebLinks, isFalse);
      expect(PurchaseMode.none.showsPlayBilling, isFalse);
    });

    test('playBilling (OI-519) sells through Play only: no Razorpay, no web',
        () {
      expect(PurchaseMode.playBilling.showsPurchaseUi, isTrue);
      expect(PurchaseMode.playBilling.showsPlayBilling, isTrue);
      expect(PurchaseMode.playBilling.showsRazorpay, isFalse);
      expect(PurchaseMode.playBilling.showsWebLinks, isFalse);
    });

    test('wire names are the define values', () {
      expect(PurchaseMode.razorpay.wireName, 'razorpay');
      expect(PurchaseMode.none.wireName, 'none');
      expect(PurchaseMode.playBilling.wireName, 'play_billing');
    });
  });

  group('current and the override seam', () {
    tearDown(() => PurchaseMode.debugOverrideForTests = null);

    test('under flutter test the real resolution is razorpay', () {
      // dart.vm.product is false in tests, kIsWeb is false, no define given.
      expect(PurchaseMode.current, PurchaseMode.razorpay);
      expect(showsUpgradeAffordance(), isTrue);
    });

    test('the override wins and showsUpgradeAffordance follows it', () {
      PurchaseMode.debugOverrideForTests = PurchaseMode.none;
      expect(PurchaseMode.current, PurchaseMode.none);
      expect(showsUpgradeAffordance(), isFalse);
      PurchaseMode.debugOverrideForTests = PurchaseMode.playBilling;
      expect(showsUpgradeAffordance(), isTrue);
    });
  });
}
