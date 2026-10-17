// Contract: admin-dashboard-data Edge Function response -> AdminDashboardData.
//
// The Edge Function's admin-gate logic itself is pinned server-side by
// supabase/functions/admin-dashboard-data/index_test.ts (Deno) — that logic
// cannot run client-side. This test pins the OTHER half of the contract:
// the Dart model must parse the Edge Function's real response shape
// correctly and defensively (missing/null fields default sanely; an empty
// trend array — expected for ~30 days after ship, see the plan's
// Verification section — must not crash).
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/admin/models/admin_dashboard_data.dart';

void main() {
  group('AdminDashboardData.fromJson', () {
    test('parses a complete, well-formed response', () {
      final json = {
        'generated_at': '2026-07-12T18:15:00.000Z',
        'trend': [
          {
            'snapshot_date': '2026-07-12',
            'total_users': 13,
            'signups_today_ist': 1,
            'signups_7d': 2,
            'signups_30d': 5,
            'pro_active': 6,
            'pro_expired': 1,
            'free_users': 7,
            'active_subscriptions': 5,
            'active_last_7d': 9,
            'workouts_logged_today': 4,
            'food_logs_today': 6,
            'ai_messages_today': 20,
            'streak_maintained_current_week': 3,
            'client_errors_today': 12,
            'client_errors_7d': 90,
            'open_alerts_count': 2,
            'cron_failures_24h': 0,
          },
        ],
        'current': {
          'total_users': 13,
          'signups_today_ist': 1,
          'signups_7d': 2,
          'signups_30d': 5,
          'pro_active': 6,
          'pro_expired': 1,
          'free_users': 7,
          'active_subscriptions': 5,
          'active_last_7d': 9,
          // Engagement + ops groups merged into `current` (all live).
          'workouts_logged_today': 4,
          'food_logs_today': 6,
          'ai_messages_today': 20,
          'streak_maintained_current_week': 3,
          'client_errors_today': 12,
          'client_errors_7d': 90,
          'open_alerts_count': 2,
          'cron_failures_24h': 0,
        },
        'revenue': {
          'monthly_active': 4,
          'yearly_active': 1,
          'trial_active': 6,
          'other_active': 0,
          'derived_mrr_inr': 1745.92,
          'current_monthly_price_inr': 349,
          'current_yearly_price_inr': 2999,
        },
        'subscriptions_expiring': {
          'expired': [
            {'user_id': 'u1', 'email': 'a@x.com', 'subscription_expires_at': '2026-07-01T00:00:00.000Z'},
          ],
          'expiring7d': [],
          'expiring30d': [
            {'user_id': 'u2', 'email': null, 'subscription_expires_at': '2026-08-01T00:00:00.000Z'},
          ],
        },
        'open_alerts': [
          {
            'id': 31,
            'detected_at': '2026-07-12T05:30:00.000Z',
            'source': 'alert_client_errors_spike',
            'severity': 'info',
            'summary': 'client_errors spike',
            'suggested_action': 'Inspect docs/diagnoses',
          },
        ],
      };

      final data = AdminDashboardData.fromJson(json);

      expect(data.generatedAt, DateTime.parse('2026-07-12T18:15:00.000Z'));
      expect(data.trend, hasLength(1));
      expect(data.trend.first.snapshotDate, '2026-07-12');
      expect(data.trend.first.workoutsLoggedToday, 4);
      expect(data.current.totalUsers, 13);
      expect(data.current.proActive, 6);
      // Live engagement + ops fields merged into `current`.
      expect(data.current.workoutsLoggedToday, 4);
      expect(data.current.aiMessagesToday, 20);
      expect(data.current.clientErrorsToday, 12);
      expect(data.current.clientErrors7d, 90);
      expect(data.current.openAlertsCount, 2);
      expect(data.current.cronFailures24h, 0);
      expect(data.revenue.monthlyActive, 4);
      expect(data.revenue.trialActive, 6);
      expect(data.revenue.otherActive, 0);
      expect(data.revenue.derivedMrrInr, closeTo(1745.92, 0.001));
      expect(data.subscriptionsExpiring.expired, hasLength(1));
      expect(data.subscriptionsExpiring.expired.first.userId, 'u1');
      expect(data.subscriptionsExpiring.expiring7d, isEmpty);
      expect(data.subscriptionsExpiring.expiring30d.first.email, isNull);
      expect(data.openAlerts, hasLength(1));
      expect(data.openAlerts.first.id, 31);
      expect(data.openAlerts.first.severity, 'info');
    });

    test('an empty trend array parses to an empty list, not a crash (expected for ~30 days after ship)', () {
      final json = {
        'generated_at': '2026-07-12T18:15:00.000Z',
        'trend': <Map<String, dynamic>>[],
        'current': <String, dynamic>{},
        'revenue': <String, dynamic>{},
        'subscriptions_expiring': <String, dynamic>{},
        'open_alerts': <Map<String, dynamic>>[],
      };

      final data = AdminDashboardData.fromJson(json);

      expect(data.trend, isEmpty);
    });

    test('missing top-level keys default to empty/zeroed structures instead of throwing', () {
      final data = AdminDashboardData.fromJson({'generated_at': '2026-07-12T18:15:00.000Z'});

      expect(data.trend, isEmpty);
      expect(data.current.totalUsers, 0);
      expect(data.revenue.derivedMrrInr, 0);
      expect(data.subscriptionsExpiring.expired, isEmpty);
      expect(data.subscriptionsExpiring.expiring7d, isEmpty);
      expect(data.subscriptionsExpiring.expiring30d, isEmpty);
      expect(data.openAlerts, isEmpty);
    });

    test('a null field within an otherwise-present object defaults that field, not the whole parse', () {
      final json = {
        'generated_at': '2026-07-12T18:15:00.000Z',
        'current': {'total_users': 13, 'pro_active': null},
      };

      final data = AdminDashboardData.fromJson(json);

      expect(data.current.totalUsers, 13);
      expect(data.current.proActive, 0);
    });
  });
}
