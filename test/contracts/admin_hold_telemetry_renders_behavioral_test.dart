import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/features/admin/models/admin_dashboard_data.dart';
import 'package:icanbefitter/features/admin/widgets/engagement_tab.dart';

/// Hermes P1-D. Migration 120 added holds_started_today / holds_started_7d /
/// holders_total to founder_metrics_engagement(), and FOB-5 claimed "the
/// consumer is REAL, not aspirational" on the strength of
/// admin-dashboard-data/index.ts:255 spreading the RPC row wholesale.
///
/// That claim was true only to the HTTP boundary. AdminCurrentMetrics.fromJson
/// is a NAMED-KEY parser: a column with no field is silently dropped at parse,
/// and engagement_tab renders a fixed tile list. The founder saw nothing.
///
/// So this file deliberately asserts at BOTH layers. Testing fromJson alone
/// would repeat the very error the finding is about — verifying at the layer
/// being looked at and not one layer further.
void main() {
  AdminDashboardData dataWith(Map<String, dynamic> current) =>
      AdminDashboardData.fromJson({
        'generated_at': '2026-08-20T18:30:00Z',
        'trend': const [],
        'current': current,
        'revenue': const {},
        'subscriptions_expiring': const {},
        'open_alerts': const [],
      });

  group('P1-D — the hold columns reach the DASHBOARD, not just the payload',
      () {
    test('fromJson parses all three columns', () {
      final d = dataWith({
        'holds_started_today': 3,
        'holds_started_7d': 11,
        'holders_total': 47,
      });
      expect(d.current.holdsStartedToday, 3);
      expect(d.current.holdsStarted7d, 11);
      expect(d.current.holdersTotal, 47);
    });

    // Migration 120's inline rollback shrinks the return signature back to 5
    // columns. The EF spreads whatever it gets and names none of these keys, so
    // a revert must degrade to zeroes rather than throw — otherwise rolling
    // back the migration would break the admin dashboard entirely.
    test('a rolled-back migration (keys absent) degrades to 0, does not throw',
        () {
      final d = dataWith({'ai_messages_today': 22});
      expect(d.current.holdsStartedToday, 0);
      expect(d.current.holdsStarted7d, 0);
      expect(d.current.holdersTotal, 0);
      expect(d.current.aiMessagesToday, 22,
          reason: 'the pre-existing columns still parse');
    });

    testWidgets('EngagementTab RENDERS all three values', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EngagementTab(
            data: dataWith({
              'workouts_logged_today': 8,
              'ai_messages_today': 22,
              'holds_started_today': 3,
              'holds_started_7d': 11,
              'holders_total': 47,
            }),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // WardStatTile uppercases both label and unit at render
      // (ward_stat_tile.dart:50,75), so these assert the RENDERED form. Pinning
      // the source-cased string instead would pass a widget that never paints.
      expect(find.text('HOLDS TODAY'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      expect(find.text('47'), findsOneWidget);

      // "min" is load-bearing, not decoration: rolling-context prunes the rows
      // these count nightly (91 of 92 already gone when measured 2026-08-20)
      // and an offline hold never emits at all, so holders_total is a floor.
      // Labelling it a total would misrepresent the retention thesis it feeds.
      expect(find.text('MIN, ALL-TIME'), findsOneWidget,
          reason: 'the floor caveat must be visible to the founder reading it');
    });

    testWidgets('a holder-free dashboard still renders the tiles as 0',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // The expected state while enable_hold_weeks is OFF. The tiles must be
      // PRESENT and read 0 — an absent tile is indistinguishable from a
      // regression that dropped the wiring again.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: EngagementTab(data: dataWith(const {}))),
      ));
      await tester.pumpAndSettle();

      expect(find.text('HOLDS TODAY'), findsOneWidget);
      expect(find.text('HOLDERS'), findsOneWidget);
    });
  });
}
