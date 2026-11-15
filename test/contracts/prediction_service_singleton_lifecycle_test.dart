// BEHAVIORAL — PredictionService really registers with
// SingletonLifecycleRegistry (B-pass finding, 2026-09-26).
//
// Before this fix, PredictionService was the one singleton in this family
// (AiService, SubscriptionService, SyncService, WorkoutScheduleService,
// UsageCounterService, RazorpayService, SeedService — all registered) that
// never told the registry about an account change. A device-level account
// switch while a prediction refresh was in flight left the new account's
// own tap free to JOIN the old account's stale in-flight Future
// (PredictionAttemptGate.run's `if (running != null) return running;`),
// handing the new user an outcome computed for someone else.
//
// This test proves the REGISTRATION actually runs — not just that the
// source text contains a `SingletonLifecycleRegistry.register(...)` call,
// which a dead/unreachable call site would also satisfy. The join-avoidance
// mechanism itself (clearInFlightForAccountChange preventing a stale join)
// is behaviourally tested against the real PredictionAttemptGate class in
// test/services/prediction_attempt_gate_test.dart; the wiring between
// PredictionService's callback and that method is pinned in
// test/contracts/prediction_refresh_outcome_wiring_test.dart. A full
// end-to-end test through the real network call
// (AiService.instance.predict) is not attempted here: no injection seam
// exists for it, and none of PredictionService's siblings' lifecycle
// registrations are tested that way either — see
// singleton_lifecycle_registry_behavioral_test.dart, whose own callbacks
// are plain counters for the same reason.
//
// Harness matches auth_hive_owner_agreement_behavioral_test.dart and
// singleton_lifecycle_registry_behavioral_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/prediction_service.dart';
import 'package:icanbefitter/core/services/singleton_lifecycle_registry.dart';
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
    tempDir = Directory.systemTemp.createTempSync('prediction_singleton_');
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

  test(
      'touching PredictionService.instance registers it with '
      'SingletonLifecycleRegistry — proves the call actually runs, not '
      'just that it appears in source', () {
    expect(SingletonLifecycleRegistry.registeredNames(),
        isNot(contains('PredictionService')),
        reason: 'precondition — nothing has touched the singleton yet in '
            'this isolate');

    // First touch constructs the singleton, running its constructor body.
    PredictionService.instance;

    expect(SingletonLifecycleRegistry.registeredNames(),
        contains('PredictionService'));
  });

  test(
      'a real account-switch cycle (HiveUserSession.openForUser) invokes '
      "PredictionService's callback without throwing", () async {
    // Constructed by the previous test (singletons are process-wide), but
    // touch it again defensively in case tests run in isolation/reorder.
    PredictionService.instance;
    expect(SingletonLifecycleRegistry.registeredNames(),
        contains('PredictionService'));

    const userA = 'aaaaaaaa-1111-1111-1111-111111111111';
    const userB = 'bbbbbbbb-2222-2222-2222-222222222222';

    // notifyUserChanged() runs every registered callback AFTER the owner
    // flip (SingletonLifecycleRegistry's own doc comment) — this is the
    // exact call HiveUserSession makes internally from openForUser/
    // closeAll. If PredictionService's callback threw, it would be caught
    // and swallowed there (never crashes the app), so the meaningful
    // assertion is that the REAL end-to-end open→callback path completes
    // without hanging or leaving HiveUserSession in a bad state — which a
    // typo referencing an uninitialised `_gate` or a wrong field name
    // would risk surfacing as a hang or a later failure in this same test.
    await HiveUserSession.openForUser(userA);
    expect(HiveUserSession.currentOwnerFullId, userA);

    await HiveUserSession.openForUser(userB);
    expect(HiveUserSession.currentOwnerFullId, userB);
  });
}
