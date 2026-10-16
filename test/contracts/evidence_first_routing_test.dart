// test/contracts/evidence_first_routing_test.dart
//
// Contract — closes-diagnose e5b2a9 (Unit A extension, founder decision
// 2026-10-01: "if the data is on the phone, why wait for the server?").
//
// A device that already holds local evidence of onboarding must go home WITHOUT
// awaiting the cloud routing read. With evidence EVERY branch of
// `RestoringScreen._kickoffRestore` ends in `_goHome`, so the read cannot change
// where the user lands; what it still owes (the self-heal stamp, the c2e9f4
// override signal) is applied when it answers, behind a session-ownership guard.
//
// Behavioral (fakeAsync) for the policy + the late-answer handler; comment-
// stripped source-grep for the wiring (presence only — the behavioral half is the
// helper tests). The MIRRORS matter as much as the fix: no evidence, a throwing
// evidence check and the kill-switches must all keep the old await behaviour.

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/read_screen_source.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

typedef _Dest = PostSignInDestination;

void main() {
  group('resolveBounded — evidence first', () {
    test('evidence + a read that NEVER answers → GoHome with zero time elapsed', () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(
          Completer<_Dest>().future,
          hasLocalEvidence: () async => true,
          evidenceFirst: true,
        ).then((v) => got = v);
        async.flushMicrotasks(); // NO elapse: the 8 s ceiling must not be involved
        expect(got, isA<GoHome>());
      });
    });

    test('the ORIGINAL read is handed to onEvidenceFirst (it is not abandoned)', () {
      fakeAsync((async) {
        final read = Completer<_Dest>().future;
        Future<_Dest>? handed;
        AuthSessionBootstrapper.resolveBounded(
          read,
          hasLocalEvidence: () async => true,
          evidenceFirst: true,
          onEvidenceFirst: (r) => handed = r,
        );
        async.flushMicrotasks();
        expect(identical(handed, read), isTrue);
      });
    });

    test('a read that answers StartMissionBrief later does NOT change the outcome already returned', () {
      fakeAsync((async) {
        _Dest? got;
        final read = Completer<_Dest>();
        AuthSessionBootstrapper.resolveBounded(
          read.future,
          hasLocalEvidence: () async => true,
          evidenceFirst: true,
        ).then((v) => got = v);
        async.flushMicrotasks();
        read.complete(const StartMissionBrief());
        async.flushMicrotasks();
        expect(got, isA<GoHome>());
      });
    });

    test('double-call guard: the evidence check runs exactly ONCE (the old path also calls it once, after the ceiling)', () {
      fakeAsync((async) {
        var calls = 0;
        AuthSessionBootstrapper.resolveBounded(
          Completer<_Dest>().future,
          hasLocalEvidence: () async {
            calls++;
            return true;
          },
          evidenceFirst: true,
        );
        async.elapse(const Duration(seconds: 30));
        expect(calls, 1);
      });
    });

    test('a throwing onEvidenceFirst cannot break the routing result', () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(
          Completer<_Dest>().future,
          hasLocalEvidence: () async => true,
          evidenceFirst: true,
          onEvidenceFirst: (_) => throw StateError('boom'),
        ).then((v) => got = v);
        async.flushMicrotasks();
        expect(got, isA<GoHome>());
      });
    });

    test('MIRROR: NO evidence → still awaits the ORIGINAL read and routes on the late answer (c2e9f4)', () {
      fakeAsync((async) {
        _Dest? got;
        var handed = false;
        final read = Completer<_Dest>();
        AuthSessionBootstrapper.resolveBounded(
          read.future,
          hasLocalEvidence: () async => false,
          evidenceFirst: true,
          onEvidenceFirst: (_) => handed = true,
        ).then((v) => got = v);
        async.elapse(const Duration(seconds: 20)); // well past the 8 s ceiling
        expect(got, isNull, reason: 'fresh device: nothing to fall back to — keep waiting');
        read.complete(const ResumeOnboarding('goal'));
        async.flushMicrotasks();
        expect(got, isA<ResumeOnboarding>());
        expect(handed, isFalse, reason: 'no evidence → no background hand-off');
      });
    });

    test('MIRROR: a throwing evidence check is read as NO evidence, never as GoHome', () {
      fakeAsync((async) {
        _Dest? got;
        final read = Completer<_Dest>();
        AuthSessionBootstrapper.resolveBounded(
          read.future,
          hasLocalEvidence: () async => throw StateError('hive'),
          evidenceFirst: true,
        ).then((v) => got = v);
        async.elapse(const Duration(seconds: 20));
        expect(got, isNull);
        read.complete(const StartMissionBrief());
        async.flushMicrotasks();
        expect(got, isA<StartMissionBrief>(),
            reason: 'a real answer is routed; an evidence failure must not invent GoHome');
      });
    });

    test('MIRROR (kill-switch disable_evidence_first_routing): evidence present but evidenceFirst=false → the old path', () {
      fakeAsync((async) {
        _Dest? got;
        var evidenceCalls = 0;
        AuthSessionBootstrapper.resolveBounded(
          Completer<_Dest>().future,
          hasLocalEvidence: () async {
            evidenceCalls++;
            return true;
          },
        ).then((v) => got = v);
        async.elapse(const Duration(seconds: 7));
        expect(got, isNull, reason: 'the old path waits for the read until the ceiling');
        expect(evidenceCalls, 0, reason: 'evidence is consulted only after the ceiling');
        async.elapse(const Duration(seconds: 2));
        expect(got, isA<DestinationUnknown>());
        expect((got! as DestinationUnknown).reason,
            AuthSessionBootstrapper.kDestinationTimeoutReason);
      });
    });

    test('MIRROR (kill-switch disable_resolve_destination_timeout): disabled turns evidence-first off too', () {
      fakeAsync((async) {
        _Dest? got;
        var evidenceCalls = 0;
        final read = Completer<_Dest>();
        AuthSessionBootstrapper.resolveBounded(
          read.future,
          hasLocalEvidence: () async {
            evidenceCalls++;
            return true;
          },
          disabled: true,
          evidenceFirst: true,
        ).then((v) => got = v);
        async.elapse(const Duration(minutes: 5));
        expect(got, isNull, reason: 'the unbounded await is restored whole');
        expect(evidenceCalls, 0);
        read.complete(const GoHome());
        async.flushMicrotasks();
        expect(got, isA<GoHome>());
      });
    });

    test('a read that answers promptly with evidence present still returns GoHome (never later than the read)', () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(
          Future<_Dest>.value(const ResumeOnboarding('plan')),
          hasLocalEvidence: () async => true,
          evidenceFirst: true,
        ).then((v) => got = v);
        async.flushMicrotasks();
        expect(got, isA<GoHome>(),
            reason: 'with evidence every screen branch goes home — the answer cannot reroute');
      });
    });
    test('a read that REJECTS while the evidence check is still running is observed at once (no uncaught error)', () {
      fakeAsync((async) {
        final uncaught = <Object>[];
        _Dest? got;
        runZonedGuarded(() {
          final read = Future<_Dest>.delayed(
              const Duration(milliseconds: 10), () => throw StateError('read failed'));
          AuthSessionBootstrapper.resolveBounded(
            read,
            hasLocalEvidence: () async {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              return true;
            },
            evidenceFirst: true,
          ).then((v) => got = v);
        }, (e, st) => uncaught.add(e));
        async.elapse(const Duration(seconds: 1));
        expect(got, isA<GoHome>());
        expect(uncaught, isEmpty,
            reason: 'nothing listens to the read until the evidence check returns');
      });
    });
  });

  group('applyLateAnswer — what the answer still owes once the user is home', () {
    late int stamps;
    late int overrides;
    late bool mine;
    late bool stampable;

    setUp(() {
      stamps = 0;
      overrides = 0;
      mine = true;
      stampable = true;
    });

    Future<void> run(_Dest d) => AuthSessionBootstrapper.applyLateAnswer(
          d,
          sessionStillMine: () => mine,
          shouldStamp: () => stampable,
          stamp: () async => stamps++,
          logOverride: () => overrides++,
        );

    test('ResumeOnboarding + all 9 fields → the self-heal stamp runs once', () async {
      await run(const ResumeOnboarding('plan'));
      expect(stamps, 1);
      expect(overrides, 0);
    });

    test('MIRROR: ResumeOnboarding on a field-incomplete profile (OI-46) → no doomed stamp', () async {
      stampable = false;
      await run(const ResumeOnboarding('plan'));
      expect(stamps, 0);
    });

    test('StartMissionBrief with evidence → ONLY the c2e9f4 override signal (no stamp, no routing)', () async {
      await run(const StartMissionBrief());
      expect(overrides, 1);
      expect(stamps, 0);
    });

    test('GoHome / DestinationUnknown owe nothing', () async {
      await run(const GoHome());
      await run(const DestinationUnknown('read_failed: x'));
      expect(stamps, 0);
      expect(overrides, 0);
    });

    test('CROSS-ACCOUNT: a late answer for a session that is no longer ours writes NOTHING', () async {
      mine = false;
      await run(const ResumeOnboarding('plan'));
      await run(const StartMissionBrief());
      expect(stamps, 0, reason: 'the stamp would land in the NEXT user\'s profile');
      expect(overrides, 0);
    });

    test('sessionOwnedBy needs the Supabase session AND the open Hive owner to name the user', () {
      const me = 'aaaaaaaa-1111';
      const other = 'bbbbbbbb-2222';
      bool owned(String? s, String? h) => AuthSessionBootstrapper.sessionOwnedBy(me,
          supabaseUid: s, hiveOwner: h);
      expect(owned(me, me), isTrue);
      expect(owned(other, me), isFalse, reason: 'signed in as someone else');
      expect(owned(me, other), isFalse, reason: 'the open boxes belong to someone else');
      expect(owned(null, me), isFalse, reason: 'signed out');
      expect(owned(me, null), isFalse, reason: 'no boxes open');
    });
    test('applyLateAnswer WAITS for the stamp, so a Hive write failure reaches the caller (and its error sink)', () async {
      final gate = Completer<void>();
      var done = false;
      final f = AuthSessionBootstrapper.applyLateAnswer(
        const ResumeOnboarding('plan'),
        sessionStillMine: () => true,
        shouldStamp: () => true,
        stamp: () => gate.future,
        logOverride: () {},
      ).then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse, reason: 'must still be waiting on the stamp');
      gate.complete();
      await f;
      expect(done, isTrue);
      await expectLater(
        AuthSessionBootstrapper.applyLateAnswer(
          const ResumeOnboarding('plan'),
          sessionStillMine: () => true,
          shouldStamp: () => true,
          stamp: () async => throw StateError('hive write failed'),
          logOverride: () {},
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('liveSessionOwnedBy compares BOTH live readers against the CAPTURED user, not against each other', () {
      const me = 'aaaaaaaa-1111';
      const other = 'bbbbbbbb-2222';
      bool live(String? s, String? h) => AuthSessionBootstrapper.liveSessionOwnedBy(me,
          supabaseUid: () => s, hiveOwner: () => h);
      expect(live(me, me), isTrue);
      expect(live(other, me), isFalse, reason: 'A signed out, B signed in, boxes not yet swapped');
      expect(live(other, other), isFalse,
          reason: 'B is fully in: A late answer is none of B business');
      expect(live(me, other), isFalse);
      expect(live(me, null), isFalse, reason: 'no boxes open');
      expect(live(null, me), isFalse, reason: 'signed out');
    });
  });

  group('settleLateAnswer — the background chain never throws and has no ceiling', () {
    late List<Object> errors;
    late int stamps;
    late int overrides;

    setUp(() {
      errors = <Object>[];
      stamps = 0;
      overrides = 0;
    });

    Future<void> settle(
      Future<_Dest> read, {
      Future<void> Function()? stamp,
      bool Function()? shouldStamp,
      void Function(Object, StackTrace)? onError,
    }) =>
        AuthSessionBootstrapper.settleLateAnswer(
          read,
          sessionStillMine: () => true,
          shouldStamp: shouldStamp ?? () => true,
          stamp: stamp ?? () async => stamps++,
          logOverride: () => overrides++,
          onError: onError ?? (e, st) => errors.add(e),
        );

    test('a REJECTING read lands in onError, never an uncaught error', () async {
      final uncaught = <Object>[];
      await runZonedGuarded(
          () => settle(Future<_Dest>.error(StateError('read failed'))),
          (e, st) => uncaught.add(e));
      expect(errors, hasLength(1));
      expect(uncaught, isEmpty);
      expect(stamps, 0);
    });

    test('a THROWING stamp lands in onError', () async {
      await settle(Future<_Dest>.value(const ResumeOnboarding('plan')),
          stamp: () async => throw StateError('hive write failed'));
      expect(errors, hasLength(1));
    });

    test('a THROWING guard predicate lands in onError', () async {
      await settle(Future<_Dest>.value(const ResumeOnboarding('plan')),
          shouldStamp: () => throw StateError('box closed'));
      expect(errors, hasLength(1));
      expect(stamps, 0);
    });

    test('a throwing onError sink cannot escape either', () async {
      await settle(Future<_Dest>.error(StateError('x')),
          onError: (e, st) => throw StateError('sink'));
    });

    test('a SLOW read (an outage: minutes) is still applied when it lands — no ceiling', () {
      fakeAsync((async) {
        final c = Completer<_Dest>();
        unawaited(settle(c.future));
        async.elapse(const Duration(minutes: 30));
        expect(stamps, 0, reason: 'still waiting');
        c.complete(const ResumeOnboarding('plan'));
        async.flushMicrotasks();
        expect(stamps, 1);
        expect(errors, isEmpty);
      });
    });

    test('MIRROR: the ordinary happy path reports nothing to onError', () async {
      await settle(Future<_Dest>.value(const GoHome()));
      await settle(Future<_Dest>.value(const StartMissionBrief()));
      expect(errors, isEmpty);
      expect(overrides, 1);
    });
  });

  group('evidenceFirstDisabled — the kill-switch is read from configBox (real Hive)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
    });

    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    test('absent → the feature is ON', () {
      expect(AuthSessionBootstrapper.evidenceFirstDisabled, isFalse);
    });

    test('disable_evidence_first_routing == true → OFF', () async {
      await HiveService.instance.configBox.put('disable_evidence_first_routing', true);
      expect(AuthSessionBootstrapper.evidenceFirstDisabled, isTrue);
    });

    test('MIRROR: only the SIBLING timeout switch set → evidence-first stays ON (that switch acts through "disabled", not through this key)', () async {
      await HiveService.instance.configBox
          .put(AuthSessionBootstrapper.kDisableDestinationTimeoutKey, true);
      expect(AuthSessionBootstrapper.evidenceFirstDisabled, isFalse);
    });

    test('MIRROR: an UNREADABLE configBox keeps the feature ON (the defensive read fails open, never closed)', () async {
      await HiveService.instance.configBox.close();
      expect(AuthSessionBootstrapper.evidenceFirstDisabled, isFalse,
          reason: 'a missing switch must never silently turn the feature off');
    });

    test('MIRROR: only a literal true disables (false / the string "true" do not)', () async {
      await HiveService.instance.configBox.put('disable_evidence_first_routing', false);
      expect(AuthSessionBootstrapper.evidenceFirstDisabled, isFalse);
      await HiveService.instance.configBox.put('disable_evidence_first_routing', 'true');
      expect(AuthSessionBootstrapper.evidenceFirstDisabled, isFalse);
    });
  });

  group('stampOnboardingCompletedAt — the ONE writer of the Plan A self-heal stamp (real Hive)', () {
    late Directory tempDir;
    late List<String> pushed;

    setUp(() async {
      tempDir = await setUpHiveForTests();
      pushed = <String>[];
    });

    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    Future<void> stamp({bool Function()? mine}) =>
        AuthSessionBootstrapper.stampOnboardingCompletedAt(
          kTestUserId,
          sessionStillMine: mine ?? () => true,
          push: (uid) async => pushed.add(uid),
        );

    Map<String, dynamic> stored() =>
        Map<String, dynamic>.from(HiveService.instance.userBox.get('profile') as Map);

    test('stamps onboarding_completed_at as the CURRENT UTC instant and keeps every other field', () async {
      await HiveService.instance.userBox.put('profile', <String, dynamic>{
        'primary_goal': 'build_muscle',
        'current_weight_kg': 78.9,
      });
      final before = DateTime.now().toUtc();
      await stamp();
      final p = stored();
      expect(p['primary_goal'], 'build_muscle');
      expect(p['current_weight_kg'], 78.9);
      final parsed = DateTime.parse(p['onboarding_completed_at'] as String);
      expect(parsed.isUtc, isTrue);
      expect(parsed.difference(before).abs(), lessThan(const Duration(seconds: 5)),
          reason: 'a +5:30 or a stale instant would be a silent timezone bug');
    });

    test('the cloud push fires once, for the stamped user, after the write', () async {
      await HiveService.instance.userBox
          .put('profile', <String, dynamic>{'primary_goal': 'build_muscle'});
      await stamp();
      expect(pushed, <String>[kTestUserId]);
    });

    test('MIRROR: with no stored profile it still writes the stamp (a map is created, nothing throws)', () async {
      expect(HiveService.instance.userBox.get('profile'), isNull);
      await stamp();
      expect(stored()['onboarding_completed_at'], isA<String>());
    });

    test('an EXISTING real stamp is KEPT (the true completion time) and is still pushed', () async {
      const real = '2026-01-02T03:04:05.000Z';
      await HiveService.instance.userBox.put('profile', <String, dynamic>{
        'primary_goal': 'build_muscle',
        'onboarding_completed_at': real,
      });
      await stamp();
      expect(stored()['onboarding_completed_at'], real,
          reason: 'overwriting with now() would lie about when onboarding finished');
      expect(pushed, <String>[kTestUserId],
          reason: 'a device that finished onboarding but never got the push must send it');
    });

    test('MIRROR: a blank / non-string stamp is NOT a real stamp — it is replaced', () async {
      for (final junk in <Object?>['', '   ', null, 12345]) {
        await HiveService.instance.userBox.put('profile', <String, dynamic>{
          'primary_goal': 'build_muscle',
          'onboarding_completed_at': junk,
        });
        await stamp();
        final v = stored()['onboarding_completed_at'];
        expect(v, isA<String>(), reason: 'junk=$junk');
        expect((v as String).trim(), isNotEmpty, reason: 'junk=$junk');
        expect(DateTime.parse(v).isUtc, isTrue, reason: 'junk=$junk');
      }
    });

    test('CROSS-ACCOUNT (entry): a session that is no longer ours → nothing written, nothing pushed', () async {
      await HiveService.instance.userBox
          .put('profile', <String, dynamic>{'primary_goal': 'build_muscle'});
      await stamp(mine: () => false);
      expect(stored().containsKey('onboarding_completed_at'), isFalse);
      expect(pushed, isEmpty);
    });

    test('the DEFAULT guard is the LIVE session check: with nobody signed in, a caller that passes no guard writes nothing and pushes nothing', () async {
      await HiveService.instance.userBox
          .put('profile', <String, dynamic>{'primary_goal': 'build_muscle'});
      await AuthSessionBootstrapper.stampOnboardingCompletedAt(
        kTestUserId,
        push: (uid) async => pushed.add(uid),
      );
      expect(stored().containsKey('onboarding_completed_at'), isFalse,
          reason: 'Supabase is not initialised here, so the live uid is null');
      expect(pushed, isEmpty);
    });

    test('CROSS-ACCOUNT (after the write): the session flipped mid-write → written, but NOT pushed under the old user', () async {
      await HiveService.instance.userBox
          .put('profile', <String, dynamic>{'primary_goal': 'build_muscle'});
      var calls = 0;
      await stamp(mine: () => ++calls == 1);
      expect(calls, 2, reason: 'the guard is checked at entry AND again before the push');
      expect(stored()['onboarding_completed_at'], isA<String>());
      expect(pushed, isEmpty,
          reason: 'syncProfileNow pushes the WHOLE current profile under that user id');
    });
  });

  group('wiring (presence — comment-stripped; behavior is covered above)', () {
    final boot = _strip(
        File('lib/core/services/auth_session_bootstrapper.dart').readAsStringSync());
    final screen = _strip(readRestoringScreenSource());

    test('the kill-switch key literal is pinned (a typo would silently disable the switch)', () {
      expect(boot.contains("'disable_evidence_first_routing'"), isTrue);
    });

    test('resolveDestinationBounded turns evidence-first on ONLY via the kill-switch, and hands the read to the settle path', () {
      final body = _between(boot,
          'Future<PostSignInDestination> resolveDestinationBounded(', ');');
      expect(
          RegExp(r'evidenceFirst:\s*!evidenceFirstDisabled,\s*onEvidenceFirst:')
              .hasMatch(body),
          isTrue,
          reason: 'evidenceFirst must be EXACTLY the negated kill-switch');
      expect(RegExp(r'evidenceFirst:[^,]*&&').hasMatch(body), isFalse,
          reason: 'no extra condition may silently narrow the feature');
      expect(body.contains('_settleLateAnswer(userId, read)'), isTrue);
      expect(body.contains('disabled: destinationTimeoutDisabled'), isTrue);
    });

    test('_settleLateAnswer owns the guard feeds, the stamp gate, the override event and the error sink', () {
      final body = _between(
          boot, 'void _settleLateAnswer(', 'static Future<void> settleLateAnswer(');
      expect(body.contains('sessionStillMine: () => _sessionStillMine(userId)'), isTrue);
      expect(body.contains('stamp: () => stampOnboardingCompletedAt(userId)'), isTrue);
      expect(
          RegExp(r"shouldStamp:\s*\(\)\s*=>\s*hasAllRequiredProfileFields\(\s*_hive\.userBox\.get\('profile'\)\s*\)")
              .hasMatch(body),
          isTrue,
          reason: 'the stamp is gated on all 9 migration-112 fields (OI-46), read from the user-scoped box');
      expect(body.contains("'restoring_missionbrief_overridden_by_local_evidence'"), isTrue,
          reason: 'the c2e9f4 anomaly signal keeps its event name');
      expect(body.contains('onError:'), isTrue);
      expect(body.contains('recordNonFatal('), isTrue);
      expect(body.contains("'evidence_first_late_answer_failed'"), isTrue);
    });

    test('settleLateAnswer catches into onError and has NO ceiling', () {
      final body = _between(
          boot, 'static Future<void> settleLateAnswer(', 'bool _sessionStillMine(');
      expect(body.contains('await read'), isTrue);
      expect(body.contains('catch (e, st)'), isTrue);
      expect(body.contains('onError(e, st)'), isTrue);
      expect(body.contains('.timeout('), isFalse,
          reason: 'a ceiling here would drop the answer exactly when the outage makes it slow');
    });

    test('the session guard is fed by the LIVE Supabase uid and the LIVE Hive owner', () {
      expect(
          RegExp(r'bool _sessionStillMine\(String userId\)\s*=>\s*liveSessionOwnedBy\(userId\)')
              .hasMatch(boot),
          isTrue);
      final live = _between(boot, 'static bool liveSessionOwnedBy(', 'static bool sessionOwnedBy(');
      expect(live.contains('(supabaseUid ?? _liveSupabaseUid)()'), isTrue);
      expect(live.contains('(hiveOwner ?? _liveHiveOwner)()'), isTrue);
      expect(live.contains('sessionOwnedBy('), isTrue);
      expect(boot.contains('String? _liveSupabaseUid() => SupabaseService.instance.currentUser?.id'),
          isTrue);
      expect(boot.contains('String? _liveHiveOwner() => HiveUserSession.currentOwnerFullId'),
          isTrue);
    });

    test('applyLateAnswer bails on a foreign session BEFORE touching the answer', () {
      final body = _between(boot, 'static Future<void> applyLateAnswer(',
          'static Future<void> stampOnboardingCompletedAt(');
      final guard = body.indexOf('if (!sessionStillMine()) return;');
      final sw = body.indexOf('switch (answer)');
      expect(guard, greaterThan(-1));
      expect(sw, greaterThan(guard));
      expect(body.contains('await stamp()'), isTrue,
          reason: 'awaited, so a Hive write failure reaches the settle path error sink');
    });

    test('the stamp re-checks the session at entry (before any box access) and again before the push', () {
      final body = _between(boot, 'static Future<void> stampOnboardingCompletedAt(',
          'syncProfileNow)(userId))');
      final guards = RegExp(RegExp.escape('if (!mine()) return;'))
          .allMatches(body)
          .map((m) => m.start)
          .toList();
      expect(guards, hasLength(2));
      expect(guards[0], lessThan(body.indexOf('HiveService.instance.userBox')),
          reason: 'the entry guard must come before the first box access');
      expect(guards[1], greaterThan(body.indexOf(".put('profile'")));
      expect(guards[1], lessThan(body.indexOf('syncProfileNow')));
    });

    test('the terms-consent fallback refreshes the token BEFORE its users read (a stale token answers 200 + zero rows)', () {
      final body =
          _between(boot, 'Future<void> ensureTermsConsentFallback(', ".from('users')");
      expect(body.contains('_supabase.ensureFreshToken()'), isTrue);
      expect(body.contains("'terms_fallback_token_refresh_failed'"), isTrue,
          reason: 'a refresh failure is observable, never silently swallowed');
    });

    test('the screen keeps ONE stamp writer: its helper delegates to the bootstrapper', () {
      expect(
          RegExp(r'_stampOnboardingCompletedAt\(String userId\)\s*=>\s*AuthSessionBootstrapper\.stampOnboardingCompletedAt\(userId\)')
              .hasMatch(screen),
          isTrue);
      expect(screen.contains("merged['onboarding_completed_at']"), isFalse,
          reason: 'a second copy of the stamp body would drift');
    });

    test('the screen still passes its OWN evidence helper (session opened first; disable_local_onboarded_evidence honoured)', () {
      expect(
          RegExp(r'resolveDestinationBounded\(\s*user\.id,\s*_hasLocalOnboardedEvidence\s*\)')
              .hasMatch(screen),
          isTrue);
    });

    test('_hasLocalOnboardedEvidence: kill-switch first, THEN the session open, THEN the predicate', () {
      final body = _between(
          screen, 'Future<bool> _hasLocalOnboardedEvidence()', 'Future<void> _goHome(');
      final sw = body.indexOf("get('disable_local_onboarded_evidence') ==");
      final off = body.indexOf('return false;');
      final open = body.indexOf('await _ensureHiveSessionOpenForEvidence()');
      final pred = body.indexOf('return hasLocalOnboardedEvidence(');
      expect(sw, greaterThan(-1));
      expect(off, greaterThan(sw));
      expect(open, greaterThan(off));
      expect(pred, greaterThan(open),
          reason: 'an owner-null box serves empty: reading before the open means evidence-first never fires');
    });

    test('the evidence helper and the ResumeOnboarding arm read the SAME predicate inputs', () {
      final helper = _between(
          screen, 'Future<bool> _hasLocalOnboardedEvidence()', 'Future<void> _goHome(');
      final kick = _between(
          screen, 'Future<void> _kickoffRestore()', 'Future<void> _ensureHiveSessionOpenForEvidence()');
      final resume = kick.substring(kick.indexOf('case ResumeOnboarding('));
      for (final src in <String>[helper, resume]) {
        expect(src.contains("MigratedKey.readWithDefault<bool>('onboarding_completed', false)"),
            isTrue);
        expect(src.contains("HiveService.instance.userBox.get('profile')"), isTrue);
      }
    });

    test('EVERY arm that finds evidence ends in _goHome BEFORE any onboarding navigation (the premise of skipping the wait)', () {
      final kick = _between(
          screen, 'Future<void> _kickoffRestore()', 'Future<void> _ensureHiveSessionOpenForEvidence()');
      final starts = <String, int>{
        'mission': kick.indexOf('case StartMissionBrief():'),
        'unknown': kick.indexOf('case DestinationUnknown('),
        'resume': kick.indexOf('case ResumeOnboarding('),
        'home': kick.indexOf('case GoHome():'),
      };
      expect(starts.values.every((v) => v > -1), isTrue);
      final order = starts.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
      String arm(String name) {
        final i = order.indexWhere((e) => e.key == name);
        final from = order[i].value;
        final to = i + 1 < order.length ? order[i + 1].value : kick.length;
        return kick.substring(from, to);
      }

      final goHomeThenReturn =
          RegExp(r'_committedToGoHome = true;\s*await _goHome\(user\.id, restoreFuture\);\s*return;');
      for (final name in <String>['mission', 'unknown', 'resume', 'home']) {
        final body = arm(name);
        final m = goHomeThenReturn.firstMatch(body);
        expect(m, isNotNull, reason: '$name arm must go home and return when it has evidence');
        final nav = body.indexOf("context.go('/onboarding");
        if (nav > -1) {
          expect(m!.start, lessThan(nav),
              reason: '$name arm: the evidence branch must come before the onboarding navigation');
        }
      }
      expect(arm('home').contains('context.go('), isFalse,
          reason: 'the GoHome arm never navigates anywhere but home');
    });
  });
}

String _between(String src, String start, String end) {
  final i = src.indexOf(start);
  expect(i, greaterThan(-1), reason: 'marker not found: $start');
  final j = src.indexOf(end, i + start.length);
  expect(j, greaterThan(-1), reason: 'end marker not found after: $start (looking for $end)');
  return src.substring(i, j + end.length);
}
