@Timeout(Duration(minutes: 2))
library;

// L2a (OI-297, B-pass) - the two chat entry points that guard the body
// measurement site list. Both call isBodyMeasurementSite (the registry) so a
// model-invented part such as 'thighs' never reaches a day record; this file
// executes them (the derivation test only greps for the symbol). Since L2b
// Landing A, HealthWriteService.logMeasurement validates the part and the
// value as well (test/contracts/body_measurement_bounds_behavioral_test.dart),
// and the chat parse drops an out-of-range value, so these two guards are the
// pre-filter and the writer is the backstop.
//
// The in-range fixtures below are LITERALS on purpose: derived from
// kBodyMeasurementSpecs they would follow a moved bound and prove nothing.

import 'dart:convert';

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

/// One in-range centimetre value per site and the confirm-card text it must
/// produce. A new site in the registry fails the lookups below on purpose: it
/// owes a fixture here.
const _inRange = <String, ({double cm, String card})>{
  'chest': (cm: 95, card: 'Chest: 95.0cm'),
  'waist': (cm: 80, card: 'Waist: 80.0cm'),
  'hips': (cm: 95, card: 'Hips: 95.0cm'),
  'arms': (cm: 35, card: 'Arms: 35.0cm'),
};

/// Values implausible as centimetres, per the bounds of L2b Landing A: below a
/// floor (inches typed in a centimetre field), above a ceiling, zero, negative
/// and an Infinity. `1e999` decodes to Infinity when the app decodes it itself;
/// the proxy's JSON.stringify turns an Infinity into null before a reply
/// reaches the app, so this row is the latent hazard, not a wire case.
final _outOfRange = <({String site, Object value, String why})>[
  (site: 'waist', value: 40, why: 'waist 40 is inches'),
  (site: 'arms', value: 80, why: 'arms 80 is above the ceiling'),
  (site: 'chest', value: 3000, why: 'chest 3000'),
  (site: 'hips', value: 59.9, why: 'hips just under the floor'),
  (site: 'waist', value: 0, why: 'zero'),
  (site: 'waist', value: -1, why: 'negative'),
  (site: 'waist', value: jsonDecode('1e999') as Object, why: 'Infinity'),
];

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
        final fixture = _inRange[site]!;
        final pending = parse({'type': site, 'value_cm': fixture.cm});
        expect(pending, hasLength(1), reason: site);
        expect(pending.single.type, LogActionType.measurement);
        expect(pending.single.displayText, fixture.card, reason: site);
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

    test('an out-of-range or non-finite value is dropped, whatever the site', () {
      for (final c in _outOfRange) {
        expect(
          parse({'type': c.site, 'value_cm': c.value}),
          isEmpty,
          reason: c.why,
        );
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
            await run({'type': site, 'value_cm': _inRange[site]!.cm}),
            isTrue,
            reason: site,
          );
        }
        final keys = measurementKeys();
        expect(keys, hasLength(1), reason: 'one record per IST day');
        final rec = HiveService.instance.healthBox.get(keys.single) as Map;
        for (final site in kBodyMeasurementSites) {
          expect(rec[site], _inRange[site]!.cm, reason: site);
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

    testWidgets(
      'an out-of-range or non-finite value is refused by the writer and writes nothing',
      (tester) => withHandler(tester, (run, measurementKeys) async {
        // The handler's only own check is `valueCm <= 0` (the zero and negative
        // rows below are refused there); every other refusal is the writer's,
        // which is what makes a handler-tier bound redundant (plan A5).
        for (final c in _outOfRange) {
          expect(
            await run({'type': c.site, 'value_cm': c.value}),
            isFalse,
            reason: c.why,
          );
        }
        expect(
          await run({'type': 'waist', 'value_cm': double.nan}),
          isFalse,
          reason: 'NaN passes the handler\'s own <= 0 test and the writer refuses it',
        );
        expect(
          measurementKeys(),
          isEmpty,
          reason: 'a refused value must not create a day record',
        );
      }),
    );
  });
}
