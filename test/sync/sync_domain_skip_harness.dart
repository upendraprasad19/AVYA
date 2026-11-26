// Shared setup + the per-domain skip contract (spec §9 "Sync") used by every
// sync domain test and every Gate 9 `sync_*_payload_hash_index` contract file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/sync_stub_server.dart';

class SyncHarness {
  late Directory _hiveDir;
  final SyncStubServer server = SyncStubServer();

  Future<void> setUp() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _hiveDir = await setUpHiveForTests();
    await server.start();
    SupabaseService.clientOverrideForTest = server.client();
    HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
  }

  /// Each cleanup step is isolated so one failing step cannot throw out of
  /// `tearDown()` and skip the rest (CLAUDE.md §4.9 — teardown must never
  /// throw).
  Future<void> tearDown() async {
    try {
      SupabaseService.clientOverrideForTest = null;
    } catch (_) {}
    try {
      HiveUserSession.debugCurrentUidResolverForTests = null;
    } catch (_) {}
    try {
      await server.stop();
    } catch (_) {}
    try {
      await tearDownHiveForTests(_hiveDir);
    } catch (_) {}
  }
}

Box<dynamic> skipBoxOf(SyncSkipDomain d) => switch (d.box) {
      SyncSkipBox.workout => HiveService.instance.workoutBox,
      SyncSkipBox.nutrition => HiveService.instance.nutritionBox,
      SyncSkipBox.health => HiveService.instance.healthBox,
      SyncSkipBox.custom => HiveService.instance.customBox,
    };

/// The contract every history domain honours:
/// 1. the first pass pushes every row, with live-schema keys only, and records;
/// 2. an unchanged second pass sends nothing;
/// 3. one edited row sends exactly [writesPerRow] writes;
/// 4. a failed push is retried on the next pass;
/// 5. [touchSentAtOnly] (a change to a sent-at stamp only) sends nothing;
/// 6. the kill switch pushes everything and deletes the index.
Future<void> expectSkipContract({
  required SyncHarness h,
  required SyncSkipDomain domain,
  required String table,
  required Future<void> Function() runPass,
  required Future<void> Function() seed,
  required Future<void> Function(int generation) editOne,
  int writesPerRow = 1,
  Future<void> Function()? touchSentAtOnly,
}) async {
  await seed();
  await runPass();
  final firstPass = h.server.writesTo(table).length;
  expect(firstPass, greaterThan(0), reason: 'first pass pushes every row');
  expectWritesMatchLiveSchema(h.server);
  expect(SyncSkipIndex.readIndex(skipBoxOf(domain), domain.indexKey), isNotEmpty,
      reason: 'confirmed pushes are recorded');

  h.server.clear();
  await runPass();
  expect(h.server.writesTo(table), isEmpty,
      reason: 'an unchanged second pass sends nothing');

  await editOne(1);
  h.server.clear();
  await runPass();
  expect(h.server.writesTo(table), hasLength(writesPerRow),
      reason: 'one edited row sends only that row');

  await editOne(2);
  h.server
    ..clear()
    ..failWritesTo.add(table);
  await runPass();
  expect(h.server.writesTo(table), isNotEmpty, reason: 'the push was attempted');
  h.server
    ..clear()
    ..failWritesTo.remove(table);
  await runPass();
  expect(h.server.writesTo(table), hasLength(writesPerRow),
      reason: 'a failed push is retried on the next pass');

  if (touchSentAtOnly != null) {
    await touchSentAtOnly();
    h.server.clear();
    await runPass();
    expect(h.server.writesTo(table), isEmpty,
        reason: 'a change to a sent-at stamp alone sends nothing');
  }

  await HiveService.instance.configBox.put(domain.killSwitchKey, true);
  h.server.clear();
  await runPass();
  expect(h.server.writesTo(table), hasLength(firstPass),
      reason: 'the kill switch restores the unconditional sweep');
  expect(skipBoxOf(domain).containsKey(domain.indexKey), isFalse,
      reason: 'the kill switch deletes the index');
  await HiveService.instance.configBox.delete(domain.killSwitchKey);
}
