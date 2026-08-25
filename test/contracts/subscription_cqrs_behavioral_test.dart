// BEHAVIORAL contract for the OI-44 Unit 6 CQRS split on the entitlement
// surface. Rule 21: every assertion here was run against the UNFIXED code
// first and observed to fail (negative controls recorded in the diagnose-doc).
//
// THE DEFECT, traced end to end:
//   profile_provider.dart  SubscriptionInfoNotifier.build()
//     -> isPro()
//     -> _downgradeLocally()          (expiry or cross-account branch)
//     -> onStateChanged?.call()
//     -> app.dart:47  ref.invalidate(subscriptionInfoProvider)
// i.e. a Riverpod provider's build invalidating ITSELF. It terminated (the
// second pass reads isPro=false and returns before mutating) and the
// invalidation landed a microtask later rather than synchronously, so it was
// one wasted rebuild rather than a crash — but a build method must not mutate.
//
// HOW THIS IS TESTED. Rather than standing up the whole provider graph (which
// would pull auth + Hive-session providers and test Riverpod more than it
// tests this fix), these assert on the MECHANISM that makes the loop possible:
// whether a read fires `onStateChanged` — the exact hook app.dart wires to the
// invalidation. A read that cannot fire it cannot invalidate its own provider,
// whatever the graph above it looks like.
//
// Run: flutter test test/contracts/subscription_cqrs_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
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

String _pastIso() =>
    DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
String _futureIso() =>
    DateTime.now().add(const Duration(days: 30)).toIso8601String();

/// Waits for `_downgradeLocally`'s async MigratedKey writes to land.
///
/// `_downgradeLocally` awaits its MigratedKey writes before firing
/// `onStateChanged`, so the hook lands a few microtasks after the call returns.
///
/// A FIXED sleep is not a synchronization primitive. At 20 ms this file was
/// green on an idle machine and RED under load — observed 2026-08-10, when a
/// pre-push full suite failed on exactly one assertion here ("the decision path
/// must still wipe expiresAt") while background jobs ran, then passed 3/3 once
/// the machine went idle. Same commit, both times. That is the async-timing arm
/// of `feedback_local_ci_env_divergence`, and it blocks a push at random.
///
/// This waits for QUIESCENCE, not for a caller-supplied predicate, and that
/// choice is load-bearing. The first attempt at this fix took a per-call-site
/// `until:` predicate — and each site's predicate was derived from the FIRST
/// assertion that followed it, so at the site below (`isPro` → `expiresAt` →
/// `proLapsedAt`) the poll exited the moment `isPro` flipped, before the other
/// two writes landed. That turned a flaky test into a deterministically failing
/// one: strictly worse. Quiescence needs no per-site knowledge and therefore
/// cannot encode a partial view of what a given test asserts next.
///
/// `_downgradeLocally` writes several keys in sequence; the run is done when the
/// observed tuple stops changing. Sampling stops as soon as it is stable, so an
/// idle machine pays ~30 ms rather than a blanket sleep.
Future<void> _settle() async {
  const keys = ['isPro', 'expiresAt', 'pro_lapsed_at', 'plan'];
  String snapshot() =>
      keys.map((k) => '$k=${MigratedKey.read<dynamic>(k)}').join('|');

  final deadline = DateTime.now().add(const Duration(seconds: 5));
  var previous = snapshot();
  var stableRounds = 0;
  while (stableRounds < 3 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final current = snapshot();
    stableRounds = current == previous ? stableRounds + 1 : 0;
    previous = current;
  }
}

/// Every entitlement key a test in this file can leave behind.
const _entitlementKeys = <String>[
  'isPro',
  'expiresAt',
  'plan',
  'pro_lapsed_at',
  'lastVerifiedAt',
  'localActivationAt',
];

