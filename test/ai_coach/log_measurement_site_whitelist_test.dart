@Timeout(Duration(minutes: 2))
library;

// L2a (OI-297, B-pass) - the two chat entry points that guard the body
// measurement site list. HealthWriteService.logMeasurement does not
// re-validate the part ("we don't re-validate here to stay flexible"), so
// these two call sites are the only thing between a model-invented part such as
// 'thighs' and a day record carrying a key no push or reader knows. Both
// guards now call isBodyMeasurementSite (the registry); this file executes them
// (the derivation test only greps for the symbol).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/body_measurement_sites.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/services/conversational_log_handler.dart';

import '../helpers/hive_test_setup.dart';

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  group('PendingLogActionsNotifier.addActions (the chat action parser)', () {
    late dynamic tempDir;
    setUp(() async {
      tempDir = await setUpHiveForTests();
    });
    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    List<PendingLogAction> parse(Map<String, dynamic> data) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(pendingLogActionsProvider.notifier).addActions([
        {'action': 'log_measurement', 'data': data},
      ], c.read(_refProvider));
      return c.read(pendingLogActionsProvider);
    }

    test('every site token becomes a confirm card', () {
      for (final site in kBodyMeasurementSites) {
        final pending = parse({'type': site, 'value_cm': 80});
        expect(pending, hasLength(1), reason: site);
        expect(pending.single.type, LogActionType.measurement);
        expect(
          pending.single.displayText,
          '${site[0].toUpperCase()}${site.substring(1)}: 80.0cm',
        );
      }
    });

    test('anything that is not a site token is dropped, case included', () {
      for (final t in ['thighs', 'Waist', 'neck', '', ' waist']) {
        expect(parse({'type': t, 'value_cm': 50}), isEmpty, reason: "'$t'");
      }
      expect(parse({'value_cm': 50}), isEmpty, reason: 'no type at all');
    });

    test('a missing, zero or negative value is dropped', () {
      for (final v in <Object?>[null, 0, -3]) {
        expect(parse({'type': 'waist', 'value_cm': v}), isEmpty, reason: '$v');
      }
    });
  });

  group('ConversationalLogHandler.executeAction (the confirm handler)', () {
    // The handler takes a WidgetRef, which is sealed (it cannot be faked), so
    // a real one is captured from a Consumer. Real disk I/O must run inside
    // tester.runAsync (CLAUDE.md section 4.9), hence Hive is opened there.
    Future<void> withHandler(
      WidgetTester tester,
      Future<void> Function(
        Future<bool> Function(Map<String, dynamic> data) run,
        List<String> Function() measurementKeys,
      )
      body,
    ) async {
      late WidgetRef ref;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.runAsync(() async {
        final tempDir = await setUpHiveForTests();
        HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
        // logMeasurement fires a background sync pass; there is no cloud here.
        SyncService.pausedForSimulation = true;
        try {
          await body(
            (data) => ConversationalLogHandler(ref).executeAction(
              PendingLogAction(
                id: 'x',
                type: LogActionType.measurement,
                data: data,
                displayText: '',
              ),
            ),
            () => HiveService.instance.healthBox.keys
                .whereType<String>()
                .where((k) => k.startsWith('measurement_'))
                .toList(),
          );
        } finally {
          SyncService.pausedForSimulation = false;
          HiveUserSession.debugCurrentUidResolverForTests = null;
          await tearDownHiveForTests(tempDir);
        }
      });
    }

    testWidgets(
      'a site is written through HealthWriteService into the day record',
      (tester) => withHandler(tester, (run, measurementKeys) async {
        for (final site in kBodyMeasurementSites) {
          expect(
            await run({'type': site, 'value_cm': 70.5}),
            isTrue,
            reason: site,
          );
        }
        final keys = measurementKeys();
        expect(keys, hasLength(1), reason: 'one record per IST day');
        final rec = HiveService.instance.healthBox.get(keys.single) as Map;
        for (final site in kBodyMeasurementSites) {
          expect(rec[site], 70.5, reason: site);
        }
      }),
    );

    testWidgets(
      'a token that is not a site writes nothing and reports failure',
      (tester) => withHandler(tester, (run, measurementKeys) async {
        for (final t in ['thighs', 'Waist', 'neck', '']) {
          expect(
            await run({'type': t, 'value_cm': 50}),
            isFalse,
            reason: "'$t'",
          );
        }
        expect(await run({'value_cm': 50}), isFalse, reason: 'no type');
        expect(
          measurementKeys(),
          isEmpty,
          reason: 'a rejected part must not create a day record',
        );
      }),
    );

    testWidgets(
      'a missing, zero or negative value writes nothing',
      (tester) => withHandler(tester, (run, measurementKeys) async {
        for (final v in <Object?>[null, 0, -3]) {
          expect(
            await run({'type': 'waist', 'value_cm': v}),
            isFalse,
            reason: '$v',
          );
        }
        expect(measurementKeys(), isEmpty);
      }),
    );
  });
}
