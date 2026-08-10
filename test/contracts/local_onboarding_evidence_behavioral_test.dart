// closes-diagnose: c2e9f4
//
// Behavioral + contract cover for the local-onboarding-evidence predicate and
// the DestinationUnknown state that make a FAILED cloud read stop meaning
// "brand-new user".
//
// Concept: onboarding_completed_at (SoT registry)
// Writer:  lib/features/auth/screens/restoring_screen.dart — the three
//          not-onboarded branches, all now routed through the shared predicate
// Reader:  lib/core/router/app_router.dart `_authRedirect`
//
// WHY THIS FILE IS BEHAVIORAL, NOT SOURCE-GREP (rule 21 / §4.4)
// The bug this closes is a *decision* bug: the code was present and correct
// to read, it just answered the wrong question when the cloud didn't reply.
// A source-grep proving "the branch calls the predicate" cannot fail when the
// predicate itself is wrong. The truth-table tests below fail on a wrong
// answer, and the Hive round-trip fails when the read path is broken even if
// every line of source text survives intact.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/local_onboarding_evidence.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/features/onboarding/providers/onboarding_provider.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/read_screen_source.dart';

/// A profile map carrying all 9 fields migration 112 gates on.
Map<String, dynamic> _completeProfile() => <String, dynamic>{
      'primary_goal': 'build_muscle',
      'fitness_experience': 'advanced',
      'current_weight_kg': 78.9,
      'date_of_birth': '1988-06-30',
      'gender': 'male',
      'height_cm': 174,
      'target_weight_kg': 80.0,
      'days_per_week': 4,
      'equipment_access': 'basic_gym',
    };