/// Clears the entitlement keys and KEEPS clearing until the clear STICKS.
///
/// WHY A LOOP AND NOT SIX `delete` CALLS (2026-08-25).
/// ---------------------------------------------------
/// A single delete pass is not enough, and [_settle] cannot rescue it. The
/// enforcement path stamps the lapse marker FIRE-AND-FORGET —
/// `subscription_service.dart:458`:
///
///     unawaited(MigratedKey.write(_proLapsedAtKey, expiresAt.toIso8601String()));
///
/// That write is issued OUTSIDE `_downgradeLocally`, so it is never awaited by
/// anything. [_settle] samples for quiescence, which closes the "write is
/// in-flight" window but NOT the "write has not been scheduled yet" one — an
/// unstarted write looks exactly like a finished one to a sampler. On a loaded
/// machine the write can fail to start inside `_settle`'s 3x10ms stability
/// window, land after the NEXT test's `setUp` has already deleted the keys, and
/// resurrect `pro_lapsed_at` with the PREVIOUS test's `expiresAt` value.
///
/// That is the observed failure verbatim: `Expected: null, Actual:
/// '2026-08-24T01:39:16'` — a `_pastIso()` value, i.e. a prior test's seed.
/// Reproduced 1-in-3 under CPU load, 0-in-9 idle.
///
/// This is the SECOND time this file has flaked this way. The 2026-08-10 fix
/// replaced a fixed 20ms sleep with [_settle]'s quiescence sampler and its
/// docstring records that history — but it hardened the sampler while leaving
/// the one genuinely unawaited write outside its reach.
///
/// ⚠ WHAT THIS DOES AND DOES NOT CLOSE (corrected 2026-08-25 after a Hermes
/// pass called out the overclaim). It closes the setUp-CONTAMINATION window:
/// no prior test's late write can survive into the next test's body. It does
/// NOT remove the unawaited write itself — `subscription_service.dart:458`
/// still reads `unawaited(MigratedKey.write(_proLapsedAtKey, …))`, so a write
/// scheduled on a longer timer could in principle still land mid-test. Closing
/// that for real means exposing an awaitable from the enforcement path, which
/// is a production change this test-side fix deliberately does not make. Say
/// the smaller true thing rather than the larger satisfying one.
///
/// Converging by construction: a late write resurrects a key, the next pass
/// deletes it again, and we only exit once a full pass observes every key null
/// AND that holds for consecutive rounds.
Future<void> _drainAndClearEntitlementKeys() async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  var cleanRounds = 0;

  while (cleanRounds < 3 && DateTime.now().isBefore(deadline)) {
    for (final k in _entitlementKeys) {
      if (MigratedKey.read<dynamic>(k) != null) await MigratedKey.delete(k);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final allNull =
        _entitlementKeys.every((k) => MigratedKey.read<dynamic>(k) == null);
    cleanRounds = allNull ? cleanRounds + 1 : 0;
  }

  // Fail LOUDLY rather than letting a later assertion blame the production
  // code for leftover test state — the exact misattribution that cost an hour
  // of investigation on 2026-08-25.
  final leftovers = _entitlementKeys
      .where((k) => MigratedKey.read<dynamic>(k) != null)
      .toList();
  if (leftovers.isNotEmpty) {
    throw StateError(
      'entitlement keys survived the drain: $leftovers — a fire-and-forget '
      'write is outrunning a 5s converging clear. Do NOT paper over this by '
      'raising the deadline; find the new unawaited writer.',
    );
  }
}

