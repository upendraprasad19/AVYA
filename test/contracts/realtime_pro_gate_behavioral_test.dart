// test/contracts/realtime_pro_gate_behavioral_test.dart
//
// closes-diagnose: e4a7c9  ·  SoT concept: sync_realtime_subscription
//
// BEHAVIORAL, not source-grep. A source-grep test cannot catch this class: the
// string `isPro` already appeared at the OTHER call site before the fix, so
// "the file mentions an entitlement check" was true of the broken code too.
// That is the exact false-confidence shape feedback_source_grep_false_confidence
// warns about, and it is why these cases drive the real methods.
//
// WHY THIS RUNS WITHOUT SUPABASE. `subscribeToRealtimeSync` evaluates the
// entitlement gate BEFORE reading `currentUser`, because entitlement is a purely
// local Hive decision — so the gate branch is reachable in-process. The
// observable is the `realtime_subscribe_skipped_free_tier` event, NOT a throw:
// `SupabaseService.currentUser` returns null rather than throwing when
// uninitialised (supabase_service.dart:80), so the method returns early either
// way and "did it throw" cannot distinguish the two paths. The gate is the only
// emitter of that event and emits whenever it stops a caller, which makes its
// presence a clean read on whether entitlement blocked.
//
// SCOPE LIMIT, stated rather than implied: these cases pin the DECISION and the
// teardown WIRING. They do not exercise the WebSocket, the WAL poll, or the
// stream handler — no unit test can, and a green run here is not evidence those
// work.
//
// MUTATION PROOF — MEASURED 2026-08-15 by applying each mutation, running, and
// reverting. These are counts, not predictions; my predictions were wrong on
// two of the four, which is the reason the rule says measure.
//   1. neuter the entitlement gate (`if (false)`)          → 2 red
//   2. delete `onDowngrade?.call()` in _downgradeLocally    → 1 red
//   3. drop the `_realtimeSkipLogged` latch                 → 1 red
//   4. `proStateSnapshot()` → `isPro()`                     → 1 red
//   5. restore the B-pass P0 (latch reset back inside
//      `unsubscribeRealtime`)                               → 1 red (1 vs 5)
//   6. delete the swap reset from `_onUserChanged`          → 3 red
// Every guard in this fix has a test that fails without it. Mutation 4 matters
// most: it is the one a well-meaning future edit is likeliest to make, and it
// reddens only because of the last group in this file.
//
// Mutations 5 and 6 were added AFTER the B-pass found a P0 that the first four
// missed entirely — see the pause/resume case below. Note 6 reddens 3, not 1:
// `_realtimeSkipLogged` lives on the SyncService SINGLETON and survives between
// tests in this file, and `tearDownHiveForTests` → `closeAll()` →
// `notifyUserChanged()` → `_onUserChanged` is what clears it. So that reset
// doubles as this file's test isolation. Stated because it means mutation 6's
// count is partly isolation collapse rather than purely the semantic under
// test — the account-swap case still reddens on its own terms, but the number
// would be misleading without this note.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/singleton_lifecycle_registry.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;
  final logged = <String>[];

  setUp(() async {
    tempDir = await setUpHiveForTests();
    // migrationBox is NOT opened by the shared helper, and MigratedKey — which
    // every entitlement read funnels through — needs it.
    if (!Hive.isBoxOpen(HiveService.migrationBoxName)) {
      await Hive.openBox(HiveService.migrationBoxName);
    }
    // Without this seam `wrapUserScopedBox` reaches for `Supabase.instance` to
    // resolve the auth uid and asserts (uninitialised in a pure VM test), so
    // every MigratedKey read would throw and silently degrade to the default —
    // making a PRO fixture indistinguishable from a free one and the whole
    // suite green for the wrong reason. Matches the owner the shared helper
    // opened, so Layer A agrees.
    debugAuthUidResolverForTests = () => kTestUserId;
    logged.clear();
    ErrorTelemetry.debugOnLogEventForTests = (op, {message}) => logged.add(op);
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    SubscriptionService.onDowngrade = null;
    debugAuthUidResolverForTests = null; // never leak the seam across tests
    await tearDownHiveForTests(tempDir);
  });

  /// Puts the local entitlement state a PRO user would have.
  ///
  /// Key names are NOT free choices — they mirror SubscriptionService's private
  /// `_isProKey` / `_expiresAtKey` ('isPro' / 'expiresAt'). Writing a
  /// plausible-but-wrong key ('proExpiresAt') makes `proStateSnapshot()` return
  /// false, so a "PRO" fixture silently behaves as free and the PRO cases pass
  /// for the wrong reason. If these constants are ever renamed, these tests
  /// must be updated with them.
  Future<void> makePro({Duration validFor = const Duration(days: 30)}) async {
    final box = HiveService.instance.userBox;
    await box.put('isPro', true);
    await box.put('expiresAt', DateTime.now().add(validFor).toIso8601String());
  }

  /// The gate is the ONLY emitter of this event, and it emits whenever it
  /// stops a caller. So its presence/absence is a clean read on whether the
  /// gate blocked — which beats asserting on a throw, since `currentUser`
  /// returns null rather than throwing on uninitialised Supabase and the
  /// method would return early either way.
  bool gateBlocked() =>
      logged.contains('realtime_subscribe_skipped_free_tier');

  group('e4a7c9 — the gate stops a free user before any network work', () {
    test('THE BUG: a free user does not attach the realtime stream', () async {
      // No isPro key at all == free tier.
      // Pre-fix this fell straight through to refreshSession() and
      // .from('weight_logs').stream(), which is why every user on every
      // foreground attached a WAL poller. Post-fix it returns at the gate,
      // so it completes rather than throwing on uninitialised Supabase.
      await SyncService.instance.subscribeToRealtimeSync();

      expect(gateBlocked(), isTrue,
          reason: 'a free user must be turned away at the gate; the event is '
              'also what makes the gate observable in production');
    });

    test('the skip is logged ONCE across repeated subscribe attempts',
        () async {
      // didChangeAppLifecycleState fires on every foreground. A bare logEvent
      // here would turn a cost fix into a telemetry flood (bug-class 2.13).
      await SyncService.instance.subscribeToRealtimeSync();
      await SyncService.instance.subscribeToRealtimeSync();
      await SyncService.instance.subscribeToRealtimeSync();

      expect(
        logged.where((e) => e == 'realtime_subscribe_skipped_free_tier').length,
        1,
        reason: 'three attempts, one event — the latch must hold',
      );
    });

    test('THE B-PASS P0: a pause/resume CYCLE does not re-fire the skip event',
        () async {
      // The case above passes even with a broken latch, because it never
      // models a pause. Production always does: day_rollover_service calls
      // unsubscribeRealtime() on EVERY AppLifecycleState.paused. The first
      // version of this fix reset the latch inside unsubscribeRealtime, so a
      // free user re-fired an Edge Function call + a client_errors row on
      // every single foreground — reintroducing, through the anti-flood
      // mechanism itself, the per-foreground load this whole fix exists to
      // remove. Measured at 5 events for 5 cycles before the fix.
      //
      // This is the mirror the original suite lacked, and it is why the rule
      // says a diff's own tests are not evidence: they were written from the
      // same mental model as the code and modelled the same half.
      for (var i = 0; i < 5; i++) {
        await SyncService.instance.subscribeToRealtimeSync(); // resumed
        SyncService.instance.unsubscribeRealtime(); // paused
      }

      expect(
        logged.where((e) => e == 'realtime_subscribe_skipped_free_tier').length,
        1,
        reason: 'five background/foreground cycles, ONE event — if this is 5, '
            'the latch is being re-armed by the routine teardown path',
      );
    });

    test('an account swap DOES re-arm the latch (the mirror of the P0 fix)',
        () async {
      // The counter-case to the one above: the latch must still clear when the
      // USER changes, or free user A's latch silently suppresses free user B's
      // first skip event. Fixing the flood by simply deleting the reset would
      // pass the test above and break this one.
      await SyncService.instance.subscribeToRealtimeSync();
      expect(logged.where((e) => e.startsWith('realtime_subscribe')).length, 1);

      SingletonLifecycleRegistry.notifyUserChanged();
      await SyncService.instance.subscribeToRealtimeSync();

      expect(
        logged.where((e) => e == 'realtime_subscribe_skipped_free_tier').length,
        2,
        reason: 'a new user must get its own skip event, not inherit the '
            "previous user's latch",
      );
    });

    test('a PRO user is NOT stopped by the gate', () async {
      await makePro();

      await SyncService.instance.subscribeToRealtimeSync();

      // It then stops at the `currentUser == null` guard, which is correct and
      // unrelated — what this pins is that ENTITLEMENT did not stop it. This
      // is the mirror of case 1: without it, a gate that refuses everyone
      // (including paying users) would still pass case 1.
      expect(gateBlocked(), isFalse,
          reason: 'a PRO user must pass the entitlement gate; if this is true '
              'the gate is refusing the very users it exists to serve');
    });

    test('kill-switch ON restores verbatim pre-fix behaviour', () async {
      // §4.6 — the old path must stay reachable, and "reachable" has to mean
      // a free user is no longer turned away.
      await HiveService.instance.configBox
          .put('disable_realtime_pro_gate', true);

      await SyncService.instance.subscribeToRealtimeSync();

      expect(gateBlocked(), isFalse,
          reason: 'with the switch closed the gate must not fire at all — '
              'that IS the pre-fix behaviour being restored');
    });
  });

  group('e4a7c9 — the teardown half (an attached channel never re-enters '
      'the gate)', () {
    test('THE SECOND BUG: a downgrade fires onDowngrade', () async {
      // subscribeToRealtimeSync's first line is an `_realtimeSubscription !=
      // null` early return, so gating the subscribe cannot help a channel that
      // is ALREADY attached. Without this hook a lapsed PRO user keeps a live
      // PRO channel until app background. Driven through the real isPro()
      // expiry path, not by calling the private _downgradeLocally directly.
      var tornDown = false;
      SubscriptionService.onDowngrade = () => tornDown = true;

      await makePro(validFor: const Duration(days: -1)); // already expired

      SubscriptionService.instance.isPro();
      // isPro() calls _downgradeLocally() UN-AWAITED (subscription_service
      // .dart:461), and the hook fires after five Hive writes inside it. So
      // the queue must drain before asserting — without this the test reads
      // `false` and looks like a missing hook rather than a pending one.
      await pumpEventQueue();

      expect(tornDown, isTrue,
          reason: 'an expiry downgrade must release PRO-owned resources');
    });

    test('a still-valid PRO user does NOT fire the teardown', () async {
      // The mirror: a hook that fires unconditionally would tear down every
      // PRO user's channel on any isPro() call, which is worse than the bug.
      var tornDown = false;
      SubscriptionService.onDowngrade = () => tornDown = true;

      await makePro();

      SubscriptionService.instance.isPro();
      // Drained for the same reason as the case above — and deliberately, so
      // this mirror cannot pass merely because nothing had run yet.
      await pumpEventQueue();

      expect(tornDown, isFalse,
          reason: 'entitlement is intact — nothing should be released');
    });
  });

  group('e4a7c9 — why the gate uses proStateSnapshot() and not isPro()', () {
    test('the gate does not mutate entitlement state', () async {
      // isPro() is the DECISION path: it can reach _downgradeLocally and write
      // five Hive keys plus fire onStateChanged → ref.invalidate. Deciding
      // whether to open a socket must not do that (OI-44 Unit 6 / a9c4e1).
      // A gate built on isPro() would fire the downgrade hook from inside a
      // subscribe attempt — which is exactly the self-invalidation loop that
      // rule exists to prevent.
      var tornDown = false;
      SubscriptionService.onDowngrade = () => tornDown = true;

      await makePro(validFor: const Duration(days: -1)); // expired

      // Gate only. If this were isPro(), the expiry enforcement would fire.
      await SyncService.instance.subscribeToRealtimeSync();

      expect(tornDown, isFalse,
          reason: 'the subscribe gate must be a PURE read — swapping it to '
              'isPro() makes this go true, which is the mutation this pins');
    });
  });
}
