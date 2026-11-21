/// Response model for the `admin-dashboard-data` Edge Function.
///
/// This is the one place in the app that parses a direct Supabase Edge
/// Function response rather than a Hive map — see
/// `lib/features/admin/CLAUDE.md` for why the Hive-first rule doesn't
/// apply here. Every field is defensively parsed (missing/null -> a sane
/// zero/empty default) since this data crosses a network boundary and the
/// trend array in particular will be empty or near-empty for the first
/// ~30 days after ship (one snapshot accumulates per day).
library;

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;
double _double(dynamic v) => (v as num?)?.toDouble() ?? 0;
String _str(dynamic v) => v as String? ?? '';
String? _strOrNull(dynamic v) => v as String?;

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) parse) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => parse(Map<String, dynamic>.from(e)))
      .toList();
}

class AdminMetricsSnapshotPoint {
  final String snapshotDate;
  final int totalUsers;
  final int signupsTodayIst;
  final int signups7d;
  final int signups30d;
  final int proActive;
  final int proExpired;
  final int freeUsers;
  final int activeSubscriptions;
  final int activeLast7d;
  final int workoutsLoggedToday;
  final int foodLogsToday;
  final int aiMessagesToday;
  final int streakMaintainedCurrentWeek;
  final int clientErrorsToday;
  final int clientErrors7d;
  final int openAlertsCount;
  final int cronFailures24h;

  const AdminMetricsSnapshotPoint({
    required this.snapshotDate,
    required this.totalUsers,
    required this.signupsTodayIst,
    required this.signups7d,
    required this.signups30d,
    required this.proActive,
    required this.proExpired,
    required this.freeUsers,
    required this.activeSubscriptions,
    required this.activeLast7d,
    required this.workoutsLoggedToday,
    required this.foodLogsToday,
    required this.aiMessagesToday,
    required this.streakMaintainedCurrentWeek,
    required this.clientErrorsToday,
    required this.clientErrors7d,
    required this.openAlertsCount,
    required this.cronFailures24h,
  });

  factory AdminMetricsSnapshotPoint.fromJson(Map<String, dynamic> json) {
    return AdminMetricsSnapshotPoint(
      snapshotDate: _str(json['snapshot_date']),
      totalUsers: _int(json['total_users']),
      signupsTodayIst: _int(json['signups_today_ist']),
      signups7d: _int(json['signups_7d']),
      signups30d: _int(json['signups_30d']),
      proActive: _int(json['pro_active']),
      proExpired: _int(json['pro_expired']),
      freeUsers: _int(json['free_users']),
      activeSubscriptions: _int(json['active_subscriptions']),
      activeLast7d: _int(json['active_last_7d']),
      workoutsLoggedToday: _int(json['workouts_logged_today']),
      foodLogsToday: _int(json['food_logs_today']),
      aiMessagesToday: _int(json['ai_messages_today']),
      streakMaintainedCurrentWeek: _int(json['streak_maintained_current_week']),
      clientErrorsToday: _int(json['client_errors_today']),
      clientErrors7d: _int(json['client_errors_7d']),
      openAlertsCount: _int(json['open_alerts_count']),
      cronFailures24h: _int(json['cron_failures_24h']),
    );
  }
}

