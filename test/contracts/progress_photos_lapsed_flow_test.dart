// Behavioural proof of the Progress screen's LAPSED / PRO flows (OI-314, founder
// decision 6 of 2026-10-06: a lapsed PRO user may VIEW and DELETE old photos, no new
// uploads) against the REAL SubscriptionService and the real screen. Photos come
// from the repository's test seams (`debugListOverride`, `debugDeleteOverride`,
// `debugCaptureOverride`), so no Supabase is needed; the seams script the
// repository, they do NOT stand in for the screen's own logic.
//
//   LAPSED (local state free, the read finds photos) - the gallery shows, no locked
//     card; Add is offered but its tap goes to the paywall and NEVER to a picker or
//     to capture; deleting a photo removes the tile; a failed refresh after a delete
//     keeps the photos (snackbar) and is never read as "no photos"; deleting the
//     LAST photo with a SUCCESSFUL empty read ends on the locked card; a failed
//     read with nothing on screen is the error state with Retry, never the locked
//     card, and Retry recovers.
//   SINGLE WRITER - two reloads overlap and the OLDER one finishes last: its result
//     is dropped; a payer who upgrades while a not-PRO reload is in flight still
//     ends on the PRO gallery (one re-run); disposing the screen with a read
//     pending throws nothing; a read that throws synchronously ends in the error
//     state, not a stranded spinner.
//   PRO REFUSAL (the server refused a new photo, migration 154) - a payment in
//     flight: the "still activating" snackbar, no paywall, no state change; the
//     server says NOT PRO: the paywall and the gallery stays (now read-only); the
//     server cannot confirm: the "couldn't confirm" snackbar and no paywall; a
//     generic failure: "Upload failed"; the daily cap: its own snackbar.
//
// HARNESS: as progress_photos_screen_gate_test.dart (typography warmup first, Hive
// disk I/O in tester.runAsync, @Timeout + library).
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/repositories/progress_photo_repository.dart';
import 'package:icanbefitter/features/profile/screens/progress_photos_screen.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/pro_locked_overlay.dart';

import '../helpers/hive_test_setup.dart';

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.pro);
  final bool pro;
  @override
  SubscriptionInfoData build() => SubscriptionInfoData(isPro: pro);
  void set(bool value) => state = SubscriptionInfoData(isPro: value);
}

Widget _app({void Function(_Sub sub)? capture}) => ProviderScope(
      overrides: [
        subscriptionInfoProvider.overrideWith(() {
          final sub = _Sub(false);
          capture?.call(sub);
          return sub;
        }),
      ],
      child: const MaterialApp(home: ProgressPhotosScreen()),
    );

Map<String, dynamic> _photo(String id, String area) =>
    {'id': id, 'body_area': area, 'signed_url': null};

final _three = [
  _photo('a', 'front'),
  _photo('b', 'side'),
  _photo('c', 'back'),
];

