part of 'screen.dart';

extension _ProfileContent on _ProfileScreenState {

  Widget _buildProfileContent(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final stats = ref.watch(userStatsProvider);
    final subInfo = ref.watch(subscriptionInfoProvider);
    final biometric = ref.watch(biometricProvider);
    final usageWeeks = ref.watch(usageWeeksProvider);
    final firstReportViewed = ref.watch(firstReportViewedProvider);

    final name = profile['full_name'] as String? ?? 'User';
    final weightKg = (profile['current_weight_kg'] as num?)?.toDouble();
    final targetKg = (profile['target_weight_kg'] as num?)?.toDouble();
    final heightCm = (profile['height_cm'] as num?)?.toDouble();
    final bodyFatPct = (profile['body_fat_percent'] as num?)?.toDouble();

    final experience = profile['fitness_experience'] as String? ?? '';
    final expLabel = experience.isNotEmpty
        ? ' \u00B7 ${experience[0].toUpperCase()}${experience.substring(1)}'
        : '';
    final subtitle =
        'Phase ${stats.currentPhase} \u00B7 Week ${stats.currentWeek} \u00B7 ${_formatGoal(stats.primaryGoal)}$expLabel';

    // BMI calculation
    double? bmi;
    if (weightKg != null && heightCm != null && heightCm > 0) {
      bmi = weightKg / ((heightCm / 100) * (heightCm / 100));
    }

    // Nutrition targets
    //
    // Source of truth (CLAUDE.md §15): `macroTargetsProvider` is the ONE
    // reader for BMR / TDEE / calories / P / C / F across Home, Nutrition,
    // and Profile. It prefers the stored targets in the Hive profile map
    // (written at onboarding and on every Edit Profile save) and falls
    // back to `BmrCalculator.calculateTargets` only when they're missing.
    //
    // Profile used to call BmrCalculator directly here, which diverged
    // from Home/Nutrition whenever `activity_level` was stale or defaulted
    // to 'moderate' — observed 2026-04-17 with icanbefitter@gmail.com.
    final macros = ref.watch(macroTargetsProvider);
    final Map<String, double>? nutritionTargets = (macros['calories'] ?? 0) > 0
        ? {
            'tdee': macros['tdee'] ?? 0,
            'calories': macros['calories'] ?? 0,
            'protein': macros['protein'] ?? 0,
          }
        : null;

    // Usage counts for free users
    final usageService = UsageCounterService.instance;
    final isPro = subInfo.isPro;

    // Enabled notifications count
    int enabledNotifCount = 0;
    for (final key in ['morning_checkin', 'workout_reminder', 'streak_alerts', 'weekly_recap', 'subscription_reminders']) {
      if (_getNotifEnabled(key)) enabledNotifCount++;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          const SyncBanner(),
          Expanded(
            child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Plan D D-9 — Profile uses ProfileIdentity (banner + 80dp
              // avatar overlap + name + EDIT button + gold rule) as its
              // letterhead. The floating DOSSIER · OFFICER eyebrow is
              // overlaid on the banner @ ~65% alpha inside ProfileIdentity.
              // No unified WardTabHeader.

              // 1. Profile identity with banner + avatar
              ProfileIdentity(
                name: name,
                subtitle: subtitle,
                avatarUrl: _addCacheBuster(profile['avatar_url'] as String?),
                bannerUrl: _addCacheBuster(profile['banner_url'] as String?),
                onReplaceAvatar: () async {
                  final outcome = await ref.read(userProfileProvider.notifier).uploadAvatar();
                  if (!context.mounted) return;
                  ref.invalidate(userProfileProvider);
                  if (outcome.result == UploadResult.cancelled) {
                    debugPrint('[ProfileScreen] Avatar upload cancelled: ${outcome.errorMessage}');
                    if (outcome.errorMessage != null && outcome.errorMessage!.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(outcome.errorMessage!, style: AppTypography.bodyM),
                        backgroundColor: AppColors.card,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 3),
                      ));
                    }
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                      outcome.result == UploadResult.success
                          ? 'Profile photo updated'
                          : 'Upload failed: ${outcome.errorMessage ?? "Unknown error"}',
                      style: AppTypography.bodyM.copyWith(fontWeight: FontWeight.w500),
                    ),
                    backgroundColor: outcome.result == UploadResult.success
                        ? AppColors.successTint
                        : AppColors.errorTint,
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                onReplaceBanner: () async {
                  final outcome = await ref.read(userProfileProvider.notifier).uploadBanner();
                  if (!context.mounted) return;
                  ref.invalidate(userProfileProvider);
                  if (outcome.result == UploadResult.cancelled) {
                    debugPrint('[ProfileScreen] Banner upload cancelled: ${outcome.errorMessage}');
                    if (outcome.errorMessage != null && outcome.errorMessage!.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(outcome.errorMessage!, style: AppTypography.bodyM),
                        backgroundColor: AppColors.card,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 3),
                      ));
                    }
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                      outcome.result == UploadResult.success
                          ? 'Banner updated'
                          : 'Upload failed: ${outcome.errorMessage ?? "Unknown error"}',
                      style: AppTypography.bodyM.copyWith(fontWeight: FontWeight.w500),
                    ),
                    backgroundColor: outcome.result == UploadResult.success
                        ? AppColors.successTint
                        : AppColors.errorTint,
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                // Plan D D-7: edit moved to SETTINGS first row (D-9).
                // null hides the top EDIT PROFILE button inside ProfileIdentity.
                onTapEdit: null,
                isPro: isPro,
                // Theme B · Test #8 — compact rank chip in banner-overlap row.
                rankCode: RankService.instance.getCurrentRank().entry.code,
                rankShortCode: RankService.instance
                    .getCurrentRank()
                    .entry
                    .shortName
                    .toUpperCase(),
                onTapRank: () => RankServiceRecordSheet.show(context),
                onTapPremium: () {
                  // Bug #14 — PRO users see subscription detail; free users
                  // get the paywall sheet. Subscription detail reuses the
                  // existing _buildSubscriptionSection inside a bottom sheet
                  // so we don't have to maintain two upgrade surfaces.
                  if (isPro) {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: AppColors.card,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(22)),
                      ),
                      builder: (_) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.border,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildSubscriptionSection(
                                  subInfo, isPro, usageService),
                            ],
                          ),
                        ),
                      ),
                    );
                  } else {
                    showPaywallSheet(context, feature: 'PRO Upgrade');
                  }
                },
              ),
              const SizedBox(height: 14),

              // Theme B · Test #8 — rank chip moved into ProfileIdentity's
              // banner-overlap row. Tap opens RankServiceRecordSheet
              // (replaces the previous WardRankPill inline accordion).

              // Profile completeness (shows until 100%) — stays OUTSIDE the
              // flush stack below; keeps its own WardCard styling.
              const ProfileCompletenessCard(),
              const SizedBox(height: 8),

              // Theme C · Test #8 — Flush card stack.
              //
              // Five cards rendered as a single visual block: outer 6-dp
              // corners (top of Daily Goals, bottom of My Targets / Body
              // Stats), square inner corners, no inter-card gaps, shared
              // 1-px border rail. Order: Daily Goals → SlimAchievements →
              // Journey → Body Stats → My Targets (My Targets dropped if
              // nutritionTargets is null, in which case Body Stats holds
              // the bottom corner).
              _buildFlushCard(
                _buildDailyCompletionInner(stats),
                pos: _FlushPos.first,
              ),
              _buildFlushCard(
                const SlimAchievementsCard(compact: true),
                pos: _FlushPos.middle,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              _buildFlushCard(
                _buildJourneyTimelineInner(
                  stats,
                  currentWeightKg: weightKg,
                  targetWeightKg: targetKg,
                  goal: stats.primaryGoal,
                ),
                pos: _FlushPos.middle,
              ),
              _buildFlushCard(
                _buildBodyStatsInner(weightKg, targetKg, bmi, bodyFatPct),
                pos: nutritionTargets == null
                    ? _FlushPos.last
                    : _FlushPos.middle,
              ),
              if (nutritionTargets != null)
                _buildFlushCard(
                  _buildNutritionTargetsInner(
                    nutritionTargets,
                    currentKg: weightKg,
                    targetKg: targetKg,
                    goal: stats.primaryGoal,
                    pacePreference: profile['pace_preference'] is String
                        ? profile['pace_preference'] as String
                        : 'balanced',
                  ),
                  pos: _FlushPos.last,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  onTap: _nutritionTargetsOnTap(
                    currentKg: weightKg,
                    targetKg: targetKg,
                    goal: stats.primaryGoal,
                    pacePreference: profile['pace_preference'] is String
                        ? profile['pace_preference'] as String
                        : 'balanced',
                  ),
                ),
              const SizedBox(height: 8),

              // Reports now hosts BOTH the weekly AI report AND progress
              // photos (moved here from SHARE & GROW per 2026-04-18 user
              // feedback). Progress Photos is still PRO-gated at tap.
              //
              // Plan D D-10: Predictions moved into REPORTS as the first
              // REPORTS \u2014 WeeklyReportCard on top, then a single card for
              // the 3 list rows (Predictions / Progress Comparison / Progress
              // Photos). Consolidating from 3 separate _buildCard calls
              // removes the triple gap and matches the SETTINGS / SHARE &
              // GROW single-card pattern.
              const SectionHeader('REPORTS'),
              WeeklyReportCard(
                isPro: subInfo.isPro,
                usageWeeks: usageWeeks,
                hasFirstReport: firstReportViewed,
                onViewReport: () {
                  if (!firstReportViewed) {
                    ref.read(firstReportViewedProvider.notifier).markViewed();
                  }
                  context.go('/profile/reports');
                },
                onUpgradeTap: () {
                  SubscriptionService.instance.gate(
                    AppConstants.featureWeeklyAiReport,
                    onPro: () => context.go('/profile/reports'),
                    onFree: () => showPaywallSheet(context, feature: 'Weekly AI Report'),
                  );
                },
              ),
              const SizedBox(height: 6),
              Builder(builder: (ctx) {
                final prediction = ref.watch(predictionProvider);
                return _buildCard([
                  ProfileRow(
                    icon: Icons.auto_awesome_outlined,
                    iconColor: AppColors.accent,
                    title: 'Predictions',
                    subtitle: _truncatedPredictionPreview(prediction),
                    trailing: const ProfileRowChevron(),
                    showBorder: true,
                    onTap: () => _showPredictionBottomSheet(ctx),
                  ),
                  ProfileRow(
                    icon: Icons.compare_arrows_outlined,
                    title: 'Progress Comparison',
                    subtitle: 'Then vs now \u2014 starting stats and milestones',
                    trailing: const ProfileRowChevron(),
                    showBorder: true,
                    onTap: () => context.go('/profile/progress-comparison'),
                  ),
                  ProfileRow(
                    icon: Icons.photo_library_outlined,
                    title: 'Progress Photos',
                    subtitle: subInfo.isPro
                        ? 'Track your transformation visually'
                        : 'PRO \u2014 visual progress timeline',
                    trailing: const ProfileRowChevron(),
                    showBorder: false,
                    onTap: () => SubscriptionService.instance.gate(
                      AppConstants.featureProgressPhotos,
                      onPro: () => context.go('/profile/progress-photos'),
                      onFree: () =>
                          showPaywallSheet(context, feature: 'Progress Photos'),
                    ),
                  ),
                ]);
              }),
              const SizedBox(height: 8),

              // #4b Invite Friends (referral)
              //
              // Progress Photos moved up to REPORTS. Health Sync row added
              // into SETTINGS (see below) — its standalone section was
              // removed.
              const SectionHeader('SHARE & GROW'),
              _buildCard([
                // Q4: Apply Referral Code — visible only within 7-day signup
                // window AND when the user hasn't redeemed a referral yet.
                // Tap opens ApplyReferralSheet; on success the provider is
                // invalidated so the tile disappears automatically.
                ...ref.watch(referralEligibilityProvider).when(
                  data: (state) {
                    if (!state.isEligible) return const <Widget>[];
                    return <Widget>[
                      ProfileRow(
                        icon: Icons.card_giftcard_outlined,
                        iconBgColor: AppColors.accentSoft,
                        iconColor: AppColors.accent,
                        title: 'Apply Referral Code',
                        subtitle: '7 days of PRO when you apply a code',
                        titleSuffix: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${state.daysRemaining}D LEFT',
                            style: AppTypography.monoXs.copyWith(
                              letterSpacing: 0.8,
                              color: AppColors.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        trailing: const ProfileRowChevron(),
                        onTap: () async {
                          final ok = await ApplyReferralSheet.show(context);
                          if (ok == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '7 days of PRO unlocked!',
                                  style: AppTypography.body.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                backgroundColor: AppColors.card,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                            ref.invalidate(referralEligibilityProvider);
                          }
                        },
                      ),
                    ];
                  },
                  loading: () => const <Widget>[],
                  error: (e, st) => const <Widget>[],
                ),
                ProfileRow(
                  icon: Icons.card_giftcard,
                  title: 'Invite Friends',
                  subtitle: 'Both get 7 days PRO free',
                  trailing: const ProfileRowChevron(),
                  onTap: () => InviteFriendsSheet.show(context),
                ),
                // S1 (2026-04-24) — the pre-APK-1-batch split of
                // "Review Community Items" (bottom sheet) and
                // "My Submissions" (screen) confused testers who kept
                // tapping one expecting the other. Collapsed into a
                // single Submissions row that opens a tabbed screen
                // with both views.
                ProfileRow(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Submissions',
                  subtitle: 'Your submissions + vote on community items',
                  trailing: const ProfileRowChevron(),
                  onTap: () => context.go('/profile/submissions'),
                ),
                // AH.7 — Rate App tile completes the SHARE & GROW block
                // (JSX spec lines 331–338 + user ask for explicit Rate App
                // row). Launches the Play Store listing via externalApplication
                // so the Play Store app intercepts on-device; users without
                // it land on the web listing.
                ProfileRow(
                  icon: Icons.star_outline,
                  title: 'Rate App',
                  subtitle: 'Tell the Play Store what you think',
                  trailing: const ProfileRowChevron(),
                  showBorder: false,
                  onTap: () => _launchUrl(
                    'https://play.google.com/store/apps/details?id=com.icanbefitter.icanbefitter',
                  ),
                ),
              ]),
              const SizedBox(height: 8),

              // #5 Notifications (consolidated — just a row linking to settings screen)
              const SectionHeader('SETTINGS'),
              _buildCard([
                // Plan D D-9: Edit Profile moved here from top-of-Profile
                // (replaced by WardRankPill in D-7).
                ProfileRow(
                  icon: Icons.person_outline,
                  title: 'Edit Profile',
                  subtitle: 'Goal, stats, preferences',
                  trailing: const ProfileRowChevron(),
                  onTap: () => context.go('/profile/edit'),
                ),
                ProfileRow(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: '$enabledNotifCount/5 enabled',
                  trailing: const ProfileRowChevron(),
                  onTap: () => context.push(
                    '/profile/notification-settings',
                    extra: {
                      'notifPrefs': _notifPrefs,
                      'isPro': subInfo.isPro,
                      'onSave': (Map<String, dynamic> prefs) {
                        setState(() => _notifPrefs = prefs);
                        _saveNotificationPreferences();
                      },
                    },
                  ),
                ),
                ProfileRow(
                  icon: Icons.tune,
                  title: 'Units',
                  trailing: UnitsSegmentedControl(
                    isMetric: _isMetric,
                    onChanged: (metric) {
                      setState(() => _isMetric = metric);
                      UserRepository.instance.setUnitsMetric(metric);
                    },
                  ),
                ),
                // Health Sync moved here from its own top-level section
                // (2026-04-18 user feedback). Tap opens a sheet with the
                // full BiometricSyncCard (steps / sleep / toggle / manual
                // sleep log). Keeping the rich widget live instead of
                // re-implementing it as individual rows.
                ProfileRow(
                  icon: Icons.favorite_outline,
                  title: 'Health Sync',
                  subtitle: _buildHealthSyncSubtitle(biometric),
                  trailing: const ProfileRowChevron(),
                  onTap: () => _showHealthSyncSheet(biometric),
                ),
                ProfileRow(
                  icon: Icons.shield_outlined,
                  title: 'Privacy & Permissions',
                  trailing: const ProfileRowChevron(),
                  onTap: () => _showPrivacyDialog(),
                ),
                // #10 Export Data
                ProfileRow(
                  icon: Icons.download_outlined,
                  title: 'Export My Data',
                  subtitle: 'Download all your data as JSON',
                  trailing: const ProfileRowChevron(),
                  showBorder: false,
                  onTap: () => _exportData(),
                ),
              ]),
              const SizedBox(height: 12),

              const SectionHeader('AVYA'),
              _buildCard([
                ProfileRow(
                  icon: Icons.military_tech_outlined,
                  iconColor: AppColors.accent,
                  title: "AVYA's Promise",
                  subtitle: 'Our philosophy — read before you train',
                  trailing: const ProfileRowChevron(),
                  showBorder: true,
                  onTap: () => context.push('/avya/promise'),
                ),
                ProfileRow(
                  icon: Icons.language_outlined,
                  title: 'icanbefitter.com',
                  subtitle: 'Visit the website',
                  trailing: const ProfileRowChevron(),
                  showBorder: true,
                  onTap: () => _launchUrl('https://icanbefitter.com'),
                ),
                ProfileRow(
                  icon: Icons.camera_alt_outlined,
                  title: '@icanbefitter',
                  subtitle: 'Daily wins on Instagram',
                  trailing: const ProfileRowChevron(),
                  showBorder: false,
                  onTap: _openInstagram,
                ),
              ]),
              const SizedBox(height: 12),

              // Bug #14 — Subscription moved to the bottom (full upsell banner
              // in the closing-pitch position). Premium pill at the top is the
              // primary discoverability surface; this card is the closer.
              const SectionHeader('SUBSCRIPTION'),
              _buildSubscriptionSection(subInfo, isPro, usageService),
              const SizedBox(height: 8),

              // Bug #21 — Achievements are now rendered as the compact inline
              // row inside ProfileIdentity. Full grid opens via its chevron.

              // Sign Out — sharp 2-px bad-tinted slab
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: WardButton(
                  label: 'Sign Out',
                  variant: WardButtonVariant.danger,
                  onPressed: () => _showSignOutDialog(),
                ),
              ),

              // #9 Delete Account — hidden behind expandable danger zone
              const SizedBox(height: 8),
              _buildDangerZone(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
          ),
        ],
      ),
    );
  }
}
