// Unit 4 (d-bf, 2026-06-14) — pins BodyFatDefaultHealer: a one-time heal that
// nulls the FABRICATED onboarding body-fat default (18.0) so the profile-edit
// Katch recompute (profile_provider.recalculateTargets) stops feeding a made-up
// 18% into every skip-user's calorie target.
//
// Discriminator: heal ONLY when body_fat_percent == 18.0 AND body_fat_assessed_at
// == null (stepped + legacy-chat onboarding never stamp assessed_at; only the AI
// scan / Edit-Profile does). A genuinely-assessed 18.0 or any other value is left
// alone. Kill-switch: configBox['disable_bodyfat_heal'].
//
// Cloud-clear path: when there is no Supabase session (uid == null, as in this
// unit test) the healer skips the cloud UPDATE and nulls only local — so this
// drives the local heal without a live backend. (Production runs it post-auth
// with a session, clearing cloud FIRST then local — see the class doc.)

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/body_fat_default_healer.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_bf_heal');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'userBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  Future<void> seedProfile(Map<String, dynamic> profile) async {
    await HiveService.instance.userBox.put('profile', profile);
  }

  Map readProfile() => HiveService.instance.userBox.get('profile') as Map;

  test('18.0 + never-assessed → nulled (the fabricated default)', () async {
    await seedProfile({
      'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      'body_fat_percent': 18.0,
      'body_fat_assessed_at': null,
      'current_weight_kg': 80.0, // unrelated key must survive
    });

    await BodyFatDefaultHealer.runIfNeeded();

    final p = readProfile();
    expect(p['body_fat_percent'], isNull,
        reason: 'fabricated 18.0 default must be cleared');
    expect(p['current_weight_kg'], 80.0,
        reason: 'heal is surgical — unrelated keys preserved');
  });

  test('18.0 + genuinely assessed → KEPT (real value the user/AI set)', () async {
    await seedProfile({
      'body_fat_percent': 18.0,
      'body_fat_assessed_at': '2026-05-01T10:00:00.000Z',
    });

    await BodyFatDefaultHealer.runIfNeeded();

    expect(readProfile()['body_fat_percent'], 18.0,
        reason: 'an assessed 18.0 is a real measurement — never heal it');
  });

  test('22.0 + never-assessed → KEPT (not the fabricated default)', () async {
    await seedProfile({
      'body_fat_percent': 22.0,
      'body_fat_assessed_at': null,
    });

    await BodyFatDefaultHealer.runIfNeeded();

    expect(readProfile()['body_fat_percent'], 22.0,
        reason: 'only the exact 18.0 default is suspect; 22.0 is user input');
  });

  test('already null → no-op (no crash, stays null)', () async {
    await seedProfile({
      'body_fat_percent': null,
      'body_fat_assessed_at': null,
    });

    await BodyFatDefaultHealer.runIfNeeded();

    expect(readProfile()['body_fat_percent'], isNull);
  });

  test('idempotent — second run is a no-op (value already null)', () async {
    await seedProfile({
      'body_fat_percent': 18.0,
      'body_fat_assessed_at': null,
    });

    await BodyFatDefaultHealer.runIfNeeded();
    expect(readProfile()['body_fat_percent'], isNull);

    // Second run: discriminator (bf != 18.0) short-circuits cleanly.
    await BodyFatDefaultHealer.runIfNeeded();
    expect(readProfile()['body_fat_percent'], isNull);
  });

  test('kill-switch (disable_bodyfat_heal) leaves the 18.0 untouched', () async {
    await HiveService.instance.configBox
        .put(BodyFatDefaultHealer.killSwitch, true);
    await seedProfile({
      'body_fat_percent': 18.0,
      'body_fat_assessed_at': null,
    });

    await BodyFatDefaultHealer.runIfNeeded();

    expect(readProfile()['body_fat_percent'], 18.0,
        reason: 'kill-switch must fully disable the heal');
  });

  // B-pass F2 — the cloud-clear path can't run in a unit test (no Supabase
  // session → uid == null → the `if (uid != null)` block is skipped). Pin the
  // CLOUD contract at the SOURCE level so a wrong table/column/filter or a
  // dropped fresh-token is caught here; the column itself is validated against
  // the live schema by scripts/check_schema_column_refs.dart (it scans lib/
  // .from().update() refs), and the local heal is proven behaviorally above.
  group('source — cloud-clear contract (the untestable-in-unit path)', () {
    final src = _strip(
        File('lib/core/services/body_fat_default_healer.dart')
            .readAsStringSync());

    test('clears the correct cloud table + column under the user filter', () {
      expect(src.contains("from('user_profile')"), isTrue,
          reason: 'cloud heal must target the user_profile table');
      expect(src.contains("update({'body_fat_percent': null})"), isTrue,
          reason: 'cloud heal must null body_fat_percent (schema-gate validated)');
      expect(src.contains(".eq('user_id', uid)"), isTrue,
          reason: 'cloud heal must scope to the current user_id');
    });

    test('requires a fresh token BEFORE the cloud update, and defers if null',
        () {
      final tokenIdx = src.indexOf('ensureFreshToken');
      final updateIdx = src.indexOf("from('user_profile')");
      expect(tokenIdx, greaterThanOrEqualTo(0),
          reason: 'must call ensureFreshToken (§2.31 boot-adjacent token)');
      expect(tokenIdx, lessThan(updateIdx),
          reason: 'fresh token must be acquired BEFORE the cloud update');
      expect(src.contains('if (token == null) return'), isTrue,
          reason: 'no fresh token → defer the WHOLE heal (no cloud/local split)');
    });

    test('nulls local AFTER the cloud block (cloud-first ordering)', () {
      final updateIdx = src.indexOf("from('user_profile')");
      final localIdx = src.indexOf("profile['body_fat_percent'] = null");
      expect(localIdx, greaterThan(updateIdx),
          reason: 'cloud clear must precede the local null (durability claim)');
    });
  });
}
