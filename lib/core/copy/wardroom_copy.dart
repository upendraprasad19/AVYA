/// Single source of truth for literal Wardroom-handoff copy strings.
///
/// Every eyebrow, hero title, CTA, chip label, empty state, and
/// microcopy phrase from
/// `Knowledgebase/Avya App redesign/design_handoff_wardroom/src/screens/*.jsx`
/// is mirrored here verbatim. Screens import from this file only; never
/// hardcode handoff copy in widgets.
///
/// Editing a string here is a one-file deploy to every screen using it.
/// QA can diff this file against the handoff jsx to audit copy drift.
///
/// Organised per screen in the order they appear in the handoff.
class WardroomCopy {
  WardroomCopy._();

  // ── DAILY (Home) ───────────────────────────────────────────────────────
  /// Header eyebrow above the display name.
  static const dailyWelcomeEyebrow = 'WELCOME BACK,';

  /// Streak warning banner — `{N}` replaced with streak day count.
  static const dailyStreakAtRiskTitle = '{n}-day streak at risk';

  /// Streak warning banner meta line — `{hours}` and `{freezes}` filled
  /// at render time.
  static const dailyStreakAtRiskMeta =
      '{hours}H LEFT · {freezes} FREEZE AVAILABLE';

  /// Streak warning banner CTA.
  static const dailyStreakAtRiskCta = 'Train Now';

  /// Section eyebrow above the workout + macros grid.
  static const dailyTodayEyebrow = 'TODAY';

  /// Hero workout card meta above the title.
  static const dailyWorkoutMetaTemplate = '{workout} · {mode}';

  /// Hero workout card CTA.
  static const dailyStartCta = '▸ Start';

  /// Right column stat tile labels.
  static const dailyFuelLabel = 'FUEL';
  static const dailyProteinLabel = 'PROTEIN';
  static const dailyStepsLabel = 'STEPS';

  /// Quick action labels.
  static const dailyQuickWorkout = 'WORKOUT';
  static const dailyQuickMeals = 'MEALS';
  static const dailyQuickWater = 'WATER';
  static const dailyQuickWeight = 'WEIGHT';

  /// AI Coach insights eyebrow — leading green dot rendered by widget.
  static const dailyCoachInsightsEyebrow = 'AI COACH · INSIGHTS';

  /// Inline "QUICK WINS" nested inset label.
  static const dailyQuickWinsLabel = 'QUICK WINS';

  /// Weight trend section eyebrow.
  static const dailyWeightTrendEyebrow = 'WEIGHT TREND';

  /// Weight trend period tabs (left-to-right, first active).
  static const dailyWeightTrendPeriods = ['7D', '30D', '3M', '1Y', 'ALL'];

  /// Personal records eyebrow.
  static const dailyPrsEyebrow = 'PERSONAL RECORDS';

  /// Recent logs eyebrow.
  static const dailyRecentLogsEyebrow = 'RECENT LOGS';

  /// Daily quote attribution prefix (the quote itself is data-driven).
  static const dailyQuoteAttributionPrefix = '— ';

  // ── TRAIN (Workout Plan) ───────────────────────────────────────────────
  /// Plan header eyebrow template.
  static const trainPhaseEyebrowTemplate = 'PHASE {n} · {name}';

  /// Plan header title template.
  static const trainWeekTitleTemplate = 'Week {n} of {total}';

  /// Plan header subtitle template.
  static const trainWeekSubtitleTemplate = '{done}/{total} done';

  /// Today's Workout section eyebrow.
  static const trainTodayWorkoutEyebrow = "TODAY'S WORKOUT";

  /// Today's Workout CTA.
  static const trainStartWorkoutCta = '▸ START WORKOUT →';

  /// Week selector chip template (short form).
  static const trainWeekChipTemplate = 'W{n}';

  /// Day row status chips.
  static const trainDayDoneChip = '✓ DONE';
  static const trainDayTodayChip = '● TODAY';
  static const trainDayRestLabel = 'Rest';