/// LIVE current-state metrics — the read Edge Function merges all three
/// `founder_metrics_*()` groups (growth + engagement + ops) into one `current`
/// object, so every current-value stat tile is genuinely live (NOT the up-to-
/// 24h-stale daily snapshot). The snapshot table backs only the `trend` series.
class AdminCurrentMetrics {
  // Growth (founder_metrics_for_admin_api)
  final int totalUsers;
  final int signupsTodayIst;
  final int signups7d;
  final int signups30d;
  final int proActive;
  final int proExpired;
  final int freeUsers;
  final int activeSubscriptions;
  final int activeLast7d;
  // Engagement (founder_metrics_engagement)
  final int workoutsLoggedToday;
  final int foodLogsToday;
  final int aiMessagesToday;
  final int streakMaintainedCurrentWeek;
  // Hold-week telemetry (founder_metrics_engagement, migration 120 / FOB-5).
  //
  // These MUST be declared here, not merely returned by the RPC. The Edge
  // Function spreads the RPC row wholesale (admin-dashboard-data/index.ts:255),
  // which is why migration 120 needed no redeploy — but this class is a
  // NAMED-KEY parser, so a column with no field here is silently dropped at
  // parse and renders nowhere. FOB-5 shipped in exactly that state and its
  // own claim ("the consumer is REAL, not aspirational") was true only to the
  // HTTP boundary (Hermes P1-D).
  //
  // holdersTotal is a LOWER BOUND, not a count: rolling-context's nightly
  // summarize-and-delete prunes the ai_coach_interactions rows these are
  // counted over (91 of 92 comparable rows already gone when measured
  // 2026-08-20), and an offline hold emits nothing at all because
  // AppEventsService drops failed inserts with no queue. The tile label says
  // so rather than implying a census.
  final int holdsStartedToday;
  final int holdsStarted7d;
  final int holdersTotal;
  // Ops (founder_metrics_ops)
  final int clientErrorsToday;
  final int clientErrors7d;
  final int openAlertsCount;
  final int cronFailures24h;

  const AdminCurrentMetrics({
    required this.totalUsers,
    required this.signupsTodayIst,
    required this.signups7d,
    required this.signups30d,
    required this.proActive,
    required this.proExpired,
    required this.freeUsers,
    required this.activeSubscriptions,
    required this.activeLast7d,
    required this.workoutsLoggedToday,
    required this.foodLogsToday,
    required this.aiMessagesToday,
    required this.streakMaintainedCurrentWeek,
    required this.holdsStartedToday,
    required this.holdsStarted7d,
    required this.holdersTotal,
    required this.clientErrorsToday,
    required this.clientErrors7d,
    required this.openAlertsCount,
    required this.cronFailures24h,
  });

  factory AdminCurrentMetrics.fromJson(Map<String, dynamic> json) {
    return AdminCurrentMetrics(
      totalUsers: _int(json['total_users']),
      signupsTodayIst: _int(json['signups_today_ist']),
      signups7d: _int(json['signups_7d']),
      signups30d: _int(json['signups_30d']),
      proActive: _int(json['pro_active']),
      proExpired: _int(json['pro_expired']),
      freeUsers: _int(json['free_users']),
      activeSubscriptions: _int(json['active_subscriptions']),
      activeLast7d: _int(json['active_last_7d']),
      workoutsLoggedToday: _int(json['workouts_logged_today']),
      foodLogsToday: _int(json['food_logs_today']),
      aiMessagesToday: _int(json['ai_messages_today']),
      streakMaintainedCurrentWeek: _int(json['streak_maintained_current_week']),
      holdsStartedToday: _int(json['holds_started_today']),
      holdsStarted7d: _int(json['holds_started_7d']),
      holdersTotal: _int(json['holders_total']),
      clientErrorsToday: _int(json['client_errors_today']),
      clientErrors7d: _int(json['client_errors_7d']),
      openAlertsCount: _int(json['open_alerts_count']),
      cronFailures24h: _int(json['cron_failures_24h']),
    );
  }
}

class AdminRevenueMetrics {
  final int monthlyActive;
  final int yearlyActive;

  /// Non-paying `referral_trial` subscriptions. Surfaced so the plan split
  /// reconciles against the active-sub count (₹0 toward MRR).
  final int trialActive;

  /// Catch-all for any plan value that isn't monthly/yearly/referral_trial —
  /// a future unforeseen plan shows here instead of silently vanishing.
  final int otherActive;
  final double derivedMrrInr;
  final int currentMonthlyPriceInr;
  final int currentYearlyPriceInr;

  const AdminRevenueMetrics({
    required this.monthlyActive,
    required this.yearlyActive,
    required this.trialActive,
    required this.otherActive,
    required this.derivedMrrInr,
    required this.currentMonthlyPriceInr,
    required this.currentYearlyPriceInr,
  });

