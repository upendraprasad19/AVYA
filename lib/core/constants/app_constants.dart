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

  // ── UI hints / placeholders (audit 2026-05-20 / C9) ────────────
  /// Canonical referral code placeholder shown in input fields. Centralized
  /// so a brand or format change updates 5 callsites at once. Match the
  /// real referral code grammar: `AVYA-` prefix + 8 alphanumerics.
  static const String referralCodeHint = 'AVYA-XXXXXXXX';

  // ── Subscription ──────────────────────────────────────────

  static const int monthlyPriceInr = 349;
  static const int yearlyPriceInr = 2999;

  // ── PRO Feature Keys ──────────────────────────────────────

  static const String featurePhases2To12 = 'phases_2_to_12';
  // audit-2026-05-16 E.8 — `featureActiveWorkoutMode` constant deleted.
  // Active workout has been free since Test #2 Q6 (2026-04-25) and had 0
  // `gate()` callsites. The constant remained @Deprecated for back-compat
  // but accumulated zero references over 3 weeks of testing. Removed cleanly.
  static const String featureAiCoachUnlimited = 'ai_coach_unlimited';
  // `featureReasoningTab` removed 2026-04-18 — Chat/Reasoning toggle
  // deleted from UI, single AI coach backend, no separate reasoning gate.
  static const String featureWeeklyAiReport = 'weekly_ai_report';
  // ⑥ 6 B-pass P2 — `featureReadinessTrends` feature-KEY constant removed. The
  // W3.7 readiness trend gates via a synchronous `ref.watch(subscriptionInfoProvider)
  // .isPro` teaser in reports_screen, NOT a server-verified `gate()` — so the key
  // had 0 gate() callsites (dead), matching the E.8 featureActiveWorkoutMode /
  // featureVoiceNotes removals. Re-add a key only if it gains a real gate() site.
  static const String featureProgressPhotos = 'progress_photos';
  static const String featureScanMealPro = 'scan_meal_pro';         // 10/day PRO (free=3/day)
  static const String featureCartAuditorPro = 'cart_auditor_pro';   // 10/day PRO (free=1/day)
  static const String featureAiTextLogPro = 'ai_text_log_pro';      // Unlimited PRO (free=10/day)
  // audit-2026-05-16 E.8 — `featureVoiceNotes` constant deleted.
  // Voice has been free since Test #9 F13 (zero on-device compute cost via
  // speech_to_text) and the constant had 0 `gate()` callsites.
  static const String featureMorningAlertPro = 'morning_alert_pro'; // AI-personalised (free=generic)
  static const String featurePredictionMonthly = 'prediction_monthly'; // Monthly card (free=once)
  static const String featureAdaptiveWorkouts = 'adaptive_workouts'; // Phase 2
  // audit-2026-05-16 E.8 — `featureDietPlanPdf` constant deleted.
  // CLAUDE.md §14 confirms diet-plan PDF export is FREE. 0 `gate()` callsites.
  static const String featurePhotoAnalysis = 'photo_analysis';     // Photo in chat (PRO)

  // ── Free Tier Limits ──────────────────────────────────────

  /// Maximum AI coach messages per day for free users.
  /// Must match FREE_DAILY_LIMIT in ai-proxy Edge Function (10).
  static const int freeAiMessagesPerDay = 10;

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

  // ── Activity Goals ────────────────────────────────────────
  /// Default daily step goal shown on the Home steps card + Today's Workout
  /// card. Centralized 2026-06-07 (in-sync sweep) so the figure is a one-line
  /// edit, not a 4-site literal sweep.
  static const int defaultDailyStepGoal = 10000;

  // ── Terms & Privacy ───────────────────────────────────────

  /// Current ToS/Privacy-Policy version. Bumping this re-prompts every user
  /// via [TermsModal] on next launch (Hive flag is stamped with the version
  /// at accept time; mismatch = re-show). Also persisted on the Supabase
  /// `users.terms_version` column for audit.
  static const String termsVersion = 'v1';

  /// App version (pubspec `version:` field). Audit 2026-05-12 P2-A — fixes the
  /// hardcoded `0.0.0+release` placeholder in error telemetry so client_errors
  /// rows can be correlated to specific APK builds.
  ///
  /// IMPORTANT: Keep this in sync with `pubspec.yaml` `version:` field.
  ///
  /// audit-2026-05-16 F10.1 — was hardcoded `'1.0.0+23'` since Test #11 but
  /// APKs +24/+25/+26 shipped without bumping the constant. 358 telemetry
  /// rows in the last 30 days were mis-labelled. Bumped to `+27` for the
  /// audit ship; permanent gate `scripts/check_app_version_matches_pubspec.dart`
  /// added so the next regression is caught pre-build.
  static const String appVersion = '1.0.0+37';

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