  /// Phase unlock callout.
  static const trainPhaseUnlockSealLabel = 'PHASE {n}';
  static const trainPhaseUnlockSealDate = 'UNLOCK';
  static const trainPhaseUnlockTitleTemplate = 'Phase {n} unlocks in {days} days';
  static const trainPhaseUnlockMeta =
      'CAPACITY · 6 WEEKS · RECALIBRATE AVAILABLE';

  /// PR grid eyebrow.
  static const trainPrsEyebrow = 'YOUR PRs';

  /// PR tile labels.
  static const trainPrTotalVolume = 'TOTAL VOLUME';
  static const trainPrWorkouts = 'WORKOUTS';
  static const trainPrStreak = 'STREAK';
  static const trainPrAvgSession = 'AVG SESSION';

  /// Templates section eyebrow.
  static const trainTemplatesEyebrow = 'MY TEMPLATES';

  /// Create custom exercise CTA.
  static const trainCreateCustomCta = '+ Create custom exercise';

  // ── ACTIVE WORKOUT ─────────────────────────────────────────────────────
  /// End-session button label.
  static const activeEndLabel = 'END ×';

  /// Session header template.
  static const activeSessionTemplate = 'SESSION · {name}';

  /// Notes right button label.
  static const activeNotesLabel = 'NOTES';

  /// Exercise header template (1-based).
  static const activeExerciseHeaderTemplate = 'EXERCISE {n} / {total} · {muscle}';

  /// Weight / reps column labels.
  static const activeWeightLabel = 'WEIGHT · KG';
  static const activeRepsLabel = 'REPS';

  /// Sticky bottom rest label.
  static const activeRestLabel = 'REST';

  /// Sticky bottom log-set CTA.
  static const activeLogSetCta = 'LOG SET ✓';

  // ── NUTRITION (Galley) ─────────────────────────────────────────────────
  /// Letterhead eyebrow template — "NUTRITION · TUE 14 APR".
  /// Weekday and date filled at render.
  static const nutritionLetterheadEyebrowTemplate = 'GALLEY · {weekday} {day} {month}';

  /// Letterhead title.
  static const nutritionLetterheadTitle = 'Fueling the plan';

  /// Trailing meals chip template — "3/4 MEALS".
  static const nutritionMealsChipTemplate = '{done}/{total} MEALS';

  /// Calorie-remaining column label.
  static const nutritionRemainingLabel = 'REMAINING';

  /// On-track status chip.
  static const nutritionOnTrackChip = 'ON TRACK';

  /// Macros card eyebrow.
  static const nutritionMacrosEyebrow = 'MACROS';
  static const nutritionProteinLabel = 'PROTEIN';
  static const nutritionCarbsLabel = 'CARBS';
  static const nutritionFatLabel = 'FAT';

  /// Hydration eyebrow and CTA.
  static const nutritionHydrationEyebrow = 'HYDRATION · WATER';
  static const nutritionHydrationMetaTemplate = '{litres} L / {goal} L · {left} LEFT';
  static const nutritionAddGlassCta = '+ GLASS';

  /// Meal slot labels.
  static const nutritionBreakfast = 'BREAKFAST';
  static const nutritionLunch = 'LUNCH';
  static const nutritionSnack = 'SNACK';
  static const nutritionDinner = 'DINNER';
  static const nutritionLogCta = '+ LOG';

  /// AI Meal Coach card.
  static const nutritionAiCoachEyebrow = 'AI MEAL COACH';
  static const nutritionAiSuggestMealsCta = 'SUGGEST MEALS';
  static const nutritionAiDismissCta = 'DISMISS';

  /// From Your Diet Plan card.
  static const nutritionDietPlanEyebrow = 'FROM YOUR DIET PLAN';
  static const nutritionDietPlanViewCta = 'VIEW PLAN →';
  static const nutritionDietPlanMetaTemplate =
      'PHASE {phase} · WEEK {week} · DAY {day}';