void main() {
  testWidgets('typography warmup - GoogleFonts caches before any Hive mock',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(false))],
      child: MaterialApp(
        home: Scaffold(
          body: Column(children: [
            Expanded(
              child: ProLockedOverlay(
                featureLabel: 'Progress Photos',
                description: 'x',
                onUpgradeTap: () {},
                child: const SizedBox.shrink(),
              ),
            ),
            Text('a', style: AppTypography.h3),
            Text('b', style: AppTypography.bodySm),
            Text('c', style: AppTypography.monoXs),
            Text('d', style: AppTypography.body),
            Text('e', style: AppTypography.h1),
          ]),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('Progress screen: lapsed and refusal flows', () {
    late Directory dir;
    late List<String> events;
    late int listCalls;
    late int captureCalls;
    late List<String> deleted;
    // What the next read answers. Replace per test.
    late Future<List<Map<String, dynamic>>> Function() readFn;

    setUp(() async {
      events = [];
      listCalls = 0;
      captureCalls = 0;
      deleted = [];
      readFn = () async => <Map<String, dynamic>>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {message}) => events.add('$op ${message ?? ''}');
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required reason, extra}) {};
      ProgressPhotoRepository.debugOnListForTests = () => listCalls++;
      ProgressPhotoRepository.debugListOverride = () => readFn();
      ProgressPhotoRepository.debugDeleteOverride = (id) async {
        deleted.add(id);
        return true;
      };
      ProgressPhotoRepository.debugCaptureOverride = (_, _) async {
        captureCalls++;
        return 'new-id';
      };
      dir = await setUpHiveForTests();
      events.clear();
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      ProgressPhotoRepository.debugOnListForTests = null;
      ProgressPhotoRepository.debugListOverride = null;
      ProgressPhotoRepository.debugDeleteOverride = null;
      ProgressPhotoRepository.debugCaptureOverride = null;
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

    Future<void> payInFlight(WidgetTester tester) => tester.runAsync(
        () => SubscriptionService.instance.markPaymentInFlight(orderId: 'o1'));

    final paywall = find.text(paywallLetterheadTitle('Progress Photos'));

    /// [settle] false leaves the capture pending (its busy spinner never
    /// settles): the caller completes whatever the capture waits on, then settles.
    Future<void> openAddAndPickGallery(WidgetTester tester,
        {bool settle = true}) async {
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Front'));
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    Future<void> deleteTile(WidgetTester tester, String label) async {
      await tester.longPress(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    // ── LAPSED ────────────────────────────────────────────────────────────

    testWidgets('LAPSED with photos: the gallery, no locked card, Add leads to '
        'the paywall and never to a picker or capture', (tester) async {
      await makeFree(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('FRONT'), findsOneWidget);
      expect(find.text('SIDE'), findsOneWidget);
      expect(find.text('BACK'), findsOneWidget);
      expect(find.byType(ProLockedOverlay), findsNothing,
          reason: 'a lapsed user\'s photos must not sit behind the upsell');
      expect(find.text('Add photo'), findsOneWidget);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      expect(paywall, findsOneWidget);
      expect(find.text('Camera'), findsNothing);
      expect(find.text('Gallery'), findsNothing);
      expect(captureCalls, 0);
      expect(find.text('FRONT'), findsOneWidget,
          reason: 'the tap must not hide the photos the user holds');
    });

    testWidgets('LAPSED: deleting one photo removes its tile and keeps the '
        'others', (tester) async {
      await makeFree(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      readFn = () async => [_three[1], _three[2]];
      await deleteTile(tester, 'FRONT');

      expect(deleted, ['a']);
      expect(find.text('FRONT'), findsNothing);
      expect(find.text('SIDE'), findsOneWidget);
      expect(find.text('BACK'), findsOneWidget);
      expect(find.byType(ProLockedOverlay), findsNothing);
      expect(
          events.where((e) => e.startsWith('subscription_gate_routed')),
          hasLength(1),
          reason: 'a delete only re-reads: it reuses the last verdict and does '
              'not re-run the PRO gate (a locally-PRO user would wait up to 10 s)');
      expect(listCalls, 2, reason: 'the entry read, then one read after the delete');
    });

    testWidgets('LAPSED: a FAILED refresh after a delete keeps the other photos '
        '(never "no photos")', (tester) async {
      await makeFree(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      readFn = () async => throw StateError('network down');
      await deleteTile(tester, 'FRONT');

      expect(find.text('FRONT'), findsNothing, reason: 'the deleted tile is gone');
      expect(find.text('SIDE'), findsOneWidget);
      expect(find.text('BACK'), findsOneWidget);
      expect(find.byType(ProLockedOverlay), findsNothing);
      expect(find.text('Couldn\'t refresh your photos'), findsOneWidget);
    });

    testWidgets('LAPSED: deleting the LAST photo with a successful empty read '
        'ends on the locked card', (tester) async {
      await makeFree(tester);
      readFn = () async => [_three[0]];
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.text('FRONT'), findsOneWidget);

      readFn = () async => <Map<String, dynamic>>[];
      await deleteTile(tester, 'FRONT');

      expect(find.byType(ProLockedOverlay), findsOneWidget);
      expect(find.text('Add photo'), findsNothing);
    });

    testWidgets('LAPSED: deleting the last photo when the refresh FAILS is the '
        'error state, never the locked card', (tester) async {
      await makeFree(tester);
      readFn = () async => [_three[0]];
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      readFn = () async => throw StateError('network down');
      await deleteTile(tester, 'FRONT');

      expect(find.byType(ProLockedOverlay), findsNothing,
          reason: 'a failed read must not be read as "no photos" (class 2.49)');
      expect(find.text('Couldn\'t load photos'), findsWidgets);
      expect(find.text('Add photo'), findsNothing);
    });

    testWidgets('a failed first read with nothing on screen is the error state '
        'with Retry, and Retry recovers', (tester) async {
      await makeFree(tester);
      readFn = () async => throw StateError('offline');
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.byType(ProLockedOverlay), findsNothing,
          reason: 'offline must not show the upsell to a user who may hold photos');
      expect(find.text('Couldn\'t load photos'), findsWidgets);
      expect(find.text('Add photo'), findsNothing);

      readFn = () async => _three;
      await tester.tap(find.text('RETRY'));
      await tester.pumpAndSettle();

      expect(find.text('FRONT'), findsOneWidget);
      expect(find.text('Couldn\'t load photos'), findsNothing);
    });

    testWidgets('a read that throws SYNCHRONOUSLY ends in the error state, not a '
        'stranded spinner', (tester) async {
      await makeFree(tester);
      ProgressPhotoRepository.debugListOverride =
          () => throw StateError('sync throw');
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Couldn\'t load photos'), findsWidgets);
    });

    // ── SINGLE WRITER ─────────────────────────────────────────────────────

    testWidgets('two reloads overlap and the OLDER finishes last: its result is '
        'dropped', (tester) async {
      await makeFree(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // Delete starts a reload whose read stays pending.
      final older = Completer<List<Map<String, dynamic>>>();
      readFn = () => older.future;
      await tester.longPress(find.text('FRONT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump();

      // The Add tap starts a NEWER reload (known verdict: not PRO).
      final newer = Completer<List<Map<String, dynamic>>>();
      readFn = () => newer.future;
      await tester.tap(find.text('Add photo'));
      await tester.pump();
      await tester.pump();

      newer.complete([_three[2]]); // the newer answers first: only BACK left
      await tester.pumpAndSettle();
      older.complete(<Map<String, dynamic>>[]); // the older, stale and EMPTY
      await tester.pumpAndSettle();

      expect(find.text('BACK'), findsOneWidget,
          reason: 'the stale empty answer must not overwrite the newer gallery');
      expect(find.byType(ProLockedOverlay), findsNothing);
    });

    testWidgets('a payer who upgrades while a not-PRO reload is in flight ends '
        'on the PRO gallery (one re-run)', (tester) async {
      late _Sub sub;
      await makeFree(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app(capture: (s) => sub = s));
      await tester.pumpAndSettle();
      expect(find.text('Add photo'), findsOneWidget);

      final pending = Completer<List<Map<String, dynamic>>>();
      readFn = () => pending.future;
      await tester.longPress(find.text('FRONT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump();

      // The purchase lands while that reload's read is pending.
      await makePro(tester);
      sub.set(true);
      await tester.pump();
      readFn = () async => [_three[1], _three[2]];
      pending.complete([_three[1], _three[2]]);
      await tester.pumpAndSettle();

      final gates = events
          .where((e) => e.startsWith('subscription_gate_routed'))
          .toList();
      expect(gates.last, contains('exit=onPro'),
          reason: 'the flip must not be lost: the screen re-decided as PRO');
      expect(find.text('SIDE'), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('a payer\'s full re-check is not overwritten by a later reload '
        'that carries the old not-PRO verdict', (tester) async {
      late _Sub sub;
      await makeFree(tester);
      readFn = () async => [_three[0]];
      await tester.pumpWidget(_app(capture: (s) => sub = s));
      await tester.pumpAndSettle();
      expect(find.text('FRONT'), findsOneWidget);

      // The purchase lands; the listener starts the FULL re-check, whose read
      // stays pending.
      await makePro(tester);
      final stale = Completer<List<Map<String, dynamic>>>();
      readFn = () => stale.future;
      sub.set(true);
      await tester.pump();
      await tester.pump();

      // The user deletes their only photo meanwhile; that reload would carry the
      // OLD verdict (false) and must not trust it while the full one is running.
      readFn = () async => <Map<String, dynamic>>[];
      await tester.longPress(find.text('FRONT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      stale.complete([_three[0]]);
      await tester.pumpAndSettle();

      // A PRO user with no photos sees the empty gallery, NOT the locked card.
      expect(find.byType(ProLockedOverlay), findsNothing,
          reason: 'a stale not-PRO verdict must not win over the re-check');
      expect(find.text('No photos yet'), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('disposing the screen with a read pending throws nothing',
        (tester) async {
      await makePro(tester);
      final pending = Completer<List<Map<String, dynamic>>>();
      readFn = () => pending.future;
      await tester.pumpWidget(_app());
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(_three);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // ── PRO refusal (migration 154) ───────────────────────────────────────

    testWidgets('PRO: the server refuses while a payment is in flight -> "still '
        'activating", no paywall, the gallery stays', (tester) async {
      await makePro(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await payInFlight(tester);
      ProgressPhotoRepository.debugCaptureOverride = (_, _) async {
        captureCalls++;
        throw const ProgressPhotoProRequiredException();
      };

      await openAddAndPickGallery(tester);

      expect(captureCalls, 1);
      expect(find.textContaining('still activating'), findsOneWidget);
      expect(paywall, findsNothing, reason: 'a payer is never sent back to pay');
      expect(find.text('FRONT'), findsOneWidget);
      expect(find.byType(ProLockedOverlay), findsNothing);
    });

    testWidgets('PRO with NO photos, payment in flight, refused: stays on the '
        'gallery, not the locked card', (tester) async {
      await makePro(tester);
      readFn = () async => <Map<String, dynamic>>[];
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await payInFlight(tester);
      ProgressPhotoRepository.debugCaptureOverride = (_, _) async {
        throw const ProgressPhotoProRequiredException();
      };

      await openAddAndPickGallery(tester);

      expect(find.byType(ProLockedOverlay), findsNothing,
          reason: 'the most likely just-paid case: a new payer holds no photos');
      expect(find.text('No photos yet'), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
      expect(paywall, findsNothing);
    });

    testWidgets('PRO locally but the server says NOT PRO -> the paywall, and the '
        'photos stay as a read-only gallery', (tester) async {
      await makePro(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // The refusal arrives only after the subscription has really lapsed.
      final lapsed = Completer<void>();
      ProgressPhotoRepository.debugCaptureOverride = (_, _) async {
        captureCalls++;
        await lapsed.future;
        throw const ProgressPhotoProRequiredException();
      };
      await openAddAndPickGallery(tester, settle: false);
      await makeFree(tester);
      lapsed.complete();
      await tester.pumpAndSettle();

      expect(paywall, findsOneWidget);
      expect(find.text('FRONT'), findsOneWidget,
          reason: 'the lapsed user keeps seeing their photos');
      expect(find.byType(ProLockedOverlay), findsNothing);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('PRO with NO photos locally but the server says NOT PRO -> the '
        'paywall AND the locked card (the screen is re-decided)', (tester) async {
      await makePro(tester);
      readFn = () async => <Map<String, dynamic>>[];
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.text('No photos yet'), findsOneWidget);

      final lapsed = Completer<void>();
      ProgressPhotoRepository.debugCaptureOverride = (_, _) async {
        await lapsed.future;
        throw const ProgressPhotoProRequiredException();
      };
      await openAddAndPickGallery(tester, settle: false);
      await makeFree(tester);
      lapsed.complete();
      await tester.pumpAndSettle();

      expect(paywall, findsOneWidget);
      expect(find.byType(ProLockedOverlay), findsOneWidget,
          reason: 'the server agreed the user is not PRO and they hold nothing: '
              'the reload with the known verdict turns the gallery into the card');
      expect(find.text('Add photo'), findsNothing);
    });

    testWidgets('PRO refused but the server cannot say otherwise -> "couldn\'t '
        'confirm", no paywall', (tester) async {
      await makePro(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      ProgressPhotoRepository.debugCaptureOverride = (_, _) async {
        throw const ProgressPhotoProRequiredException();
      };

      await openAddAndPickGallery(tester);

      expect(find.textContaining('couldn\'t confirm your PRO'), findsOneWidget);
      expect(paywall, findsNothing);
      expect(find.text('FRONT'), findsOneWidget);
    });

    testWidgets('PRO: a generic capture failure is "Upload failed", no paywall',
        (tester) async {
      await makePro(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      ProgressPhotoRepository.debugCaptureOverride = (_, _) async => null;

      await openAddAndPickGallery(tester);

      expect(find.text('Upload failed — try again'), findsOneWidget);
      expect(paywall, findsNothing);
    });

    testWidgets('PRO: the daily cap shows its own snackbar, no paywall',
        (tester) async {
      await makePro(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      ProgressPhotoRepository.debugCaptureOverride = (_, _) async =>
          throw const PhotoQuotaException(dailyCap: 5, message: 'cap');

      await openAddAndPickGallery(tester);

      expect(find.text('Daily photo limit reached — back tomorrow.'),
          findsOneWidget);
      expect(paywall, findsNothing);
    });

    testWidgets('PRO: a successful capture re-reads and shows the new photo',
        (tester) async {
      await makePro(tester);
      readFn = () async => [_three[0]];
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      readFn = () async => [_three[0], _three[1]];

      await openAddAndPickGallery(tester);

      expect(captureCalls, 1);
      expect(find.text('SIDE'), findsOneWidget);
      expect(find.text('Upload failed — try again'), findsNothing);
      expect(
          events.where((e) => e.startsWith('subscription_gate_routed')),
          hasLength(2),
          reason: 'the entry gate and the Add gate only: the re-read after a '
              'capture reuses the last verdict and does not gate again');
      expect(listCalls, 2);
    });
  });
}
