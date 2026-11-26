// Behavioural proof of the FREE user's progress-photo flow (OI-348 Landing 3c,
// founder calls of 2026-11-26) on the real screen and the real
// SubscriptionService, the repository scripted through its test seams:
//
//   - the weekly-used snackbar carries a GO PRO action only in a build that can
//     sell PRO (`showsUpgradeAffordance()`: razorpay and play_billing yes, none
//     no, ADR-0022), and the paywall opens ONLY from that action, with the
//     'Unlimited Progress Photos' letterhead;
//   - a used slot opens nothing by itself (no paywall, no sheet, no capture);
//   - a slot check that returns normally proceeds to the source sheet, the angle
//     sheet and exactly one capture, in that order (slot, then capture);
//   - a PRO user's Add tap never asks for the free slot;
//   - the server's refusal for a free user shows the same snackbar, with the same
//     build-mode rule for GO PRO.
//
// Not proven here: the real slot check against Storage, the server rule itself
// (migration + its live verify), and the paywall's purchase body.
//
// HARNESS: as progress_photos_screen_gate_test.dart (typography warmup first, Hive
// disk I/O in tester.runAsync, @Timeout + library).
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:icanbefitter/core/copy/progress_photo_copy.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/repositories/progress_photo_repository.dart';
import 'package:icanbefitter/features/profile/screens/progress_photos_screen.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';
import 'package:image_picker/image_picker.dart';

import '../helpers/hive_test_setup.dart';

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.pro);
  final bool pro;
  @override
  SubscriptionInfoData build() => SubscriptionInfoData(isPro: pro);
}

Widget _app() => ProviderScope(
      overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(false))],
      child: const MaterialApp(home: ProgressPhotosScreen()),
    );