  // ── COACH (Dispatch) ───────────────────────────────────────────────────
  /// Dispatch letterhead eyebrow.
  static const coachDispatchEyebrow = 'YOUR AI COACH · 24/7';

  /// Dispatch letterhead title template — "Good afternoon, {name}."
  static const coachGreetingTemplate = 'Good {timeOfDay}, {name}.';

  /// Dispatch context subtitle.
  static const coachContextLine =
      'Watching · sleep, strength, recovery · last 14 days';

  /// Today's insight eyebrow.
  static const coachTodayInsightEyebrow = "TODAY'S INSIGHT";

  /// Today's insight CTAs.
  static const coachInsightRestCta = 'REST TODAY ✓';
  static const coachInsightWhyCta = 'WHY?';

  /// Suggested actions eyebrow + new count template.
  static const coachSuggestedEyebrow = 'SUGGESTED ACTIONS';
  static const coachSuggestedNewTemplate = '{n} NEW';

  /// Category sidebar labels (vertical).
  static const coachCategoryTraining = 'TRAINING';
  static const coachCategorySleep = 'SLEEP';
  static const coachCategoryMeal = 'MEAL';
  static const coachCategoryCoach = 'COACH';

  /// Suggested action CTAs.
  static const coachApplyCta = 'APPLY →';
  static const coachSkipCta = 'SKIP';

  /// Conversation eyebrow.
  static const coachConversationEyebrow = 'CONVERSATION';

  /// Coach bubble label.
  static const coachBubbleLabel = 'COACH';

  /// Composer placeholder + send button.
  static const coachComposerPlaceholder = 'Ask your coach…';
  static const coachSendCta = 'SEND';

  /// Patterns section eyebrow.
  static const coachPatternsEyebrow = "PATTERNS I'VE NOTICED";

  /// Weekly deep analysis callout.
  static const coachDeepAnalysisTitle = 'Weekly Deep Analysis';
  static const coachDeepAnalysisMetaTemplate = 'READY · {weekday} {day} {month}';
  static const coachDeepAnalysisOpenCta = 'OPEN →';

  // ── PROFILE ────────────────────────────────────────────────────────────
  /// Identity subtitle template — "PHASE 1 · WEEK 4 · LOSE FAT · INTERMEDIATE"
  static const profileIdentitySubtitleTemplate =
      'PHASE {phase} · WEEK {week} · {goal} · {experience}';

  /// Edit pill label.
  static const profileEditPill = 'EDIT';

  /// Profile completeness label.
  static const profileCompletenessLabel = 'PROFILE COMPLETENESS';

  /// Daily goals label.
  static const profileDailyGoalsLabel = 'DAILY GOALS';

  /// Body stats tile labels.
  static const profileBodyWeight = 'WEIGHT';
  static const profileBodyTarget = 'TARGET';
  static const profileBodyBmi = 'BMI';
  static const profileBodyBodyFat = 'BODY FAT';

  /// Journey card.
  static const profileJourneyTitleTemplate = 'Phase {n} — {name}';
  static const profileJourneyWeekTemplate = 'WEEK {n} / {total}';

  /// My Targets tile labels.
  static const profileTargetsTdee = 'TDEE';
  static const profileTargetsCalories = 'CALORIES';
  static const profileTargetsProtein = 'PROTEIN';

  /// Forecast / Prediction card.
  static const profileForecastChip = 'FORECAST';
  static const profileForecastRefreshCta = '⟲ REFRESH';

  /// Reports row.
  static const profileReportsTitle = 'Weekly Report';
  static const profileReportsReadyTemplate = 'WEEK {n} · READY SUNDAY';

  /// Health sync row.
  static const profileHealthSyncTitle = 'Health Sync';
  static const profileHealthSyncedTemplate = '● SYNCED · {time} AGO';

