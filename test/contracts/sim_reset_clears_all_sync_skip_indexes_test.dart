// Day-swapper + sync-load Task 20 (coordinator addendum) — resetJourney used
// to clear only 3 (of what are now 17) sync-skip-index domains by string
// literal. SyncSkipIndex.clearAll replaces those 3 literal/symbolic deletes
// and walks every SyncSkipDomain, so a sim reset never leaves a stale
// fingerprint behind to mis-skip a re-drive push. Behavioural — the
// pre-existing source-grep tests (sched/exlog/nlog) only prove resetJourney's
// source CONTAINS the call; this proves the call actually empties every box.
//
// Calls SimulationService.instance.clearJourneyLocalState() directly rather
// than resetJourney(WidgetRef ref) — Step 3g/3h of this task's Task 20
// section extracts exactly the Hive-only tail resetJourney used to run
// inline (the SyncSkipIndex.clearAll call plus the _clearKeysWithPrefixes
// calls) into that new no-WidgetRef instance method, specifically so this
// index-clearing behaviour is testable without a ProviderContainer/
// WidgetTester harness. resetJourney's own signature and every ref-using
// line are untouched; test/sim/lt_journey_plan_export.dart's
// `resetJourney(ref)` call site still compiles unchanged.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/features/dev/simulation_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() => tearDownHiveForTests(tempDir));

  test('clearJourneyLocalState clears all 17 SyncSkipDomain indexes, across '
      'all 4 boxes', () async {
    Box<dynamic> boxFor(SyncSkipBox b) => switch (b) {
          SyncSkipBox.workout => HiveService.instance.workoutBox,
          SyncSkipBox.nutrition => HiveService.instance.nutritionBox,
          SyncSkipBox.health => HiveService.instance.healthBox,
          SyncSkipBox.custom => HiveService.instance.customBox,
        };
    for (final d in SyncSkipDomain.values) {
      await boxFor(d.box).put(d.indexKey, {'seed-key': 'seed-fp'});
    }
    for (final d in SyncSkipDomain.values) {
      expect(boxFor(d.box).containsKey(d.indexKey), isTrue,
          reason: 'seed must land before the reset runs — ${d.name}');
    }

    await SimulationService.instance.clearJourneyLocalState();

    for (final d in SyncSkipDomain.values) {
      expect(boxFor(d.box).containsKey(d.indexKey), isFalse,
          reason: '${d.name} survived clearJourneyLocalState — stale '
              'fingerprint will mis-skip the next re-drive push');
    }
  });
}
