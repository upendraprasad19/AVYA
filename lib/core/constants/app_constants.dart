import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-wide constants: API URLs, feature keys, limits, and thresholds.
class AppConstants {
  AppConstants._();

  // ── API URLs (Supabase — loaded from .env) ────────────────────

  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // Edge Function names (invoked via Supabase client).
  static const String aiProxyFunction = 'ai-proxy';
  static const String aiProxyProFunction = 'ai-proxy-pro';
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
  static const String featureReasoningTab = 'reasoning_tab';
  static const String featureWeeklyAiReport = 'weekly_ai_report';
  static const String featureProgressPhotos = 'progress_photos';
  static const String featureScanMealPro = 'scan_meal_pro';         // 3/day PRO (free=3/month)
  static const String featureCartAuditorPro = 'cart_auditor_pro';   // 3/day PRO (free=1/month)
  static const String featureAiTextLogPro = 'ai_text_log_pro';      // 10/day PRO (free=3/day)
  static const String featureVoiceNotes = 'voice_notes';
  static const String featureMorningAlertPro = 'morning_alert_pro'; // AI-personalised (free=generic)
  static const String featurePredictionMonthly = 'prediction_monthly'; // Monthly card (free=once)
  static const String featureAdaptiveWorkouts = 'adaptive_workouts'; // Phase 2
  static const String featureDietPlanPdf = 'diet_plan_pdf';        // PDF export
  static const String featurePhotoAnalysis = 'photo_analysis';     // Photo in chat (PRO)

  // ── Free Tier Limits ──────────────────────────────────────

  /// Maximum AI coach messages per day for free users.
  static const int freeAiMessagesPerDay = 15;

  /// Free AI coach trial duration in days.
  static const int freeAiTrialDays = 30;

  /// Free AI food text logs per day.
  static const int freeAiTextLogsPerDay = 3;

  /// PRO AI food text logs per day.
  static const int proAiTextLogsPerDay = 10;

  /// Free scan meal uses per month.
  static const int freeScanMealPerMonth = 3;

  /// PRO scan meal uses per day (soft cap warning at 2).
  static const int proScanMealPerDay = 3;

  /// Free cart auditor uses per month.
  static const int freeCartAuditorPerMonth = 1;

  /// PRO cart auditor uses per day (soft cap warning at 2).
  static const int proCartAuditorPerDay = 3;

  /// Beat My Coach challenge interval in days (free users).
  static const int beatMyCoachIntervalDays = 14;

  /// Free users can restore up to this many days of data.
  /// Updated from 30 → 90 for better AI personalisation and user retention.
  static const int freeRestoreDays = 90;

  /// PRO users can restore ALL data (effectively unlimited).
  /// The value is set high (3650 = ~10 years) as a practical "forever".
  static const int proRestoreDays = 3650;

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

  /// Razorpay key (public, safe for client) — loaded from .env.
  static String get razorpayKeyId => dotenv.env['RAZORPAY_KEY_ID'] ?? '';
}