  /// Share & Grow row labels.
  static const profileShareInvite = 'Invite Friends';
  static const profileShareReview = 'Review Community Items';

  /// Settings row labels.
  static const profileSettingsNotifications = 'Notifications';
  static const profileSettingsUnits = 'Units';
  static const profileSettingsPrivacy = 'Privacy & Permissions';
  static const profileSettingsExport = 'Export My Data';

  /// Subscription card.
  static const profileSubscriptionTitle = "Officer's Commission";
  static const profileSubscriptionRenewsTemplate = 'RENEWS {day} {month} {year}';
  static const profileSubscriptionManageCta = 'MANAGE SUBSCRIPTION →';

  /// Sign-out + danger.
  static const profileSignOut = 'Sign Out';
  static const profileDangerZone = 'Danger Zone';

  // ── ONBOARDING ─────────────────────────────────────────────────────────
  /// Welcome screen.
  static const onboardingWelcomeEyebrow = 'AVYA';
  static const onboardingEstLabel = 'EST · 2026';
  static const onboardingProspectusEyebrow = 'PROSPECTUS';
  static const onboardingWelcomeHeadline = 'Train like\nsomeone serious\nis watching.';
  static const onboardingWelcomeEmphasis = 'serious';
  static const onboardingBeginCta = 'BEGIN ENLISTMENT →';
  static const onboardingSignInPrompt = 'Already a member? SIGN IN';

  /// Progress indicator template — "01 · 03".
  static const onboardingProgressTemplate = '{step} · {total}';

  /// Goal screen.
  static const onboardingGoalEyebrow = 'GOAL';
  static const onboardingQ1Label = 'QUESTION I';
  static const onboardingQ1Title = 'What are you here to do?';
  static const onboardingQ1Emphasis = 'do?';
  static const onboardingQ1Helper =
      'One answer shapes everything: your plan, targets, and coaching tone.';

  /// Goal options (key + title + subtitle).
  static const onboardingGoalRecomp = [
    'A',
    'Recompose',
    'Lose fat, build lean mass at the same time.',
  ];
  static const onboardingGoalBuild = [
    'B',
    'Build muscle',
    'Size and strength — surplus-driven hypertrophy.',
  ];
  static const onboardingGoalCut = [
    'C',
    'Cut',
    'Aggressive fat loss while preserving muscle.',
  ];
  static const onboardingGoalMaintain = [
    'D',
    'Maintain',
    'Hold present composition — consistency & habit.',
  ];
  static const onboardingGoalPerform = [
    'E',
    'Perform',
    'Sport-first: strength, speed, endurance ceilings.',
  ];

  static const onboardingBackCta = 'BACK';
  static const onboardingContinueCta = 'CONTINUE →';

  /// Stats screen.
  static const onboardingStatsEyebrow = 'BASELINE';
  static const onboardingQ2Label = 'QUESTION II';
  static const onboardingQ2Title = 'The baseline.';
  static const onboardingQ2Emphasis = 'baseline.';
  static const onboardingQ2Helper =
      'Measurements today. We re-calibrate every phase.';
  static const onboardingSexMale = 'MALE';
  static const onboardingSexFemale = 'FEMALE';
  static const onboardingSexOther = 'OTHER';
  static const onboardingStatWeight = 'WEIGHT · KG';
  static const onboardingStatHeight = 'HEIGHT · CM';
  static const onboardingStatAge = 'AGE · YRS';
  static const onboardingStatBodyFat = 'BODY FAT · %';
  static const onboardingActivitySedentary = 'SEDENTARY';
  static const onboardingActivityLight = 'LIGHT';
  static const onboardingActivityModerate = 'MODERATE';
  static const onboardingActivityHigh = 'HIGH';
  static const onboardingCalibrateCta = 'CALIBRATE PLAN →';

