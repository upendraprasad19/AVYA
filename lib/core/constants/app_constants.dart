/// App-wide constants: API URLs, feature keys, limits, and thresholds.
///
/// Environment variables (SUPABASE_URL, SUPABASE_ANON_KEY, RAZORPAY_KEY_ID)
/// are injected at build time via --dart-define-from-file=.env and accessed
/// through String.fromEnvironment(). They are NEVER bundled as assets.
class AppConstants {
  AppConstants._();

  // ── API URLs (injected at build time via --dart-define-from-file) ──

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Edge Function names (invoked via Supabase client).
  // `ai-proxy-pro` was merged into `ai-proxy` on 2026-04-18 (single
  // Gemini endpoint, server-side free/PRO gate). The deployed function
  // still serves 410 Gone for orphan clients; do not re-introduce the
  // constant.
  static const String aiProxyFunction = 'ai-proxy';
  static const String razorpayWebhookFunction = 'razorpay-webhook';
  static const String dailySnapshotFunction = 'daily-snapshot';
  static const String weeklyRecalcFunction = 'weekly-recalc';
  static const String rollingContextFunction = 'rolling-context';
  static const String morningAlertFunction = 'morning-alert';
  static const String beatMyCoachFunction = 'beat-my-coach';
  static const String futurePredictionFunction = 'future-prediction';
  static const String weeklyReportFunction = 'weekly-report';
  static const String aiMediaProxyFunction = 'ai-media-proxy';

  // ── Subscription ──────────────────────────────────────────

  static const int monthlyPriceInr = 349;
  static const int yearlyPriceInr = 2999;

  // ── PRO Feature Keys ──────────────────────────────────────

  static const String featurePhases2To12 = 'phases_2_to_12';
  static const String featureActiveWorkoutMode = 'active_workout_mode';
  static const String featureAiCoachUnlimited = 'ai_coach_unlimited';
  // `featureReasoningTab` removed 2026-04-18 — Chat/Reasoning toggle
  // deleted from UI, single AI coach backend, no separate reasoning gate.
  static const String featureWeeklyAiReport = 'weekly_ai_report';
  static const String featureProgressPhotos = 'progress_photos';
  static const String featureScanMealPro = 'scan_meal_pro';         // 10/day PRO (free=3/day)
  static const String featureCartAuditorPro = 'cart_auditor_pro';   // 10/day PRO (free=1/day)
  static const String featureAiTextLogPro = 'ai_text_log_pro';      // Unlimited PRO (free=10/day)
  static const String featureVoiceNotes = 'voice_notes';
  static const String featureMorningAlertPro = 'morning_alert_pro'; // AI-personalised (free=generic)
  static const String featurePredictionMonthly = 'prediction_monthly'; // Monthly card (free=once)
  static const String featureAdaptiveWorkouts = 'adaptive_workouts'; // Phase 2
  static const String featureDietPlanPdf = 'diet_plan_pdf';        // PDF export
  static const String featurePhotoAnalysis = 'photo_analysis';     // Photo in chat (PRO)

  // ── Free Tier Limits ──────────────────────────────────────

  /// Maximum AI coach messages per day for free users.
  /// Must match FREE_DAILY_LIMIT in ai-proxy Edge Function (15).
  static const int freeAiMessagesPerDay = 15;

  /// Free AI coach trial duration in days.
  static const int freeAiTrialDays = 30;

  /// Free AI food text logs per day.
  static const int freeAiTextLogsPerDay = 10;

  /// Free scan meal uses per day.
  static const int freeScanMealPerDay = 3;

  /// PRO scan meal uses per day (soft cap warning at 7).
  static const int proScanMealPerDay = 10;

  /// Free cart auditor uses per day.
  static const int freeCartAuditorPerDay = 1;

  /// PRO cart auditor uses per day (soft cap warning at 7).
  static const int proCartAuditorPerDay = 10;

  /// Beat My Coach challenge interval in days (disabled — Phase 2).
  static const int beatMyCoachIntervalDays = 14;

  /// OneSignal App ID for push notifications.
  static const String oneSignalAppId = 'fd37a411-121e-4022-9929-2af68c2371f5';

  // ── Phase Unlock ──────────────────────────────────────────

  /// Minimum completion rate to unlock next phase (80%).
  static const double phaseUnlockCompletionRate = 0.8;

  /// Minimum weeks elapsed to unlock next phase.
  static const int phaseUnlockMinWeeks = 4;

  // ── Sync Intervals ────────────────────────────────────────

  /// Full sync interval in days.
  static const int fullSyncIntervalDays = 7;

  /// Daily snapshot time (IST — 11 PM = 17:30 UTC).
  static const int snapshotHourUtc = 17;
  static const int snapshotMinuteUtc = 30;

  // ── Hive Box Names ────────────────────────────────────────

  static const String userBox = 'userBox';
  static const String workoutBox = 'workoutBox';
  static const String nutritionBox = 'nutritionBox';
  static const String healthBox = 'healthBox';
  static const String exerciseBox = 'exerciseBox';
  static const String foodBox = 'foodBox';
  static const String customBox = 'customBox';
  static const String coachBox = 'coachBox';
  static const String syncBox = 'syncBox';
  static const String configBox = 'configBox';

  // ── Misc ──────────────────────────────────────────────────

  /// App display name.
  static const String appName = 'AVYA';

  /// App tagline — used on splash, shareable cards, marketing materials.
  static const String appTagline = 'Your AI Fitness Coach';

  /// App website — used in QR codes on shareable cards.
  /// TODO: Update to Play Store link before launch.
  static const String appUrl = 'https://www.icanbefitter.com';

  /// Packages required for shareable cards:
  /// - share_plus: native OS share sheet
  /// - qr_flutter: client-side QR code generation (zero server cost)

  /// Razorpay key (public, safe for client) — injected at build time.
  static const String razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');
}