void main() {
  late Directory tempDir;
  const user = 'cccc3333-cccc-cccc-cccc-cccccccccccc';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cqrs_entitlement_');
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
    SubscriptionService.onStateChanged = null;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    SubscriptionService.onStateChanged = null;
    await HiveUserSession.closeAll();
    await HiveService.instance.configBox.clear();
    await HiveUserSession.openForUser(user);
    // Clearing configBox is NOT enough: the entitlement keys are USER-SCOPED
    // (they live in the per-user userBox — that scoping is itself the fix for
    // the 2026-06-06 cross-account banner leak). Re-opening the same user id
    // therefore re-attaches the previous test's `pro_lapsed_at`, which made a
    // "no lapse happened" assertion fail against perfectly correct code.
    await _drainAndClearEntitlementKeys();
  });

  // ignore: deprecated_member_use
  SubscriptionService sub() => SubscriptionService.instance;

  Future<void> seedExpiredPro() async {
    await MigratedKey.write('isPro', true);
    await MigratedKey.write('expiresAt', _pastIso());
  }

  Future<void> seedActivePro() async {
    await MigratedKey.write('isPro', true);
    await MigratedKey.write('expiresAt', _futureIso());
  }

  group('A — proStateSnapshot() is PURE (the fix)', () {
    test('an expired row: reports free, fires NO state-changed hook, and '
        'leaves every Hive key untouched', () async {
      await seedExpiredPro();
      final expiresBefore = MigratedKey.read<dynamic>('expiresAt');

      var fires = 0;
      SubscriptionService.onStateChanged = () => fires++;

      expect(sub().proStateSnapshot(), isFalse,
          reason: 'expired → reports not-PRO');
      await _settle();

      // THE assertion. onStateChanged is exactly what app.dart:47 wires to
      // ref.invalidate(subscriptionInfoProvider); a read that never fires it
      // cannot make a provider build invalidate itself.
      expect(fires, 0,
          reason: 'a PURE read must not fire the invalidation hook. '
              'Pre-fix this was 1, because build() called isPro().');

      expect(MigratedKey.read<dynamic>('isPro'), isTrue,
          reason: 'the pure read must not flip the stored flag');
      expect(MigratedKey.read<dynamic>('expiresAt'), expiresBefore,
          reason: 'the pure read must not wipe expiresAt');
      expect(MigratedKey.read<dynamic>('pro_lapsed_at'), isNull,
          reason: 'the pure read must not stamp the lapsed marker');
    });

    test('an active row: reports PRO and still writes nothing', () async {
      await seedActivePro();
      var fires = 0;
      SubscriptionService.onStateChanged = () => fires++;

      expect(sub().proStateSnapshot(), isTrue);
      await _settle();

      expect(fires, 0);
      expect(MigratedKey.read<dynamic>('isPro'), isTrue);
    });

    test('repeated pure reads are stable — the answer never changes under '
        'you', () async {
      await seedExpiredPro();
      final first = sub().proStateSnapshot();
      final second = sub().proStateSnapshot();
      final third = sub().proStateSnapshot();
      expect([first, second, third], everyElement(isFalse),
          reason: 'a pure read is idempotent; the pre-split isPro() mutated on '
              'the first call so a second call answered a DIFFERENT question');
    });
  });

  group('B — isPro() decision path is UNCHANGED (must pass pre- and post-fix)',
      () {
    test('genuine expiry still downgrades and still stamps pro_lapsed_at',
        () async {
      await seedExpiredPro();

      expect(sub().isPro(), isFalse);
      await _settle();

      expect(MigratedKey.read<dynamic>('isPro'), isFalse,
          reason: 'the decision path must still wipe the flag');
      expect(MigratedKey.read<dynamic>('expiresAt'), isNull,
          reason: 'the decision path must still wipe expiresAt');
      expect(sub().proLapsedAt, isNotNull,
          reason: 'the Home expiry banner depends on this marker — the split '
              'must not have dropped the stamp');
    });

    test('an active subscription is still reported PRO', () async {
      await seedActivePro();
      expect(sub().isPro(), isTrue);
    });

    test('isPro() DOES fire the state-changed hook when it downgrades — the '
        'behaviour the pure read deliberately lacks', () async {
      await seedExpiredPro();
      var fires = 0;
      SubscriptionService.onStateChanged = () => fires++;

      expect(sub().isPro(), isFalse);
      await _settle();

      expect(fires, greaterThanOrEqualTo(1),
          reason: 'the DECISION path still invalidates consumers, which is '
              'correct — it just must not be reached from a build method');
    });
  });

  group('C — evaluateEntitlement() is the explicit enforcement entry point',
      () {
    test('it downgrades an expired row without anyone asking "am I PRO?"',
        () async {
      await seedExpiredPro();

      // This is what splash_screen and _onUserChanged now call. Pre-split
      // there was no way to enforce WITHOUT also asking the question.
      sub().evaluateEntitlement();
      await _settle();

      expect(MigratedKey.read<dynamic>('isPro'), isFalse);
      expect(sub().proLapsedAt, isNotNull);
    });

    test('it is a no-op on a healthy active row', () async {
      await seedActivePro();
      final before = MigratedKey.read<dynamic>('expiresAt');

      sub().evaluateEntitlement();
      await _settle();

      expect(MigratedKey.read<dynamic>('isPro'), isTrue);
      expect(MigratedKey.read<dynamic>('expiresAt'), before);
      expect(sub().proLapsedAt, isNull,
          reason: 'no lapse happened, so no marker');
    });
  });

  group('D — §4.6 kill-switch restores the pre-split path', () {
    test('with disable_cqrs_pure_pro_read set, isPro() still downgrades '
        '(observably identical to the new path)', () async {
      await HiveService.instance.configBox
          .put('disable_cqrs_pure_pro_read', true);
      addTearDown(() async {
        await HiveService.instance.configBox
            .delete('disable_cqrs_pure_pro_read');
      });

      await seedExpiredPro();
      expect(sub().isPro(), isFalse);
      await _settle();

      expect(MigratedKey.read<dynamic>('isPro'), isFalse);
      expect(sub().proLapsedAt, isNotNull);
    });

    test('with the switch closed, evaluateEntitlement() STILL enforces — '
        'closing the switch must never produce less coverage than either path',
        () async {
      // Round-1 P1-4. The first implementation made evaluateEntitlement() a
      // no-op when the switch was closed, on the theory that the legacy inline
      // path would cover it. That was wrong and produced a state weaker than
      // BOTH: the pure-read callsites are not behind the flag, so build methods
      // stayed pure (losing the pre-split incidental guard) while the explicit
      // boot/account-swap enforcement also went dead. A cross-account Auto-
      // Backup restore would then be caught by nothing until a gated tap.
      await HiveService.instance.configBox
          .put('disable_cqrs_pure_pro_read', true);
      addTearDown(() async {
        await HiveService.instance.configBox
            .delete('disable_cqrs_pure_pro_read');
      });

      await seedExpiredPro();
      sub().evaluateEntitlement();
      await _settle();

      expect(MigratedKey.read<dynamic>('isPro'), isFalse,
          reason: 'enforcement must run in BOTH switch positions — there is no '
              'configuration in which enforcing here is worse');
    });

    test('evaluateEntitlementAtBoot() opens the session itself, so boot '
        'enforcement is NOT a no-op on cold start', () async {
      // Round-2 P0. The first version called the SYNCHRONOUS
      // evaluateEntitlement() straight from splash_screen. At cold start no
      // openForUser has run, so currentOwnerFullId is null and it returned
      // immediately — the unit claimed boot coverage it did not have, while
      // having already made the build-method readers pure. Every sibling
      // initializer fired from that splash point awaits
      // ensureOpenedForCurrentSession() first; this one must too.
      // HARNESS LIMIT, stated plainly: the cold-start condition itself is NOT
      // reachable from a unit test. `ensureOpenedForCurrentSession()` reads
      // `SupabaseService.instance.currentUser`, which is null when Supabase was
      // never initialised, so closing the session here and calling the boot
      // path would just re-assert "no session" — it would pass against the
      // BROKEN version too, and a test that cannot fail is not a test.
      //
      // So this splits into (a) a behavioural half proving the boot entry point
      // really performs the enforcement, and (b) a structural half proving the
      // session preamble is present and ordered first — which is the exact bit
      // whose absence caused the P0.
      await seedExpiredPro();

      await sub().evaluateEntitlementAtBoot();
      await _settle();

      expect(MigratedKey.read<dynamic>('isPro'), isFalse,
          reason: '(a) the boot entry point must actually enforce, not merely '
              'exist');

      // (b) The preamble, and its ORDER. Presence-only by construction
      // (feedback_source_grep_false_confidence) — but the defect it guards is
      // itself structural: the first version simply had no preamble.
      final svc = File('lib/core/services/subscription_service.dart')
          .readAsStringSync();
      final start = svc.indexOf('Future<void> evaluateEntitlementAtBoot()');
      expect(start, greaterThan(-1),
          reason: 'splash must call a boot variant that opens the session');
      final body = svc.substring(start, start + 600);
      final openAt = body.indexOf('ensureOpenedForCurrentSession');
      final guardAt = body.indexOf('evaluateEntitlement()');
      expect(openAt, greaterThan(-1),
          reason: 'boot enforcement without ensureOpenedForCurrentSession() is '
              'a NO-OP at cold start — no openForUser has run yet. Every '
              'sibling initializer fired from that splash point awaits it '
              '(refreshFromSupabase:778, rank_service.dart:83).');
      expect(openAt, lessThan(guardAt),
          reason: 'the session must be opened BEFORE the guard runs');
    });

    test('the boot path stamps pro_lapsed_at, so the Home expiry banner can '
        'surface', () async {
      // Round-2 P1. pro_lapsed_at has only TWO writers, both on the
      // enforcement path; _downgradeLocally (which refreshFromSupabase calls)
      // does NOT stamp it. Pre-split the banner provider's own isPro() call
      // stamped it. With the build methods now pure, this boot call is what
      // keeps the red "your PRO expired" banner reachable — and splash awaits
      // it BEFORE refreshFromSupabase so a server-side wipe cannot land first
      // and short-circuit the local-expiry branch.
      await seedExpiredPro();

      await sub().evaluateEntitlementAtBoot();
      await _settle();

      expect(sub().proLapsedAt, isNotNull,
          reason: 'the lapsed marker survives the expiresAt wipe and is the '
              'only thing the Home banner can key off');

      // And the ORDER at the callsite: splash must await this BEFORE firing
      // refreshFromSupabase, whose _downgradeLocally does NOT stamp the marker.
      // If the server refresh wiped isPro first, the local-expiry branch would
      // short-circuit on its own first line and the banner would never surface.
      final splash = File('lib/features/auth/screens/splash_screen.dart')
          .readAsStringSync();
      final bootAt = splash.indexOf('evaluateEntitlementAtBoot()');
      final refreshAt = splash.indexOf('refreshFromSupabase()');
      expect(bootAt, greaterThan(-1));
      expect(refreshAt, greaterThan(-1));
      expect(bootAt, lessThan(refreshAt),
          reason: 'boot enforcement must precede the server refresh');
      expect(splash.substring(bootAt - 60, bootAt).contains('await'), isTrue,
          reason: 'it must be AWAITED — leaving both unawaited makes the order '
              'a microtask race rather than a guarantee');
    });

    test('evaluateEntitlement() stands down when NO session is open — it must '
        'not write through to the shared configBox', () async {
      // Round-1 P3-8. _onUserChanged also fires on sign-out and account
      // deletion, AFTER the per-user boxes close. MigratedKey then falls back
      // to the SHARED configBox — the box whose cross-account leakage was a P0
      // on 2026-06-06. With no owner there is no entitlement to evaluate.
      await seedExpiredPro();
      await HiveUserSession.closeAll();

      sub().evaluateEntitlement();
      await _settle();

      expect(HiveService.instance.configBox.get('pro_lapsed_at'), isNull,
          reason: 'no session → no enforcement → nothing lands in the shared '
              'configBox');
    });
  });

  group('F — gateAndVerify dispatches EXACTLY ONE callback', () {
    test('a throwing onFree must NOT cause onPro to run', () async {
      // B-pass finding — a defect in the ORIGINAL 7b3eaf code. The callbacks
      // used to sit inside the `.then()` guarded by `.catchError`, so a paywall
      // sheet that threw made onFree() fail, land in catchError, and call
      // onPro() — silently GRANTING a PRO feature to a free user.
      //
      // Driven on the LOCAL-free path (no session/server needed): isPro() is
      // false, so gateAndVerify takes the not_pro_local exit and calls onFree.
      await MigratedKey.write('isPro', false);

      var proRan = 0;
      var freeRan = 0;
      await sub().gateAndVerify(
        'some_feature',
        onPro: () => proRan++,
        onFree: () {
          freeRan++;
          throw StateError('paywall blew up');
        },
      );
      await _settle();

      expect(freeRan, 1, reason: 'the free branch is the correct exit here');
      expect(proRan, 0,
          reason: 'a throwing onFree must never escalate into a PRO grant');
    });

    test('a throwing callback does not propagate out of gateAndVerify',
        () async {
      await MigratedKey.write('isPro', false);
      // Must not throw: _runCallback reports and swallows, because 6 of the 10
      // real callsites are synchronous closures that cannot await this Future.
      await expectLater(
        sub().gateAndVerify(
          'some_feature',
          onPro: () {},
          onFree: () => throw StateError('boom'),
        ),
        completes,
      );
    });
  });

  group('E — the pill\'s data source reads purely', () {
    test('SubscriptionInfoNotifier.build uses proStateSnapshot, not isPro',
        () {
      // Presence-only by construction (feedback_source_grep_false_confidence):
      // groups A–D above carry the behavioural weight. This pins the specific
      // callsite that caused the self-invalidation so a future edit that
      // reverts it fails loudly rather than silently reintroducing the loop.
      final src =
          File('lib/features/profile/providers/profile_provider.dart')
              .readAsStringSync();
      final start = src.indexOf('class SubscriptionInfoNotifier');
      expect(start, greaterThan(-1));
      final slice = src.substring(start, (start + 2500).clamp(0, src.length));
      final stripped = slice
          .replaceAll(RegExp(r'//.*'), '')
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');

      expect(stripped.contains('proStateSnapshot()'), isTrue,
          reason: 'the provider build must use the PURE read');
      expect(stripped.contains('.isPro()'), isFalse,
          reason: 'isPro() enforces (and can downgrade + invalidate); calling '
              'it from build() is the self-invalidation this unit fixed');
    });
  });
}