  /// Plan screen.
  static const onboardingPlanEyebrow = 'YOUR CAMPAIGN';
  static const onboardingPlanTitleTemplate = '12-week {goal} protocol.';
  static const onboardingReportCta = 'REPORT FOR DUTY →';
  static const onboardingPhaseITitle = 'Foundation';
  static const onboardingPhaseIWeeks = 'WEEKS 1–4';
  static const onboardingPhaseIIITitle = 'Capacity';
  static const onboardingPhaseIIWeeks = 'WEEKS 5–8';
  static const onboardingPhaseIIITitle2 = 'Consolidation';
  static const onboardingPhaseIIIWeeks = 'WEEKS 9–12';

  // ── UTILITY ────────────────────────────────────────────────────────────
  /// Settings screen.
  static const settingsEyebrow = 'SETTINGS · AVYA';
  static const settingsTitle = 'Under the hood';
  static const settingsProBadge = 'PRO';
  static const settingsSubTitle = "Officer's Commission";
  static const settingsSubStatusTemplate =
      'ACTIVE · RENEWS {day} {month} · {price}';
  static const settingsManageCta = 'MANAGE';
  static const settingsGroupAccount = 'ACCOUNT';
  static const settingsGroupPreferences = 'PREFERENCES';
  static const settingsGroupPlan = 'PLAN & COACHING';
  static const settingsGroupHealth = 'HEALTH SYNC';
  static const settingsGroupNotifications = 'NOTIFICATIONS';
  static const settingsGroupData = 'DATA & PRIVACY';
  static const settingsSignOut = 'Sign Out';
  static const settingsBuildTemplate = 'AVYA · v{version} · WARDROOM · BUILD {build}';

  /// Edit Profile screen.
  static const editProfileBackCta = '← BACK';
  static const editProfileTitle = 'Edit Profile';
  static const editProfileSaveCta = 'SAVE';
  static const editProfileChangePhoto = 'CHANGE PHOTO';
  static const editProfileFieldName = 'DISPLAY NAME';
  static const editProfileFieldHandle = 'HANDLE';
  static const editProfileFieldBio = 'BIO';
  static const editProfileFieldDob = 'DATE OF BIRTH';
  static const editProfileFieldLocation = 'LOCATION';
  static const editProfileBodyCompEyebrow = 'BODY COMPOSITION';
  static const editProfileResetCta = 'RESET TO DEFAULTS';

  /// Weekly Report screen.
  static const reportBackCta = '← BACK';
  static const reportShareCta = 'SHARE';
  static const reportSealLabel = 'REPORT';
  static const reportSealDateTemplate = 'W{n}';
  static const reportDispatchEyebrowTemplate = 'WEEKLY DISPATCH · {range}';
  static const reportSignatureTemplate = 'Signed, Coach · auto-generated {day} {time}';
  static const reportTopWorkouts = 'WORKOUTS';
  static const reportTopVolume = 'VOLUME';
  static const reportTopStreak = 'STREAK';
  static const reportSessionLogEyebrow = 'SESSION LOG';
  static const reportCoachNoteEyebrow = "COACH'S NOTE";
  static const reportTrendsEyebrow = 'TRENDS';
  static const reportTrendWeight = 'WEIGHT';
  static const reportTrendSleep = 'SLEEP AVG';
  static const reportTrendVolume = 'VOLUME';
  static const reportTrendEnergy = 'ENERGY';

  /// Notifications screen.
  static const notificationsEyebrow = 'INBOX';
  static const notificationsTitle = 'Notifications';
  static const notificationsMarkReadCta = 'MARK READ';
  static const notificationsFilterAll = 'ALL';
  static const notificationsFilterCoach = 'COACH';
  static const notificationsFilterPr = 'PR';
  static const notificationsFilterSystem = 'SYSTEM';
  static const notificationsGroupToday = 'TODAY';
  static const notificationsGroupYesterday = 'YESTERDAY';
  static const notificationsGroupEarlier = 'EARLIER THIS WEEK';
}
