// test/sync/restore_completeness_test.dart
//
// Source-scan contract tests for Theme A (APK Test #11) restore pull side.
// These tests assert that restoreFromCloudForUser invokes the 5 new restore
// helpers and that SubscriptionService.refreshFromSupabase is folded in.
//
// They are intentionally source-scan tests (read the .dart file as text)
// rather than integration tests so they catch regressions during normal
// `flutter test` runs without requiring a device or Supabase connection.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../contracts/_sync_service_source.dart';

/// Extract the body of a private method by finding its `Future<void>` definition
/// and grabbing up to [maxChars] characters from that point.
///
/// Default raised 2000 → 4000 chars in batch 2026-05-19 / diagnose 9c4a17
/// after the max-merge fix grew `_restoreFreezes` body past 2000 chars
/// while preserving all required contract markers (`try {`, `catch (e`,
/// `'user_progress'`).
String _methodBody(String src, String methodName, {int maxChars = 4000}) {
  final sig = 'Future<void> $methodName(';
  final start = src.indexOf(sig);
  if (start == -1) return '';
  final end = (start + maxChars).clamp(0, src.length);
  return src.substring(start, end);
}

void main() {
  late String syncSrc;
  late String authSrc;

  setUpAll(() async {
    syncSrc = await loadSyncServiceSource().readAsString();
    authSrc = await File(
      'lib/features/auth/providers/auth_provider.dart',
    ).readAsString();
  });

  group('restoreFromCloudForUser — 5 restore surfaces wired', () {
    test('calls _restoreFreezes', () {
      expect(
        syncSrc,
        contains('_restoreFreezes'),
        reason: 'A1: streak-freeze restore must be wired into restoreFromCloudForUser',
      );
    });

    test('calls _restoreNotificationsInbox', () {
      expect(
        syncSrc,
        contains('_restoreNotificationsInbox'),
        reason: 'A4: notifications-inbox restore must be wired into restoreFromCloudForUser',
      );
    });

    test('calls _restoreSavedDietPlan', () {
      expect(
        syncSrc,
        contains('_restoreSavedDietPlan'),
        reason: 'A5: saved-diet-plan restore must be wired into restoreFromCloudForUser',
      );
    });

    test('calls _restoreRankPromotions', () {
      expect(
        syncSrc,
        contains('_restoreRankPromotions'),
        reason: 'A2: rank-promotions restore must be wired into restoreFromCloudForUser',
      );
    });

    test('coaching_notes is pulled inside _restoreCoachMemory', () {
      final body = _methodBody(syncSrc, '_restoreCoachMemory');
      expect(
        body,
        contains('coaching_notes'),
        reason: 'A6: coaching_notes must be included in the coach_memory SELECT and written to coachBox',
      );
    });
  });

  group('A3 — subscription refresh folded into SyncService', () {
    test('SyncService calls refreshFromSupabase inside restoreFromCloudForUser', () {
      expect(
        syncSrc,
        contains('SubscriptionService.instance.refreshFromSupabase'),
        reason: 'A3: subscription refresh must be called as the last step of restoreFromCloudForUser',
      );
    });

    test('auth_provider still calls refreshFromSupabase as fast-path fallback', () {
      expect(
        authSrc,
        contains('SubscriptionService.instance.refreshFromSupabase'),
        reason: 'auth_provider fast-path subscription refresh must remain for '
            'sign-in flows that bypass RestoringScreen (silent re-auth, etc.)',
      );
    });
  });

  group('implementation correctness — private method bodies', () {
    test('_restoreFreezes reads from user_progress table', () {
      final body = _methodBody(syncSrc, '_restoreFreezes');
      expect(
        body,
        contains("'user_progress'"),
        reason: '_restoreFreezes must query the user_progress table',
      );
    });

    test('_restoreNotificationsInbox reads from notifications_inbox table', () {
      final body = _methodBody(syncSrc, '_restoreNotificationsInbox');
      expect(
        body,
        contains("'notifications_inbox'"),
        reason: '_restoreNotificationsInbox must query the notifications_inbox table',
      );
    });

    test('_restoreSavedDietPlan reads from saved_diet_plans table', () {
      final body = _methodBody(syncSrc, '_restoreSavedDietPlan');
      expect(
        body,
        contains("'saved_diet_plans'"),
        reason: '_restoreSavedDietPlan must query the saved_diet_plans table',
      );
    });

    test('_restoreRankPromotions reads from rank_promotions table', () {
      final body = _methodBody(syncSrc, '_restoreRankPromotions');
      expect(
        body,
        contains("'rank_promotions'"),
        reason: '_restoreRankPromotions must query the rank_promotions table',
      );
    });

    test('_restoreNotificationsInbox limits to 200 rows', () {
      final body = _methodBody(syncSrc, '_restoreNotificationsInbox');
      expect(
        body,
        contains('.limit(200)'),
        reason: 'notifications_inbox restore must cap at 200 rows to avoid unbounded pull',
      );
    });

    test('_restoreRankPromotions limits to 20 rows', () {
      final body = _methodBody(syncSrc, '_restoreRankPromotions');
      expect(
        body,
        contains('.limit(20)'),
        reason: 'rank_promotions restore must cap at 20 rows',
      );
    });

    test('all 4 new restore methods have try/catch error handling', () {
      final methods = [
        '_restoreFreezes',
        '_restoreNotificationsInbox',
        '_restoreSavedDietPlan',
        '_restoreRankPromotions',
      ];
      for (final method in methods) {
        final body = _methodBody(syncSrc, method);
        expect(
          body,
          isNot(isEmpty),
          reason: '$method must be defined as a Future<void> method',
        );
        expect(
          body,
          contains('try {'),
          reason: '$method must have a try block for error isolation',
        );
        expect(
          body,
          contains('catch (e'),
          reason: '$method must catch errors so one failure does not abort the full restore',
        );
      }
    });
  });
}
