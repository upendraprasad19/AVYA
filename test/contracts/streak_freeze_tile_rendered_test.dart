// test/contracts/streak_freeze_tile_rendered_test.dart
//
// Diagnose a5e3c7 (ledger F8 / U6-PROFILE-TILE-COPY): the Profile service-record
// sheet's freeze tile read "FREEZES LEFT  n / max  THIS WEEK", the weekly
// allowance wording the snackbar and the explainer no longer use. The founder
// chose "IN RESERVE" on 2026-10-07. A freeze is a kept stock (+1 each Monday),
// so the unit line must not say "this week".
//
// This renders the REAL RankServiceRecordSheet against real Hive and reads the
// tile off the screen: the number comes from userBox['progress'] and the cap
// from the subscription state, exactly as in the app.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/profile/providers/promotion_history_provider.dart';
import 'package:icanbefitter/features/profile/widgets/rank_service_record_sheet.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('streak_freeze_tile_');
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
    await HiveUserSession.openForUser('cafeface-aaaa-bbbb-cccc-eeeeeeeeeeee');
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Puts a progress map holding [available] freezes (and PRO or not) into the
  /// open user box. The writes run under `runAsync` and are AWAITED: a `put`
  /// started inside the widget test's fake-async zone never completes, and the
  /// pending write then blocks `HiveUserSession.closeAll` in tearDownAll forever.
  Future<void> seed(WidgetTester tester,
      {required int available, required bool pro}) async {
    await tester.runAsync(() async {
      final box = HiveService.instance.userBox;
      await box.put('progress', <String, dynamic>{
        'current_phase': 2,
        'total_workouts_done': 31,
        'streak_freezes_available': available,
        'streak_freeze_used_dates': <String>[],
      });
      // proStateSnapshot(): flag set with no expiry is honoured in debug builds
      // (flutter test); the cross-account check cannot fire without a session.
      await box.put('isPro', pro);
    });
  }

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        promotionHistoryProvider
            .overrideWith((ref) async => <PromotionRecord>[]),
      ],
      child: const MaterialApp(
        home: Scaffold(body: RankServiceRecordSheet()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('Profile service-record sheet: the freeze tile, rendered', () {
    testWidgets('free user with 1 freeze: "FREEZES LEFT  1 / 1  IN RESERVE"',
        (tester) async {
      await seed(tester, available: 1, pro: false);
      await pumpSheet(tester);
      expect(find.text('FREEZES LEFT'), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.text('IN RESERVE'), findsOneWidget);
    });

    testWidgets('PRO user with 2 freezes: the cap is 3, "2 / 3"',
        (tester) async {
      await seed(tester, available: 2, pro: true);
      await pumpSheet(tester);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('IN RESERVE'), findsOneWidget);
    });

    testWidgets('none left still reads "0 / 1  IN RESERVE"', (tester) async {
      await seed(tester, available: 0, pro: false);
      await pumpSheet(tester);
      expect(find.text('0 / 1'), findsOneWidget);
      expect(find.text('IN RESERVE'), findsOneWidget);
    });

    testWidgets('the weekly-allowance unit line is gone from the whole sheet',
        (tester) async {
      await seed(tester, available: 1, pro: false);
      await pumpSheet(tester);
      expect(find.textContaining('THIS WEEK'), findsNothing);
      expect(find.textContaining('PER WEEK'), findsNothing);
    });
  });
}