void main() {
  group('hasLocalOnboardedEvidence — truth table', () {
    test('the flag alone is sufficient (profile map absent)', () {
      expect(
        hasLocalOnboardedEvidence(hiveProfile: null, flagOnboarded: true),
        isTrue,
        reason: 'a device that completed onboarding locally has the flag even '
            'if the profile map was never restored',
      );
    });

    test('a complete profile map alone is sufficient (flag never stamped)', () {
      expect(
        hasLocalOnboardedEvidence(
            hiveProfile: _completeProfile(), flagOnboarded: false),
        isTrue,
        reason: 'this is the a3f6d9 cohort — restore populated the profile but '
            'nothing stamped the boolean the router gates on',
      );
    });

    // ── The no-regression case. If this ever goes green-on-true, the fix has
    // started routing genuine new users past onboarding, which is strictly
    // worse than the bug it closes.
    test('GENUINE NEW USER: no profile, no flag → NO evidence', () {
      expect(
        hasLocalOnboardedEvidence(hiveProfile: null, flagOnboarded: false),
        isFalse,
        reason: 'a fresh install must still reach Mission Brief — this fix '
            'must never let a new user skip onboarding',
      );
    });

    test('empty profile map + no flag → no evidence', () {
      expect(
        hasLocalOnboardedEvidence(
            hiveProfile: <String, dynamic>{}, flagOnboarded: false),
        isFalse,
      );
    });

    test('a PARTIAL profile (8 of 9 fields) is not evidence on its own', () {
      for (final omitted in requiredOnboardingProfileFields) {
        final partial = _completeProfile()..remove(omitted);
        expect(
          hasLocalOnboardedEvidence(
              hiveProfile: partial, flagOnboarded: false),
          isFalse,
          reason: 'omitting "$omitted" must drop the map below the migration-'
              '112 bar — otherwise the self-heal stamp would be rejected '
              'server-side (P0001) on every cold start, forever (OI-46)',
        );
      }
    });

    test('a null-valued field counts as missing, not present', () {
      final withNull = _completeProfile()..['gender'] = null;
      expect(
        hasLocalOnboardedEvidence(
            hiveProfile: withNull, flagOnboarded: false),
        isFalse,
      );
    });

    test('a non-Map value never passes (defensive against Hive shape drift)',
        () {
      expect(hasAllRequiredProfileFields('not a map'), isFalse);
      expect(hasAllRequiredProfileFields(42), isFalse);
      expect(hasAllRequiredProfileFields(<String>['a']), isFalse);
    });

    test('the required-field list matches migration 112 exactly (9 columns)',
        () {
      expect(requiredOnboardingProfileFields, hasLength(9));
      expect(
        requiredOnboardingProfileFields.toSet(),
        {
          'primary_goal',
          'fitness_experience',
          'current_weight_kg',
          'date_of_birth',
          'gender',
          'height_cm',
          'target_weight_kg',
          'days_per_week',
          'equipment_access',
        },
        reason: 'drift here silently changes who the self-heal rescues',
      );
    });
  });

  group('real Hive round-trip — the read path the screen actually uses', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
    });

    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    test('a restored profile in userBox is seen as evidence', () async {
      await HiveService.instance.userBox.put('profile', _completeProfile());

      // Exactly the expression RestoringScreen evaluates.
      final evidence = hasLocalOnboardedEvidence(
        hiveProfile: HiveService.instance.userBox.get('profile'),
        flagOnboarded:
            MigratedKey.readWithDefault<bool>('onboarding_completed', false),
      );

      expect(evidence, isTrue,
          reason: 'restore writes the profile map; the flag is NOT stamped by '
              'restore — the map alone must carry the rescue');
    });

    test('a fresh box yields no evidence (pre-fix starting condition)',
        () async {
      expect(HiveService.instance.userBox.get('profile'), isNull);
      final evidence = hasLocalOnboardedEvidence(
        hiveProfile: HiveService.instance.userBox.get('profile'),
        flagOnboarded:
            MigratedKey.readWithDefault<bool>('onboarding_completed', false),
      );
      expect(evidence, isFalse);
    });

    test('the stamped flag survives a round-trip and is seen as evidence',
        () async {
      await MigratedKey.write('onboarding_completed', true);
      final evidence = hasLocalOnboardedEvidence(
        hiveProfile: HiveService.instance.userBox.get('profile'),
        flagOnboarded:
            MigratedKey.readWithDefault<bool>('onboarding_completed', false),
      );
      expect(evidence, isTrue);
    });
  });

  group('classifyDestination — unchanged by c2e9f4', () {
    test('a row with onboarding_completed_at is still GoHome', () {
      expect(
        AuthSessionBootstrapper.classifyDestination({
          'user_id': 'u',
          'onboarding_completed_at': '2026-05-01T15:36:41Z',
        }),
        isA<GoHome>(),
      );
    });

    test('a NULL row is still StartMissionBrief (the positive-fact case)', () {
      expect(
        AuthSessionBootstrapper.classifyDestination(null),
        isA<StartMissionBrief>(),
        reason: 'classifyDestination is pure and only ever sees a real answer; '
            'the "could not read" case is DestinationUnknown, produced by '
            'resolveDestination, never by this function',
      );
    });

    test('DestinationUnknown is a distinct state carrying a reason', () {
      const d = DestinationUnknown('read_failed: 401');
      expect(d, isA<PostSignInDestination>());
      expect(d, isNot(isA<StartMissionBrief>()),
          reason: 'THE fix: an unanswered read must not be assignable to the '
              '"brand-new user" branch');
      expect(d.reason, contains('401'));
    });
  });

  group('resolveDestination — a read that CANNOT succeed', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
    });

    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    // ── THE MUTATION-KILLER FOR THIS BATCH ──────────────────────────────
    // Added after a mutation run scored ZERO: reverting the catch-block to
    // `return const StartMissionBrief()` — i.e. re-creating diagnose c2e9f4
    // exactly — broke no test at all. Every other test here covered the
    // predicate and the branch wiring; none covered the ONE line whose wrong
    // value IS the bug. A guard whose mirror test doesn't exist is not a
    // guard (feedback_mistake_guard_without_its_mirror).
    //
    // Supabase is deliberately NOT initialised in unit tests, so every path
    // through resolveDestination's SELECT throws — the real failure shape,
    // exercised end-to-end through the live method rather than a stub.
    test('returns DestinationUnknown, NEVER StartMissionBrief, when the '
        'profile read cannot complete', () async {
      final destination = await AuthSessionBootstrapper.instance
          .resolveDestination('d7a67a37-0b05-4f0a-b13c-388bff3cb59b');

      expect(destination, isA<DestinationUnknown>(),
          reason: 'an unreachable backend must produce "unknown". Returning '
              'StartMissionBrief here is diagnose c2e9f4 verbatim: it routes '
              'a fully-onboarded account into onboarding, where completing '
              'the flow overwrites a real profile.');
      expect(destination, isNot(isA<StartMissionBrief>()));
    });

    test('the kill-switch restores the pre-fix StartMissionBrief fallback',
        () async {
      await HiveService.instance.configBox
          .put('disable_resolve_destination_unknown', true);
      addTearDown(() => HiveService.instance.configBox
          .delete('disable_resolve_destination_unknown'));

      final destination = await AuthSessionBootstrapper.instance
          .resolveDestination('d7a67a37-0b05-4f0a-b13c-388bff3cb59b');

      expect(destination, isA<StartMissionBrief>(),
          reason: '§4.6 requires the old path be reachable verbatim when the '
              'switch is flipped');
    });
  });

  group('onboarding overwrite guard — must FAIL OPEN', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
    });

    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    // The guard added in this batch refuses `completeOnboarding` when the
    // cloud already holds `onboarding_completed_at`. Its FALSE-POSITIVE
    // direction is far more dangerous than its false-negative one: a
    // misroute costs a returning user one wrong screen, but a guard that
    // wrongly fires blocks every genuine new user from ever finishing
    // signup. Supabase is uninitialised here, so the check cannot complete —
    // exactly the "flaky connection during signup" case — and onboarding
    // must proceed regardless.
    // ── The pure decision, mutation-proven on its own ────────────────────
    // The surrounding `_alreadyOnboardedInCloud` makes a live Supabase call a
    // unit test cannot exercise, so the DECISION is separated from the I/O —
    // the same split as `classifyDestination` and
    // `shouldStampFallbackTermsConsent`.
    test('only a real stamp refuses; null and blank both allow', () {
      expect(
          OnboardingNotifier.shouldRefuseOnboardingOverwrite(
              '2026-05-01T15:36:41Z'),
          isTrue,
          reason: 'a genuine completion timestamp must block the overwrite');
      expect(OnboardingNotifier.shouldRefuseOnboardingOverwrite(null), isFalse,
          reason: 'never onboarded → proceed');
      expect(OnboardingNotifier.shouldRefuseOnboardingOverwrite(''), isFalse,
          reason: 'a blank column must not be read as a completion');
      expect(OnboardingNotifier.shouldRefuseOnboardingOverwrite('   '), isFalse,
          reason: 'whitespace is not a timestamp — fail OPEN');
    });

    // NOTE ON SCOPE, so nobody later mistakes this for more than it is:
    // this exercises the NO-SESSION path (Supabase is uninitialised, so
    // `currentUser` is null and the guard returns before its network call).
    // The catch-block's fail-open on a THROWN error is structural — pinned by
    // the source assertion below rather than behaviourally, because forcing a
    // throw from that call site needs a live initialised Supabase client.
    test('no session available → guard does NOT block onboarding', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(onboardingProvider.notifier);

      notifier.setAnswer('full_name', 'Recruit FailOpen');
      notifier.setAnswer('date_of_birth', '1995-06-15');
      notifier.setAnswer('gender', 'male');
      notifier.setAnswer('height_cm', 175);
      notifier.setAnswer('current_weight_kg', 72);
      notifier.setAnswer('target_weight_kg', 68);
      notifier.setAnswer('primary_goal', 'lose_fat');
      notifier.setAnswer('fitness_experience', 'beginner');
      notifier.setAnswer('days_per_week', 4);
      notifier.setAnswer('equipment_access', 'bodyweight');

      await notifier.completeOnboarding();

      expect(container.read(onboardingProvider).error, isNot('already_onboarded'),
          reason: 'the guard must fail OPEN — an unreachable backend must '
              'never be read as "this user already onboarded", or every new '
              'signup on a flaky connection is permanently blocked');
    });

    test('the guard catch-block returns false (fails OPEN), structurally', () {
      final src = File('lib/features/onboarding/providers/onboarding_provider.dart')
          .readAsStringSync();
      final guardStart = src.indexOf('Future<bool> _alreadyOnboardedInCloud()');
      expect(guardStart, greaterThan(-1));
      final catchIdx =
          src.indexOf('onboarding_overwrite_guard_check_failed', guardStart);
      expect(catchIdx, greaterThan(-1),
          reason: 'the guard must record its failures, not swallow them');
      final afterCatch = src.substring(catchIdx, catchIdx + 220);
      expect(afterCatch.contains('return false;'), isTrue,
          reason: 'FAIL OPEN. Returning true here would block every genuine '
              'new signup whose guard check errored — strictly worse than the '
              'misroute this guard exists to contain.');
    });
  });

  group('wiring — every not-onboarded branch consults local evidence', () {
    late String src;

    setUpAll(() {
      // Reads head + parts, so a future extraction cannot silently narrow
      // what this test inspects.
      src = readRestoringScreenSource();
    });

    test('the StartMissionBrief branch checks evidence before routing away',
        () {
      final branch = src.indexOf('case StartMissionBrief():');
      expect(branch, greaterThan(-1));
      final routeAway = src.indexOf("context.go('/onboarding/mission-brief')");
      final evidenceCheck =
          src.indexOf('_hasLocalOnboardedEvidence()', branch);
      expect(evidenceCheck, greaterThan(-1),
          reason: 'the branch every FAILED read lands on must consult local '
              'evidence — it consulted nothing before c2e9f4');
      expect(evidenceCheck, lessThan(routeAway),
          reason: 'the check must GATE the navigation, not follow it');
    });

    test('the DestinationUnknown branch exists and never routes to onboarding',
        () {
      final branch = src.indexOf('case DestinationUnknown(');
      expect(branch, greaterThan(-1),
          reason: 'the sealed switch must handle the unknown state explicitly');
      final nextCase = src.indexOf('case ', branch + 10);
      final body =
          nextCase == -1 ? src.substring(branch) : src.substring(branch, nextCase);
      expect(body.contains("context.go('/onboarding"), isFalse,
          reason: 'with the state unknown, routing into onboarding is the one '
              'answer that can destroy a real profile');
    });

    test('the evidence read opens the Hive session first', () {
      expect(src.contains('ensureOpenedForCurrentSession'), isTrue,
          reason: 'under owner-null wrapUserScopedBox serves GuardedBox.empty '
              '(guarded_box.dart:333), so an unopened session makes the '
              'evidence read silently return "no evidence"');
    });
  });
}
