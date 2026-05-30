// Tech-debt audit 2026-05-20 findings A1 + A9 — behavioral contract
// for AuthSessionBootstrapper.
//
// A1 (god-provider extract): auth_provider.dart formerly did Postgres
// CRUD on `users` / `user_profile` / `user_progress` inline, plus
// OneSignal player_id push. All of that now lives on
// AuthSessionBootstrapper (lib/core/services/auth_session_bootstrapper.dart).
//
// A9 (widget-layer direct Supabase): restoring_screen.dart formerly
// ran `Supabase.instance.client.from('user_profile').select()` at
// lines 50, 59, 228. All three routes now go through
// AuthSessionBootstrapper.instance.resolveDestination().
//
// This test pins the decision-tree semantics behaviorally via the
// pure `classifyDestination` helper (no Supabase mocking needed) +
// adds source-grep contracts for the structural claims.
//
// Run: flutter test test/contracts/auth_session_bootstrapper_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';

void main() {
  group('AuthSessionBootstrapper.classifyDestination (pure)', () {
    test('null row → StartMissionBrief (brand-new user)', () {
      final result = AuthSessionBootstrapper.classifyDestination(null);
      expect(result, isA<StartMissionBrief>());
    });

    test(
        'row with onboarding_completed_at IS NOT NULL → GoHome '
        '(fully onboarded user)', () {
      final result = AuthSessionBootstrapper.classifyDestination({
        'user_id': 'u1',
        'onboarding_completed_at': '2026-05-20T12:00:00Z',
        'date_of_birth': '2001-01-01',
        'primary_goal': 'muscle_gain',
        'current_weight_kg': 75.0,
        'fitness_experience': 'intermediate',
      });
      expect(result, isA<GoHome>());
    });

    // NOTE: the identity step is detected via `date_of_birth` (a real
    // user_profile column written by the onboarding identity screen +
    // sync_profile.dart:84), NOT `full_name`. `full_name` lives on the
    // `users` table — querying it from user_profile 42703s. Regression
    // guard for diagnose 2026-05-30-resolve-destination-full-name-drift.
    test(
        'row with onboarding_completed_at NULL + null date_of_birth → '
        "ResumeOnboarding('identity')", () {
      final result = AuthSessionBootstrapper.classifyDestination({
        'user_id': 'u1',
        'onboarding_completed_at': null,
        'date_of_birth': null,
        'primary_goal': null,
        'current_weight_kg': null,
        'fitness_experience': null,
      });
      expect(result, isA<ResumeOnboarding>());
      expect((result as ResumeOnboarding).firstMissingStep, 'identity');
    });

    test(
        'completed_at NULL + date_of_birth set, goal null → '
        "ResumeOnboarding('goal')", () {
      final result = AuthSessionBootstrapper.classifyDestination({
        'user_id': 'u1',
        'onboarding_completed_at': null,
        'date_of_birth': '2001-01-01',
        'primary_goal': null,
        'current_weight_kg': null,
        'fitness_experience': null,
      });
      expect(result, isA<ResumeOnboarding>());
      expect((result as ResumeOnboarding).firstMissingStep, 'goal');
    });

    test(
        'completed_at NULL + dob + goal set, weight null → '
        "ResumeOnboarding('stats')", () {
      final result = AuthSessionBootstrapper.classifyDestination({
        'user_id': 'u1',
        'onboarding_completed_at': null,
        'date_of_birth': '2001-01-01',
        'primary_goal': 'muscle_gain',
        'current_weight_kg': null,
        'fitness_experience': null,
      });
      expect(result, isA<ResumeOnboarding>());
      expect((result as ResumeOnboarding).firstMissingStep, 'stats');
    });

    test(
        'completed_at NULL + dob + goal + weight set, experience null → '
        "ResumeOnboarding('details')", () {
      final result = AuthSessionBootstrapper.classifyDestination({
        'user_id': 'u1',
        'onboarding_completed_at': null,
        'date_of_birth': '2001-01-01',
        'primary_goal': 'muscle_gain',
        'current_weight_kg': 75.0,
        'fitness_experience': null,
      });
      expect(result, isA<ResumeOnboarding>());
      expect((result as ResumeOnboarding).firstMissingStep, 'details');
    });

    test(
        'completed_at NULL + every field set → ResumeOnboarding(plan) '
        '(stamping step missed)', () {
      final result = AuthSessionBootstrapper.classifyDestination({
        'user_id': 'u1',
        'onboarding_completed_at': null,
        'date_of_birth': '2001-01-01',
        'primary_goal': 'muscle_gain',
        'current_weight_kg': 75.0,
        'fitness_experience': 'intermediate',
      });
      expect(result, isA<ResumeOnboarding>());
      expect((result as ResumeOnboarding).firstMissingStep, 'plan');
    });
  });

  group('AuthSessionBootstrapper structural contracts', () {
    test('AuthSessionBootstrapper exposes singleton .instance', () {
      // Two reads of .instance must return the same object — proves
      // the singleton convention matches HealthWriteService / WorkoutWriteService.
      expect(
        identical(
          AuthSessionBootstrapper.instance,
          AuthSessionBootstrapper.instance,
        ),
        isTrue,
        reason:
            'AuthSessionBootstrapper.instance must be a singleton (mirror '
            'HealthWriteService / WorkoutWriteService convention).',
      );
    });

    test('PostSignInDestination is a sealed hierarchy', () {
      // Exercising the three subclasses guarantees they exist and are
      // constructible. The `sealed` modifier on the parent forces the
      // switch in restoring_screen._kickoffRestore to handle every
      // case explicitly (audit A9 contract).
      const a = StartMissionBrief();
      const b = GoHome();
      const c = ResumeOnboarding('identity');
      expect(a, isA<PostSignInDestination>());
      expect(b, isA<PostSignInDestination>());
      expect(c, isA<PostSignInDestination>());
    });
  });

  group('AuthSessionBootstrapper source-grep contracts', () {
    // The bootstrapper source MUST keep these invariants. These
    // checks are deliberately structural because the heavier
    // behavioral tests (Postgres-touching) would require a mocked
    // Supabase client we don't have infra for.

    String? _strippedSource;
    String stripped() {
      _strippedSource ??= _stripComments(
        File('lib/core/services/auth_session_bootstrapper.dart')
            .readAsStringSync(),
      );
      return _strippedSource!;
    }

    test('routes all Supabase access via SupabaseService.instance.client', () {
      final src = stripped();
      expect(
        src.contains('Supabase.instance.client'),
        isFalse,
        reason:
            'AuthSessionBootstrapper must not bypass SupabaseService — '
            'all reads must go through SupabaseService.instance.client.',
      );
      expect(
        src.contains('_supabase.client') || src.contains('SupabaseService.instance.client'),
        isTrue,
        reason: 'AuthSessionBootstrapper must hold a SupabaseService handle.',
      );
    });

    test('routes errors through ErrorTelemetry.recordNonFatal (audit A11)', () {
      final src = stripped();
      expect(
        src.contains('ErrorTelemetry.recordNonFatal'),
        isTrue,
        reason:
            'AuthSessionBootstrapper must route catch-path errors to the '
            'canonical telemetry sink (no silent debugPrint-only).',
      );
    });

    test('Profile writes go through ProfileWriteService (audit A4)', () {
      final src = stripped();
      expect(
        src.contains('ProfileWriteService.instance'),
        isTrue,
        reason:
            'AuthSessionBootstrapper must route profile-map writes through '
            'ProfileWriteService — direct userBox.put("profile", ...) is '
            'forbidden by audit A4.',
      );
      expect(
        src.contains("userBox.put('profile'") ||
            src.contains('userBox.put("profile"'),
        isFalse,
        reason:
            'AuthSessionBootstrapper must not put("profile") directly — '
            'use ProfileWriteService.updateProfile.',
      );
    });

    test('Per-user mutex serialises concurrent calls', () {
      final src = stripped();
      expect(
        src.contains('_locks') && src.contains('Completer<void>'),
        isTrue,
        reason:
            'AuthSessionBootstrapper must hold a per-userId Completer mutex '
            '(mirror WorkoutWriteService).',
      );
    });

    // Regression guard — diagnose 2026-05-30-resolve-destination-full-name-
    // drift. The user_profile SELECT in resolveDestination must NOT reference
    // `full_name` (that column lives on `users`; querying it from
    // user_profile raises PostgREST 42703 → the catch silently returns
    // StartMissionBrief for EVERY user, re-onboarding fresh-install returning
    // users). Identity-step completion is detected via `date_of_birth`.
    test('resolveDestination does not query non-existent user_profile.full_name',
        () {
      final src = stripped();
      final start = src.indexOf('resolveDestination(String userId)');
      expect(start, isNot(-1),
          reason: 'resolveDestination must still exist');
      final after = src.substring(start);
      final endIdx = after.indexOf('classifyDestination');
      final body = endIdx == -1 ? after : after.substring(0, endIdx);
      expect(
        body.contains('full_name'),
        isFalse,
        reason:
            'resolveDestination must NOT select full_name from user_profile — '
            'that column lives on `users` (live schema 2026-05-30). Querying '
            'it 42703s and the catch falls back to StartMissionBrief for every '
            'user. Use date_of_birth to detect the identity step.',
      );
      expect(
        body.contains('date_of_birth'),
        isTrue,
        reason:
            'resolveDestination must select date_of_birth (a real user_profile '
            'column) to detect identity-step completion.',
      );
    });

    test('classifyDestination keys the identity step off date_of_birth', () {
      final src = stripped();
      final start = src.indexOf('classifyDestination(');
      expect(start, isNot(-1));
      final body = src.substring(start);
      expect(
        body.contains("row['date_of_birth']"),
        isTrue,
        reason:
            'classifyDestination must detect the missing identity step via '
            "row['date_of_birth'] (full_name is not on user_profile).",
      );
      expect(
        body.contains("row['full_name']"),
        isFalse,
        reason:
            "classifyDestination must not read row['full_name'] — the SELECT "
            'no longer fetches it (and the column is not on user_profile).',
      );
    });
  });

  group('restoring_screen.dart A9 contract', () {
    test(
        'restoring_screen.dart no longer imports supabase_flutter '
        'or calls Supabase.instance.client directly', () {
      final src = _stripComments(
        File('lib/features/auth/screens/restoring_screen.dart')
            .readAsStringSync(),
      );
      expect(
        src.contains("package:supabase_flutter/supabase_flutter.dart"),
        isFalse,
        reason: 'restoring_screen.dart must not import supabase_flutter '
            '— route through AuthSessionBootstrapper instead.',
      );
      expect(
        src.contains('Supabase.instance.client'),
        isFalse,
        reason: 'restoring_screen.dart must not access '
            'Supabase.instance.client directly (audit A9).',
      );
    });

    test(
        'restoring_screen.dart calls AuthSessionBootstrapper.instance.'
        'resolveDestination', () {
      final src = _stripComments(
        File('lib/features/auth/screens/restoring_screen.dart')
            .readAsStringSync(),
      );
      expect(
        src.contains('AuthSessionBootstrapper.instance.resolveDestination'),
        isTrue,
        reason: 'restoring_screen.dart must delegate destination '
            'resolution to AuthSessionBootstrapper (audit A9).',
      );
    });
  });

  group('auth_provider.dart A1 contract', () {
    test(
        'auth_provider._ensureLocalUser delegates cloud hydration to '
        'AuthSessionBootstrapper.hydrateFromCloud', () {
      final src = _stripComments(
        File('lib/features/auth/providers/auth_provider.dart')
            .readAsStringSync(),
      );
      expect(
        src.contains('AuthSessionBootstrapper.instance.hydrateFromCloud'),
        isTrue,
        reason: 'auth_provider must delegate the post-sign-in cloud '
            'hydration block to AuthSessionBootstrapper (audit A1).',
      );
    });

    test(
        'auth_provider.dart no longer issues Postgres CRUD on users / '
        'user_profile / user_progress inside _ensureLocalUser', () {
      final src = _stripComments(
        File('lib/features/auth/providers/auth_provider.dart')
            .readAsStringSync(),
      );

      // Find the _ensureLocalUser body so the assertion is scoped — we
      // don't want to false-positive on signOut() / verifyOtp() which
      // legitimately call auth.signOut etc.
      final start = src.indexOf('Future<void> _ensureLocalUser(');
      expect(start, isNot(-1),
          reason: '_ensureLocalUser must still exist on AuthNotifier');
      final body = src.substring(start);

      // Postgres CRUD against these tables must have moved to the bootstrapper.
      final forbiddenPatterns = <String>[
        ".from('users')",
        ".from('user_profile')",
        ".from('user_progress')",
      ];
      for (final p in forbiddenPatterns) {
        expect(
          body.contains(p),
          isFalse,
          reason: 'auth_provider._ensureLocalUser must not call $p directly '
              '— that CRUD now lives in AuthSessionBootstrapper (audit A1).',
        );
      }
    });
  });
}

/// Strip block + line comments so source-grep contracts don't false-
/// positive on explanatory comments that quote the banned pattern.
/// Canonical helper per `feedback_source_grep_strip_comments_first.md`.
String _stripComments(String src) {
  // Strip block comments first (greedy by line, non-greedy across).
  final noBlocks =
      src.replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');
  // Strip // line comments (preserve the newline for line counts).
  final noLines = noBlocks.replaceAll(RegExp(r'//[^\n]*'), '');
  return noLines;
}