  factory AdminRevenueMetrics.fromJson(Map<String, dynamic> json) {
    return AdminRevenueMetrics(
      monthlyActive: _int(json['monthly_active']),
      yearlyActive: _int(json['yearly_active']),
      trialActive: _int(json['trial_active']),
      otherActive: _int(json['other_active']),
      derivedMrrInr: _double(json['derived_mrr_inr']),
      currentMonthlyPriceInr: _int(json['current_monthly_price_inr']),
      currentYearlyPriceInr: _int(json['current_yearly_price_inr']),
    );
  }
}

class AdminExpiringSubscription {
  final String userId;
  final String? email;
  final DateTime subscriptionExpiresAt;

  const AdminExpiringSubscription({
    required this.userId,
    required this.email,
    required this.subscriptionExpiresAt,
  });

  factory AdminExpiringSubscription.fromJson(Map<String, dynamic> json) {
    final raw = json['subscription_expires_at'] as String?;
    return AdminExpiringSubscription(
      userId: _str(json['user_id']),
      email: _strOrNull(json['email']),
      // tryParse (not parse) so a malformed/non-ISO string degrades to a
      // sentinel instead of throwing FormatException and blanking the whole
      // dashboard (Hermes L37 hardening).
      subscriptionExpiresAt:
          (raw != null ? DateTime.tryParse(raw) : null) ?? DateTime(1970),
    );
  }
}

class AdminExpiryBuckets {
  final List<AdminExpiringSubscription> expired;
  final List<AdminExpiringSubscription> expiring7d;
  final List<AdminExpiringSubscription> expiring30d;

  const AdminExpiryBuckets({
    required this.expired,
    required this.expiring7d,
    required this.expiring30d,
  });

  factory AdminExpiryBuckets.fromJson(Map<String, dynamic> json) {
    return AdminExpiryBuckets(
      expired: _list(json['expired'], AdminExpiringSubscription.fromJson),
      expiring7d: _list(json['expiring7d'], AdminExpiringSubscription.fromJson),
      expiring30d: _list(json['expiring30d'], AdminExpiringSubscription.fromJson),
    );
  }
}

class AdminAlert {
  final int id;
  final DateTime detectedAt;
  final String source;
  final String severity;
  final String summary;
  final String? suggestedAction;

  const AdminAlert({
    required this.id,
    required this.detectedAt,
    required this.source,
    required this.severity,
    required this.summary,
    required this.suggestedAction,
  });

  factory AdminAlert.fromJson(Map<String, dynamic> json) {
    final raw = json['detected_at'] as String?;
    return AdminAlert(
      id: _int(json['id']),
      detectedAt: (raw != null ? DateTime.tryParse(raw) : null) ?? DateTime(1970),
      source: _str(json['source']),
      severity: _str(json['severity']),
      summary: _str(json['summary']),
      suggestedAction: _strOrNull(json['suggested_action']),
    );
  }
}

class AdminDashboardData {
  final DateTime generatedAt;
  final List<AdminMetricsSnapshotPoint> trend;
  final AdminCurrentMetrics current;
  final AdminRevenueMetrics revenue;
  final AdminExpiryBuckets subscriptionsExpiring;
  final List<AdminAlert> openAlerts;

  const AdminDashboardData({
    required this.generatedAt,
    required this.trend,
    required this.current,
    required this.revenue,
    required this.subscriptionsExpiring,
    required this.openAlerts,
  });

  factory AdminDashboardData.fromJson(Map<String, dynamic> json) {
    final rawGeneratedAt = json['generated_at'] as String?;
    return AdminDashboardData(
      generatedAt:
          (rawGeneratedAt != null ? DateTime.tryParse(rawGeneratedAt) : null) ??
              DateTime.now(),
      trend: _list(json['trend'], AdminMetricsSnapshotPoint.fromJson),
      current: AdminCurrentMetrics.fromJson(
        Map<String, dynamic>.from(json['current'] as Map? ?? const {}),
      ),
      revenue: AdminRevenueMetrics.fromJson(
        Map<String, dynamic>.from(json['revenue'] as Map? ?? const {}),
      ),
      subscriptionsExpiring: AdminExpiryBuckets.fromJson(
        Map<String, dynamic>.from(json['subscriptions_expiring'] as Map? ?? const {}),
      ),
      openAlerts: _list(json['open_alerts'], AdminAlert.fromJson),
    );
  }
}
