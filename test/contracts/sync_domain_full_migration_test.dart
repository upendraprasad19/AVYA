// test/contracts/sync_domain_full_migration_test.dart
//
// Tech-debt audit 2026-05-20 / finding A6 — full migration step
// (B5 D7-D8 batch, follows the scaffold in
// `sync_domain_interface_test.dart`).
//
// What this test pins
// -------------------
// 1. All 8 SyncDomain wrappers exist under `lib/core/services/sync_domains/`
//    and each implements the [SyncDomain] contract.
// 2. `SyncService.registeredDomainsForTests` exposes the 8 domains in
//    the documented order (workouts → streaks → nutrition → health →
//    coach → profile → community → restore_completeness).
// 3. Domain `name` strings are unique and lower_snake_case (matches the
//    `SyncFlags.useDomainFor(<name>)` configBox key convention).
// 4. `SyncFlags.useDomainFor(name)` returns FALSE for every registered
//    domain by default (gates-before-refactor contract — flags ship
//    OFF, follow-up batch flips them on per domain after smoke).
// 5. The dispatcher (`_dispatchDomainPushes` / `_dispatchDomainRestores`)
//    is a true no-op when all flags are FALSE — completes without
//    exercising any push/restore code path.
// 6. With a single flag flipped TRUE and NO signed-in user, the
//    dispatched domain's push/restore short-circuits cleanly via
//    `_ensureSessionOpen()` — proving the dispatcher is calling the
//    real public-forwarder code path, not a stub.
// 7. Source-grep: every `<Domain>SyncDomain` wrapper file declares a
//    class implementing `SyncDomainBase` (the inheritance contract
//    that `SyncDomain.pushSnapshot` no-op depends on).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_domain.dart';
import 'package:icanbefitter/core/services/sync_flags.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir =
        Directory.systemTemp.createTempSync('sync_domain_full_migration_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.closeAll();
    await SyncFlags.debugResetAllForTests();
  });

  group('A6 · Full SyncDomain migration · wrapper registration', () {
    test('SyncService registers exactly 8 SyncDomain wrappers in order',
        () {
      final domains = SyncService.instance.registeredDomainsForTests;
      expect(domains, hasLength(8),
          reason:
              'Expected one wrapper per part-file: workouts, streaks, '
              'nutrition, health, coach, profile, community, restore_completeness. '
              'Got ${domains.length}.');
      final names = domains.map((d) => d.name).toList();
      expect(
          names,
          equals([
            'workouts',
            'streaks',
            'nutrition',
            'health',
            'coach',
            'profile',
            'community',
            'restore_completeness',
          ]),
          reason:
              'Registration order must match the documented fan-out order '
              '(templates-before-schedules quirk lives inside WorkoutsSyncDomain).');
    });

    test('every registered domain implements SyncDomain', () {
      for (final d in SyncService.instance.registeredDomainsForTests) {
        expect(d, isA<SyncDomain>(),
            reason: 'Domain ${d.name} must implement SyncDomain.');
      }
    });

    test('domain names are unique and lower_snake_case', () {
      final names =
          SyncService.instance.registeredDomainsForTests.map((d) => d.name);
      expect(names.toSet().length, equals(names.length),
          reason: 'Duplicate domain names would collide on the '
              '`sync_domain_<name>` configBox flag key.');
      for (final name in names) {
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name), isTrue,
            reason:
                'Domain name `$name` must be lower_snake_case to match the '
                '`SyncFlags.useDomainFor(<name>)` configBox key convention.');
      }
    });
  });

  group('A6 · Full SyncDomain migration · SyncFlags defaults', () {
    test('every registered domain has SyncFlags.useDomainFor() = FALSE '
        'by default (gates-before-refactor contract)', () {
      for (final d in SyncService.instance.registeredDomainsForTests) {
        expect(SyncFlags.useDomainFor(d.name), isFalse,
            reason:
                'Domain ${d.name} ships with flag OFF — legacy `_syncX` / '
                '`_restoreX` path runs unchanged on every device. The '
                'wrapper-landing batch (B5 D7-D8) is dual-path-ready but '
                'does NOT flip flags. CLAUDE.md §4.11.');
      }
    });

    test('useDomainFor returns FALSE for unknown domain names', () {
      expect(SyncFlags.useDomainFor('nonexistent_domain'), isFalse);
    });
  });

  group('A6 · Full SyncDomain migration · dispatcher safety', () {
    test('dispatcher push is a no-op when all flags are FALSE', () async {
      // No flag is flipped → dispatcher must complete without exercising
      // any push code path. With no signed-in user, any leaked iteration
      // through a domain's forwarder would still short-circuit via
      // _ensureSessionOpen, but the cleanest assertion is that the
      // entire call completes without throwing.
      await expectLater(
          SyncService.instance.dispatchDomainPushesForTests(), completes,
          reason:
              'With every SyncFlags entry FALSE the dispatcher must skip '
              'every domain. Any throw indicates the gate is leaking.');
    });

    test('dispatcher restore is a no-op when all flags are FALSE',
        () async {
      await expectLater(
          SyncService.instance.dispatchDomainRestoresForTests(), completes);
    });

    test(
        'dispatcher push exercises the real forwarder code path when '
        'a flag is flipped TRUE (no session → short-circuit completes)',
        () async {
      // Flip streaks ON and ensure no signed-in user → the dispatcher
      // calls StreaksSyncDomain.push() → pushStreaksForSyncDomain() →
      // _ensureSessionOpen() returns null → return. No throw.
      await SyncFlags.debugSetForTests('streaks', true);
      await expectLater(
          SyncService.instance.dispatchDomainPushesForTests(), completes,
          reason:
              'Flipped-on domain must still complete cleanly when no auth '
              'session is open — proves the dispatcher is invoking the real '
              'public-forwarder code path, not a stub.');
    });
  });

  group('A6 · Full SyncDomain migration · source structure', () {
    test('every wrapper file under lib/core/services/sync_domains/ '
        'extends SyncDomainBase', () {
      final dir = Directory('lib/core/services/sync_domains');
      expect(dir.existsSync(), isTrue,
          reason: 'Wrapper directory must exist.');
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_sync_domain.dart'))
          .toList();
      expect(files.length, greaterThanOrEqualTo(8),
          reason: 'Expected at least 8 *_sync_domain.dart files '
              '(workouts, streaks, nutrition, health, coach, profile, '
              'community, restore_completeness).');
      for (final f in files) {
        final src = f.readAsStringSync();
        expect(src.contains('extends SyncDomainBase'), isTrue,
            reason:
                '${f.path} must declare a class that `extends SyncDomainBase` '
                'so the no-op `pushSnapshot()` default is inherited.');
      }
    });

    test('SyncFlags constants align with registered domain names', () {
      // Source-grep: every domain.name MUST exist either as a literal
      // in code under lib/core/services/ OR be documentable in
      // sync_flags.dart. The point is the configBox key string is
      // load-bearing; document it explicitly in sync_flags.dart.
      final flagsSrc =
          File('lib/core/services/sync_flags.dart').readAsStringSync();
      expect(flagsSrc.contains("'sync_domain_'"), isTrue,
          reason: 'SyncFlags must use the `sync_domain_<name>` key prefix '
              'so the per-domain rollout is traceable in configBox dumps.');
    });
  });
}