void main() {
  testWidgets('typography warmup - GoogleFonts caches before any Hive mock',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(false))],
      child: MaterialApp(
        home: Scaffold(
          body: Column(children: [
            Text('a', style: AppTypography.h3),
            Text('b', style: AppTypography.bodySm),
            Text('c', style: AppTypography.monoXs),
            Text('d', style: AppTypography.body),
            // Fraunces w500 - the PaywallSheet h1 letterhead.
            Text('e', style: AppTypography.h1),
            const WardButton(label: 'x', onPressed: null),
          ]),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('Progress screen: the free weekly flow', () {
    late Directory dir;
    late List<String> order;
    late int captureCalls;
    late int slotCalls;
    late Future<void> Function() slotFn;

    setUp(() async {
      order = [];
      captureCalls = 0;
      slotCalls = 0;
      slotFn = () async {};
      ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {};
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required reason, extra}) {};
      ProgressPhotoRepository.debugListOverride = () async => [];
      ProgressPhotoRepository.debugCaptureOverride = (source, area) async {
        captureCalls++;
        order.add('capture:${source.name}:$area');
        return 'new-id';
      };
      ProgressPhotoRepository.debugEnsureFreeSlotOverride = () {
        slotCalls++;
        order.add('slot');
        return slotFn();
      };
      dir = await setUpHiveForTests();
    });

    tearDown(() async {
      PurchaseMode.debugOverrideForTests = null;
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      ProgressPhotoRepository.debugListOverride = null;
      ProgressPhotoRepository.debugCaptureOverride = null;
      ProgressPhotoRepository.debugEnsureFreeSlotOverride = null;
      await tearDownHiveForTests(dir);
    });

    Future<void> makePro(WidgetTester tester) => tester.runAsync(() async {
          await MigratedKey.write('isPro', true);
          await MigratedKey.write(
              'expiresAt',
              DateTime.now().add(const Duration(days: 30)).toIso8601String());
        });

    Future<void> makeFree(WidgetTester tester) =>
        tester.runAsync(() => MigratedKey.write('isPro', false));

    final weeklyUsed = find.text(ProgressPhotoCopy.weeklyUsed);
    final goPro = find.text(ProgressPhotoCopy.goPro);
    final paywall =
        find.text(paywallLetterheadTitle(ProgressPhotoCopy.paywallFeature));

    void slotIsUsed() => slotFn = () async =>
        throw const PhotoQuotaException(weeklyCap: 1, message: 'used');

    Future<void> tapAddWithUsedSlot(WidgetTester tester) async {
      await makeFree(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      slotIsUsed();
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
    }

    for (final mode in [PurchaseMode.razorpay, PurchaseMode.playBilling]) {
      testWidgets('${mode.wireName}: the weekly-used snackbar carries a GO PRO '
          'action', (tester) async {
        PurchaseMode.debugOverrideForTests = mode;
        await tapAddWithUsedSlot(tester);

        expect(weeklyUsed, findsOneWidget);
        expect(find.byType(SnackBarAction), findsOneWidget);
        expect(goPro, findsOneWidget);
        expect(paywall, findsNothing,
            reason: 'the snackbar itself opens nothing');
      });
    }

    testWidgets('none: the weekly-used snackbar has NO action (a build that '
        'sells nothing offers no upgrade)', (tester) async {
      PurchaseMode.debugOverrideForTests = PurchaseMode.none;
      await tapAddWithUsedSlot(tester);

      expect(weeklyUsed, findsOneWidget);
      expect(find.byType(SnackBarAction), findsNothing);
      expect(goPro, findsNothing);
      expect(paywall, findsNothing);
    });

    testWidgets('tapping GO PRO opens the paywall with the Unlimited Progress '
        'Photos letterhead', (tester) async {
      PurchaseMode.debugOverrideForTests = PurchaseMode.razorpay;
      await tapAddWithUsedSlot(tester);
      expect(paywall, findsNothing);

      await tester.tap(goPro);
      await tester.pumpAndSettle();

      expect(paywall, findsOneWidget);
      expect(find.text('Unlimited Progress Photos is a PRO feature'),
          findsOneWidget);
      expect(captureCalls, 0);
    });

    testWidgets('a slot check that returns normally proceeds: slot, source '
        'sheet, angle sheet, then exactly one capture', (tester) async {
      await makeFree(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      expect(order, ['slot'], reason: 'no capture before a source is picked');
      expect(find.text('Camera'), findsOneWidget);

      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      expect(find.text('Which angle?'), findsOneWidget);
      expect(order, ['slot']);

      await tester.tap(find.text('Side'));
      await tester.pumpAndSettle();

      expect(order, ['slot', 'capture:${ImageSource.gallery.name}:side']);
      expect(slotCalls, 1);
      expect(captureCalls, 1);
      expect(paywall, findsNothing);
      expect(weeklyUsed, findsNothing);
    });

    testWidgets('a used slot opens nothing by itself: no sheet, no capture, no '
        'paywall, and the button is usable again', (tester) async {
      PurchaseMode.debugOverrideForTests = PurchaseMode.razorpay;
      await tapAddWithUsedSlot(tester);

      expect(order, ['slot']);
      expect(find.text('Camera'), findsNothing);
      expect(find.text('Which angle?'), findsNothing);
      expect(captureCalls, 0);
      expect(paywall, findsNothing);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('PRO: the Add tap never asks for the free slot', (tester) async {
      await makePro(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      // A PRO user must not be stopped by a used slot: make any ask fatal.
      slotIsUsed();

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      expect(find.text('Camera'), findsOneWidget);
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Front'));
      await tester.pumpAndSettle();

      expect(slotCalls, 0);
      expect(order, ['capture:${ImageSource.camera.name}:front']);
      expect(weeklyUsed, findsNothing);
      expect(paywall, findsNothing);
    });

    for (final mode in [PurchaseMode.razorpay, PurchaseMode.none]) {
      testWidgets('${mode.wireName}: the server refusing a FREE user shows the '
          'same snackbar; GO PRO only where PRO is sold', (tester) async {
        PurchaseMode.debugOverrideForTests = mode;
        await makeFree(tester);
        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();
        ProgressPhotoRepository.debugCaptureOverride = (_, _) async {
          captureCalls++;
          throw const ProgressPhotoProRequiredException();
        };

        await tester.tap(find.text('Add photo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Gallery'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Front'));
        await tester.pumpAndSettle();

        expect(captureCalls, 1);
        expect(weeklyUsed, findsOneWidget);
        expect(goPro, mode.showsPurchaseUi ? findsOneWidget : findsNothing);
        expect(paywall, findsNothing);
      });
    }
  });
}
