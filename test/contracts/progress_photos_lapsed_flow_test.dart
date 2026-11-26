// Behavioural proof of the Progress screen's LAPSED / PRO flows after OI-348
// Landing 3c (a lapsed PRO user is a FREE user: they view and delete the photos
// they hold and may add one photo per IST week; the paywall opens only from the
// weekly-used snackbar's GO PRO action) against the REAL SubscriptionService and
// the real screen. Photos come from the repository's test seams
// (`debugListOverride`, `debugDeleteOverride`, `debugCaptureOverride`,
// `debugEnsureFreeSlotOverride`), so no Supabase is needed; the seams script the
// repository, they do NOT stand in for the screen's own logic.
//
//   LAPSED (local state free, the read finds photos) - the gallery shows with the
//     free caption and the Add button; a used weekly slot shows the weekly-used
//     snackbar and reaches no picker, no capture and no paywall; an open slot goes
//     on to the picker; deleting a photo removes the tile; a failed refresh after
//     a delete keeps the photos (snackbar) and is never read as "no photos";
//     deleting the LAST photo with a SUCCESSFUL empty read ends on the empty state
//     (caption and Add stay); a failed read with nothing on screen is the error
//     state with Retry, never the empty state, and Retry recovers.
//   SINGLE WRITER - two reloads overlap and the OLDER one finishes last: its result
//     is dropped; a payer who upgrades while a free reload is in flight still ends
//     on the PRO gallery (one re-run); a stale free verdict does not win over the
//     payer's full re-check; disposing the screen with a read pending throws
//     nothing; a read that throws synchronously ends in the error state, not a
//     stranded spinner.
//   REFUSAL (the server refused a new photo, the free weekly cap migration) - a
//     payment in flight: the "still activating" snackbar, no paywall, no state
//     change; the server says NOT PRO: the weekly-used snackbar, NO automatic
//     paywall, the gallery stays and the screen is re-decided as free; a free user
//     whose slot check passed but whom the server refuses (another device took the
//     slot) gets the same; the server cannot confirm: the "couldn't confirm"
//     snackbar and no paywall; a generic failure: "Upload failed".
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
import 'package:icanbefitter/core/copy/progress_photo_copy.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/repositories/progress_photo_repository.dart';
import 'package:icanbefitter/features/profile/screens/progress_photos_screen.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';

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
    late int slotCalls;
    late List<String> deleted;
    // What the next read answers. Replace per test.
    late Future<List<Map<String, dynamic>>> Function() readFn;
    // What the next weekly slot check does. Replace per test.
    late Future<void> Function() slotFn;

    setUp(() async {
      events = [];
      listCalls = 0;
      captureCalls = 0;
      slotCalls = 0;
      deleted = [];
      readFn = () async => <Map<String, dynamic>>[];
      slotFn = () async {};
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
      ProgressPhotoRepository.debugEnsureFreeSlotOverride = () {
        slotCalls++;
        return slotFn();
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

    Future<void> payInFlight(WidgetTester tester) => tester.runAsync(
        () => SubscriptionService.instance.markPaymentInFlight(orderId: 'o1'));

    final paywall =
        find.text(paywallLetterheadTitle(ProgressPhotoCopy.paywallFeature));
    final caption = find.byKey(const ValueKey('progress_photos_free_caption'));
    final weeklyUsed = find.text(ProgressPhotoCopy.weeklyUsed);

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

    testWidgets('LAPSED with photos: the gallery with the free caption and the '
        'Add button', (tester) async {
      await makeFree(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('FRONT'), findsOneWidget);
      expect(find.text('SIDE'), findsOneWidget);
      expect(find.text('BACK'), findsOneWidget);
      expect(find.text('PRO FEATURE'), findsNothing);
      expect(caption, findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
      expect(find.text('No photos yet'), findsNothing);
      expect(slotCalls, 0);
      expect(captureCalls, 0);
    });

    testWidgets('LAPSED: Add with this week\'s slot used shows the weekly-used '
        'snackbar and reaches no picker, no capture and no paywall',
        (tester) async {
      await makeFree(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      slotFn = () async =>
          throw const PhotoQuotaException(weeklyCap: 1, message: 'used');

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      expect(slotCalls, 1);
      expect(weeklyUsed, findsOneWidget);
      expect(paywall, findsNothing);
      expect(find.text('Camera'), findsNothing);
      expect(find.text('Gallery'), findsNothing);
      expect(captureCalls, 0);
      expect(find.text('FRONT'), findsOneWidget,
          reason: 'the tap must not hide the photos the user holds');
    });

    testWidgets('LAPSED: Add with an open slot goes on to the picker and one '
        'capture', (tester) async {
      await makeFree(tester);
      readFn = () async => <Map<String, dynamic>>[];
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      readFn = () async => [_three[0]];

      await openAddAndPickGallery(tester);

      expect(slotCalls, 1);
      expect(captureCalls, 1);
      expect(find.text('FRONT'), findsOneWidget);
      expect(paywall, findsNothing);
      expect(caption, findsOneWidget,
          reason: 'the capture re-reads with the FREE verdict');
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
      expect(caption, findsOneWidget);
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
      expect(find.text('No photos yet'), findsNothing);
      expect(find.text('Couldn\'t refresh your photos'), findsOneWidget);
    });

    testWidgets('LAPSED: deleting the LAST photo with a successful empty read '
        'ends on the empty state, with the caption and the Add button',
        (tester) async {
      await makeFree(tester);
      readFn = () async => [_three[0]];
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.text('FRONT'), findsOneWidget);

      readFn = () async => <Map<String, dynamic>>[];
      await deleteTile(tester, 'FRONT');

      expect(find.text('No photos yet'), findsOneWidget);
      expect(caption, findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('LAPSED: deleting the last photo when the refresh FAILS is the '
        'error state, never "no photos"', (tester) async {
      await makeFree(tester);
      readFn = () async => [_three[0]];
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      readFn = () async => throw StateError('network down');
      await deleteTile(tester, 'FRONT');

      expect(find.text('No photos yet'), findsNothing,
          reason: 'a failed read must not be read as "no photos" (class 2.49)');
      expect(find.text('Couldn\'t load photos'), findsWidgets);
      expect(caption, findsNothing,
          reason: 'the caption belongs to a gallery or an empty state, not to '
              'the error state');
    });

    testWidgets('a failed first read with nothing on screen is the error state '
        'with Retry, and Retry recovers', (tester) async {
      await makeFree(tester);
      readFn = () async => throw StateError('offline');
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('No photos yet'), findsNothing,
          reason: 'offline must not read as an empty gallery');
      expect(find.text('Couldn\'t load photos'), findsWidgets);

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

      // The first delete starts a reload whose read stays pending.
      final older = Completer<List<Map<String, dynamic>>>();
      readFn = () => older.future;
      await tester.longPress(find.text('FRONT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump();

      // The second delete starts a NEWER reload (known verdict: free).
      final newer = Completer<List<Map<String, dynamic>>>();
      readFn = () => newer.future;
      await tester.longPress(find.text('BACK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump();

      newer.complete([_three[1]]); // the newer answers first: only SIDE left
      await tester.pumpAndSettle();
      older.complete(<Map<String, dynamic>>[]); // the older, stale and EMPTY
      await tester.pumpAndSettle();

      expect(deleted, ['a', 'c']);
      expect(find.text('SIDE'), findsOneWidget,
          reason: 'the stale empty answer must not overwrite the newer gallery');
      expect(find.text('No photos yet'), findsNothing);
    });

    testWidgets('a payer who upgrades while a free reload is in flight ends '
        'on the PRO gallery (one re-run)', (tester) async {
      late _Sub sub;
      await makeFree(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app(capture: (s) => sub = s));
      await tester.pumpAndSettle();
      expect(find.text('Add photo'), findsOneWidget);
      expect(caption, findsOneWidget);

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
      expect(caption, findsNothing,
          reason: 'the re-run left the free state');
    });

    testWidgets('a payer\'s full re-check is not overwritten by a later reload '
        'that carries the old free verdict', (tester) async {
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

      // A PRO user with no photos sees the empty gallery WITHOUT the free caption.
      expect(caption, findsNothing,
          reason: 'a stale free verdict must not win over the re-check');
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

    // ── Server refusal (the free weekly cap migration) ────────────────────

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
      expect(weeklyUsed, findsNothing);
      expect(find.text('FRONT'), findsOneWidget);
      expect(caption, findsNothing);
      expect(slotCalls, 0, reason: 'PRO never asks for the free slot');
    });

    testWidgets('PRO with NO photos, payment in flight, refused: stays on the '
        'empty state, no caption', (tester) async {
      await makePro(tester);
      readFn = () async => <Map<String, dynamic>>[];
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await payInFlight(tester);
      ProgressPhotoRepository.debugCaptureOverride = (_, _) async {
        throw const ProgressPhotoProRequiredException();
      };

      await openAddAndPickGallery(tester);

      expect(find.textContaining('still activating'), findsOneWidget);
      expect(caption, findsNothing,
          reason: 'the most likely just-paid case: a new payer holds no photos '
              'and must not be told the free rule');
      expect(find.text('No photos yet'), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
      expect(paywall, findsNothing);
    });

    testWidgets('PRO locally but the server says NOT PRO -> the weekly-used '
        'snackbar, NO automatic paywall, the photos stay and the screen is '
        're-decided as free', (tester) async {
      await makePro(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(caption, findsNothing);

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

      expect(weeklyUsed, findsOneWidget);
      expect(paywall, findsNothing,
          reason: 'the paywall opens only from the snackbar\'s GO PRO action');
      expect(find.text('FRONT'), findsOneWidget,
          reason: 'the lapsed user keeps seeing their photos');
      expect(caption, findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('PRO with NO photos locally but the server says NOT PRO -> the '
        'weekly-used snackbar and the free empty state', (tester) async {
      await makePro(tester);
      readFn = () async => <Map<String, dynamic>>[];
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.text('No photos yet'), findsOneWidget);
      expect(caption, findsNothing);

      final lapsed = Completer<void>();
      ProgressPhotoRepository.debugCaptureOverride = (_, _) async {
        await lapsed.future;
        throw const ProgressPhotoProRequiredException();
      };
      await openAddAndPickGallery(tester, settle: false);
      await makeFree(tester);
      lapsed.complete();
      await tester.pumpAndSettle();

      expect(weeklyUsed, findsOneWidget);
      expect(paywall, findsNothing);
      expect(find.text('No photos yet'), findsOneWidget);
      expect(caption, findsOneWidget,
          reason: 'the reload with the known verdict makes it the free state');
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('FREE whose slot check passed but the server refuses (another '
        'device took the slot) -> the weekly-used snackbar, no paywall',
        (tester) async {
      await makeFree(tester);
      readFn = () async => _three;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      ProgressPhotoRepository.debugCaptureOverride = (_, _) async {
        captureCalls++;
        throw const ProgressPhotoProRequiredException();
      };

      await openAddAndPickGallery(tester);

      expect(slotCalls, 1);
      expect(captureCalls, 1);
      expect(weeklyUsed, findsOneWidget);
      expect(paywall, findsNothing);
      expect(find.text('FRONT'), findsOneWidget);
      expect(caption, findsOneWidget);
    });

    testWidgets('PRO refused but the server cannot say otherwise -> "couldn\'t '
        'confirm", no paywall, no weekly-used snackbar', (tester) async {
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
      expect(weeklyUsed, findsNothing);
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
      expect(slotCalls, 0);
    });
  });
}
