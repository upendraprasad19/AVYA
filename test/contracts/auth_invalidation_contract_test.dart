// Source-grep — walks lib/features/*/providers/ (plus a known widget that
// declares a provider) and asserts every file containing user-scoped reads
// also watches authUserIdTokenProvider. No Hive bootstrap needed; runs in
// milliseconds.
//
// Closes APK Test #15.3 / Bug 5 (closes-diagnose: c4055a). If any new
// provider file is added that reads user-scoped Hive boxes / repositories /
// Supabase user-filtered tables WITHOUT watching authUserIdTokenProvider,
// this test fails — preventing Test #N+1 from re-surfacing the cross-account
// state cache leak class.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every user-scoped provider watches authUserIdTokenProvider (Bug c4055a)', () {
    // Pattern of user-scoped reads. Any provider file containing one of these
    // is considered user-scoped and MUST watch the auth token.
    //
    // The regex covers both direct (`HiveService.instance.userBox`) and aliased
    // (`final hive = HiveService.instance; hive.userBox`) forms, plus Supabase
    // user-filtered tables, repositories, and shared services known to
    // namespace by user.
    final userScopedPattern = RegExp(
      r'UserRepository\.|WorkoutRepository\.|NutritionRepository\.|AiCoachRepository\.|'
      r'HiveService\.instance|'
      r'\b(user|workout|nutrition|health|custom|coach|sync|notifications)Box\b|'
      r'MigratedKey\.|SubscriptionService\.|WaterTargetService\.|'
      r'NotificationInboxService|'
      r"\.from\('progress_photos'\)|\.from\('rank_promotions'\)|\.from\('referral_codes'\)|"
      r"\.from\('referral_redemptions'\)|\.from\('video_renders'\)|"
      r"\.from\('user_profile'\)|\.from\('user_progress'\)|\.from\('subscriptions'\)",
    );
    final watchPattern = RegExp(r'ref\.watch\(authUserIdTokenProvider\)');

    // Files that legitimately read user-scoped data but should NOT watch.
    // Add any new exemption with a comment justifying it.
    final exemptions = <String>{
      // Pre-auth crossing surface — intentionally shared per CLAUDE.md §15.
      'lib/features/auth/providers/referral_code_stash_provider.dart',
      // Auth provider itself + invalidation provider — can't self-watch.
      'lib/features/auth/providers/auth_provider.dart',
      'lib/features/auth/providers/auth_invalidation_provider.dart',
    };

    // Scan all of lib/features for files that contain provider declarations
    // and user-scoped reads. Not limited to /providers/ subdirs because
    // some widgets (e.g. insight_card.dart) declare top-level providers.
    final scanRoot = Directory('lib/features');

    final violations = <String>[];
    for (final entity in scanRoot.listSync(recursive: true).whereType<File>()) {
      if (!entity.path.endsWith('.dart')) continue;
      // Normalize path separator for cross-platform comparison
      final relativePath = entity.path.replaceAll(r'\', '/');
      if (exemptions.contains(relativePath)) continue;

      final content = entity.readAsStringSync();
      // Only check files that DECLARE a provider/notifier.
      // Matches:
      //   Provider<X>((ref) { ... })
      //   Provider((ref) { ... })
      //   FutureProvider<X>(...) / FutureProvider.family<X, Y>(...)
      //   StreamProvider<X>(...) / StreamProvider.family<X, Y>(...)
      //   NotifierProvider<...>
      //   class X extends Notifier<...> / AsyncNotifier<...> / StateNotifier<...>
      final hasProvider = content.contains('Provider<') ||
          content.contains('Provider((') ||
          content.contains('Provider.family<') ||
          content.contains('NotifierProvider<') ||
          content.contains('extends Notifier<') ||
          content.contains('extends AsyncNotifier<') ||
          content.contains('extends StateNotifier<');
      if (!hasProvider) continue;
      // Only check files that READ user-scoped data
      if (!userScopedPattern.hasMatch(content)) continue;
      // Must watch the auth token provider
      if (!watchPattern.hasMatch(content)) {
        violations.add(relativePath);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Bug c4055a — these provider files read user-scoped data but do '
          'not ref.watch(authUserIdTokenProvider). On signOut+signUp their '
          "cached state leaks the previous user's data into the new "
          'session. Add ref.watch(authUserIdTokenProvider) at the top of '
          "each Notifier's build() body (or at the top of the "
          'Provider<X>((ref) { ... }) builder), or add the file path to '
          'the exemptions set with a justification comment.\n\n'
          'Violations:\n${violations.join("\n")}',
    );
  });
}
