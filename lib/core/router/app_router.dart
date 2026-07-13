import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/auth/screens/splash_screen.dart';
import 'package:icanbefitter/features/auth/screens/sign_in_screen.dart';
import 'package:icanbefitter/features/auth/screens/restoring_screen.dart';
import 'package:icanbefitter/features/onboarding/screens/mission_brief_screen.dart';
import 'package:icanbefitter/features/onboarding/screens/onboarding_chat_screen.dart';
import 'package:icanbefitter/features/onboarding/screens/welcome_screen.dart';
import 'package:icanbefitter/features/onboarding/screens/goal_screen.dart';
import 'package:icanbefitter/features/onboarding/screens/identity_screen.dart';
import 'package:icanbefitter/features/onboarding/screens/stats_screen.dart';
import 'package:icanbefitter/features/onboarding/screens/details_screen.dart';
import 'package:icanbefitter/features/onboarding/screens/plan_screen.dart';
import 'package:icanbefitter/features/home/screens/home_screen.dart';
import 'package:icanbefitter/features/train/screens/train/screen.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart';
import 'package:icanbefitter/features/train/screens/template_builder_screen.dart';
import 'package:icanbefitter/features/train/screens/graduation_screen.dart';
import 'package:icanbefitter/features/train/screens/phase_roadmap_screen.dart';
import 'package:icanbefitter/features/train/screens/preview_workout_screen.dart';
import 'package:icanbefitter/features/nutrition/screens/nutrition_screen.dart';
import 'package:icanbefitter/features/nutrition/screens/diet_plan_screen.dart';
import 'package:icanbefitter/features/ai_coach/screens/ai_coach/screen.dart';
import 'package:icanbefitter/features/ai_coach/screens/induction_screen.dart';
import 'package:icanbefitter/features/ai_coach/screens/muster_screen.dart';
import 'package:icanbefitter/features/profile/screens/profile/screen.dart';
import 'package:icanbefitter/features/profile/screens/edit_profile_screen.dart';
import 'package:icanbefitter/features/profile/screens/rank_ladder_screen.dart';
import 'package:icanbefitter/features/profile/screens/submissions_screen.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/features/profile/screens/progress_comparison_screen.dart';
import 'package:icanbefitter/features/profile/screens/progress_photos_screen.dart';
import 'package:icanbefitter/features/profile/screens/reports_screen.dart';
import 'package:icanbefitter/features/profile/screens/settings_screen.dart';
import 'package:icanbefitter/features/profile/screens/notifications_screen.dart';
import 'package:icanbefitter/features/profile/screens/notification_settings_screen.dart';
import 'package:icanbefitter/features/profile/screens/delete_account_screen.dart';
import 'package:icanbefitter/features/onboarding/screens/plan_generation_screen.dart';
import 'package:icanbefitter/shared/repositories/plan_generator.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
import 'package:icanbefitter/features/dev/dev_panel_screen.dart';
import 'package:icanbefitter/features/admin/screens/admin_dashboard_screen.dart';

/// GoRouter configuration with auth redirect logic.
///
/// Redirect rules:
///   - No session -> /sign-in
///   - Not onboarded -> /onboarding
///   - Else -> /home (main shell with 5 tabs)
///
/// Uses StatefulShellRoute for the 5-tab bottom navigation.
class AppRouter {
  AppRouter._();

  /// Global navigator key — exposed for RazorpayService to show snackbars
  /// and invalidate providers after async payment callbacks.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');

  static final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    redirect: _authRedirect,
    routes: [
      // ── Splash ──────────────────────────────────────────
      GoRoute(
        path: '/splash',
        name: 'splash',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SplashScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      ),

      // ── Auth routes ───────────────────────────────────────
      GoRoute(
        path: '/sign-in',
        name: 'signIn',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SignInScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      ),

      // ── Post-auth gate — Q1 decision tree ─────────────────────
      // Shown immediately after sign-in success. Parallel: profile lookup
      // + restoreFromCloud. Branches to /home, resume-onboarding, or
      // /onboarding/mission-brief depending on user state.
      GoRoute(
        path: '/restoring',
        name: 'restoring',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const RestoringScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      ),

      // ── Mission Brief — new-user entry point (no Supabase row yet) ─
      // Reached when RestoringScreen finds no user_profile row. Must
      // appear BEFORE any `/onboarding/:step` route so GoRouter matches
      // this exact path first.
      GoRoute(
        path: '/onboarding/mission-brief',
        name: 'missionBrief',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MissionBriefScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      ),

      GoRoute(
        path: '/avya/promise',
        name: 'avyaPromise',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MissionBriefScreen(readOnly: true),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      ),

      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const WelcomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      ),
      // Identity — NEW step 01 · 05, collects full_name + date_of_birth
      // + sex. Moved sex out of Stats, replaced age input with DOB, added
      // name capture (previously extracted from email prefix at commit
      // time).
      GoRoute(
        path: '/onboarding/identity',
        name: 'onboardingIdentity',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          return CustomTransitionPage(
            key: state.pageKey,
            child: IdentityScreen(initial: Map<String, dynamic>.from(extra)),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          );
        },
      ),
      GoRoute(
        path: '/onboarding/goal',
        name: 'onboardingGoal',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          return CustomTransitionPage(
            key: state.pageKey,
            child: GoalScreen(
              initialGoal: extra['goal'] as String?,
              identity: Map<String, dynamic>.from(extra),
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          );
        },
      ),
      GoRoute(
        path: '/onboarding/stats',
        name: 'onboardingStats',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          final goal = extra['goal'] as String? ?? 'recomp';
          return CustomTransitionPage(
            key: state.pageKey,
            child: StatsScreen(
              goal: goal,
              initial: Map<String, dynamic>.from(extra),
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          );
        },
      ),
      // AI.2 — Details screen collects fitness_experience, pace_preference,
      // days_per_week, equipment_access (4 high-leverage fields the
      // handoff's 4-screen flow previously inferred or hardcoded).
      GoRoute(
        path: '/onboarding/details',
        name: 'onboardingDetails',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          return CustomTransitionPage(
            key: state.pageKey,
            child: DetailsScreen(data: Map<String, dynamic>.from(extra)),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          );
        },
      ),
      GoRoute(
        path: '/onboarding/plan',
        name: 'onboardingPlan',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          return CustomTransitionPage(
            key: state.pageKey,
            child: PlanScreen(data: Map<String, dynamic>.from(extra)),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          );
        },
      ),
      // Legacy chat-based onboarding — retained behind /onboarding/chat as
      // a fallback while the 4-step stepped flow (welcome → goal → stats
      // → plan) rolls out via PRs Y–AB. Remove once the new flow ships
      // on all environments.
      GoRoute(
        path: '/onboarding/chat',
        name: 'onboardingChat',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const OnboardingChatScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      ),
      GoRoute(
        path: '/plan-generation',
        name: 'planGeneration',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PlanGenerationScreen(
            phase: extra['phase'] as Phase?,
            daysPerWeek: extra['daysPerWeek'] as int? ?? 4,
            dailyCalories: extra['dailyCalories'] as int? ?? 2400,
            proteinGrams: extra['proteinGrams'] as int? ?? 184,
          );
        },
      ),

      // ── Captain's induction + muster (full-screen, no tab bar) ───────────
      GoRoute(
        path: '/coach/induction',
        name: 'coachInduction',
        builder: (context, state) => const InductionScreen(),
      ),
      GoRoute(
        path: '/coach/muster',
        name: 'coachMuster',
        builder: (context, state) => const MusterScreen(),
      ),

      // ── Dev panel (DEBUG ONLY) — time-travel + rank inspection ───────────
      // Registered only in debug builds; never reachable in release.
      // Audit 2026-05-29 Phase B3.
      if (kDebugMode)
        GoRoute(
          path: '/dev',
          name: 'devPanel',
          builder: (context, state) => const DevPanelScreen(),
        ),

      // ── Founder-only admin dashboard — reachable in PRODUCTION, web only ──
      // Unlike /dev (kDebugMode-gated, compiled out of release), this route
      // is registered unconditionally so it's live on app.icanbefitter.com.
      // No bottom-nav entry, no in-app link anywhere. Real access control is
      // server-side (admin-dashboard-data's ADMIN_USER_IDS allowlist) — the
      // _authRedirect kIsWeb check below is a client-side platform guard
      // only, closing off the (unlikely but not worth relying on "unlikely")
      // path where this URL is somehow reached on the Android build.
      GoRoute(
        path: '/admin',
        name: 'admin',
        builder: (context, state) => const AdminDashboardScreen(),
      ),

      // ── Main shell with 5 tabs ────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return _MainShell(navigationShell: navigationShell);
        },
        branches: [
          // Tab 0: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),

          // Tab 1: Train
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/train',
                name: 'train',
                builder: (context, state) => const TrainScreen(),
                routes: [
                  GoRoute(
                    path: 'active-workout',
                    name: 'activeWorkout',
                    builder: (context, state) =>
                        const ActiveWorkoutScreen(),
                  ),
                  GoRoute(
                    path: 'template-builder',
                    name: 'templateBuilder',
                    builder: (context, state) {
                      final extra = state.extra;
                      return TemplateBuilderScreen(
                        editData: extra is Map<String, dynamic> ? extra : null,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'graduation',
                    name: 'graduation',
                    builder: (context, state) =>
                        const GraduationScreen(),
                  ),
                  GoRoute(
                    path: 'roadmap',
                    name: 'phaseRoadmap',
                    builder: (context, state) =>
                        const PhaseRoadmapScreen(),
                  ),
                  GoRoute(
                    path: 'preview',
                    name: 'previewWorkout',
                    builder: (context, state) {
                      final phase =
                          state.uri.queryParameters['phase'] ?? 'I';
                      final week = int.tryParse(
                              state.uri.queryParameters['week'] ?? '') ??
                          1;
                      final day = int.tryParse(
                              state.uri.queryParameters['day'] ?? '') ??
                          1;
                      return PreviewWorkoutScreen(
                        phaseNumber: phase,
                        week: week,
                        day: day,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          // Tab 2: Nutrition
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/nutrition',
                name: 'nutrition',
                builder: (context, state) => const NutritionScreen(),
                routes: [
                  GoRoute(
                    path: 'diet-plan',
                    name: 'dietPlan',
                    builder: (context, state) => const DietPlanScreen(),
                  ),
                ],
              ),
            ],
          ),

          // Tab 3: AI Coach
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ai-coach',
                name: 'aiCoach',
                builder: (context, state) => const AiCoachScreen(),
              ),
            ],
          ),

          // Tab 4: Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    name: 'editProfile',
                    builder: (context, state) =>
                        const EditProfileScreen(),
                  ),
                  GoRoute(
                    path: 'reports',
                    name: 'reports',
                    builder: (context, state) => const ReportsScreen(),
                  ),
                  GoRoute(
                    path: 'progress-photos',
                    name: 'progressPhotos',
                    builder: (context, state) => const ProgressPhotosScreen(),
                  ),
                  GoRoute(
                    // APK Test #6 / Plan F-11 — Progress Comparison row in
                    // REPORTS lists baseline + promotion + manual snapshots
                    // and renders diffs in a bottom sheet.
                    path: 'progress-comparison',
                    name: 'progressComparison',
                    builder: (context, state) =>
                        const ProgressComparisonScreen(),
                  ),
                  // audit-2026-05-16 E.8 — legacy `/profile/my-submissions`
                  // route + `MySubmissionsScreen` widget deleted. The
                  // canonical `/profile/submissions` (tabbed unified screen)
                  // shipped in Test #1 / S1 batch 2026-04-24; zero deep-link
                  // hits recorded against the legacy route in `client_errors`
                  // over 3 weeks. Founder approved deletion via Phase D
                  // NEEDS_DECISION 2 Option A.
                  GoRoute(
                    path: 'submissions',
                    name: 'submissions',
                    builder: (context, state) => const SubmissionsScreen(),
                  ),
                  GoRoute(
                    // Test #10 obs 2 — Lifetime ladder full screen.
                    // Reachable from RankServiceRecordSheet's footer
                    // link (which replaced the old VIEW FULL ROADMAP →
                    // /train/roadmap entry — the train roadmap stays
                    // accessible from the Train tab).
                    path: 'rank-ladder',
                    name: 'rankLadder',
                    builder: (context, state) => const RankLadderScreen(),
                  ),
                  GoRoute(
                    path: 'settings',
                    name: 'settings',
                    builder: (context, state) => const SettingsScreen(),
                  ),
                  GoRoute(
                    path: 'notifications',
                    name: 'notificationsInbox',
                    builder: (context, state) => const NotificationsScreen(),
                  ),
                  GoRoute(
                    path: 'notification-settings',
                    name: 'notificationSettings',
                    builder: (context, state) {
                      final extra =
                          state.extra as Map<String, dynamic>? ?? {};
                      return NotificationSettingsScreen(
                        notifPrefs: extra['notifPrefs'] as Map<String, dynamic>? ?? {},
                        isPro: extra['isPro'] as bool? ?? false,
                        onSave: extra['onSave'] as ValueChanged<Map<String, dynamic>>? ??
                            (_) {},
                      );
                    },
                  ),
                  GoRoute(
                    // DPDP hard-delete flow — 2-step confirm screen.
                    // Replaces the legacy soft-delete AlertDialog.
                    // Spec: docs/superpowers/plans/2026-05-04-apk-test-11-plan.md § Task 8.2
                    path: 'delete-account',
                    name: 'deleteAccount',
                    builder: (context, state) =>
                        const DeleteAccountScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// FIX-1 Part B (e2e-2026-06-21) — pure predicate for the session-open
  /// routing guard, extracted so its truth table is unit-testable without a
  /// live Supabase / Hive / BuildContext. Returns true when an authenticated
  /// user has reached a session-gated route before `HiveUserSession.openForUser`
  /// has run (Hive owner still null) and we must route through /restoring to
  /// open the session first. Onboarding self-navigates pre-session, so it is
  /// exempt (its own writes open/own the boxes via the sign-up bootstrap).
  @visibleForTesting
  static bool shouldGateOnSessionOpen({
    required bool isInitialized,
    required bool isAuthenticated,
    required bool ownerOpen,
    required bool isOnOnboarding,
  }) {
    if (!isInitialized || !isAuthenticated) return false;
    if (ownerOpen) return false;
    if (isOnOnboarding) return false;
    return true;
  }

  /// Auth redirect logic.
  ///
  /// Gracefully handles the case where Supabase is not yet initialized
  /// (e.g., placeholder credentials during development).
  static String? _authRedirect(BuildContext context, GoRouterState state) {
    final isOnSplash = state.matchedLocation == '/splash';
    final isOnAuthRoute = state.matchedLocation == '/sign-in';
    // /restoring is the post-auth gate screen — always passthrough so the
    // decision tree can run. Authentication check is done inside the screen.
    final isOnRestoring = state.matchedLocation == '/restoring';
    // Treat every `/onboarding*` sub-route (welcome / goal / stats /
    // plan / chat / mission-brief) as "on onboarding" so the stepped flow
    // can navigate between its own screens without the not-onboarded redirect
    // bouncing the user back to /onboarding every tap.
    final isOnOnboarding = state.matchedLocation.startsWith('/onboarding') ||
        state.matchedLocation.startsWith('/plan-generation');
    // Induction + muster are post-auth, pre-home full-screen flows.
    // Let them self-navigate without redirect interference.
    final isOnCoachInduction =
        state.matchedLocation.startsWith('/coach/induction') ||
        state.matchedLocation.startsWith('/coach/muster');

    // Dev panel (debug only) — always reachable, no auth/onboarding gate,
    // so it works on a fresh web build for time-travel verification.
    if (kDebugMode && state.matchedLocation == '/dev') return null;

    // Admin dashboard is web-only, unconditionally — /admin is registered
    // in every build (see routes above), so on a non-web platform (Android)
    // bounce to /home before it ever renders. Real access control is
    // server-side; this is a platform guard, not the security boundary.
    if (!kIsWeb && state.matchedLocation == '/admin') return '/home';

    // Let splash screen handle its own navigation.
    if (isOnSplash) return null;

    // Let the post-auth gate handle its own branching.
    if (isOnRestoring) return null;

    // Idempotency: already-inducted users landing on /coach/induction or
    // /coach/muster (deep-link, hot reload, back-navigation) get bounced to
    // /home. Un-inducted users pass through so InductionScreen/MusterScreen
    // can run their flows.
    if (isOnCoachInduction) {
      if (HiveService.instance.isInitialized &&
          InductionService.instance.inductionCompleted) {
        return '/home';
      }
      return null;
    }

    // Guard against Hive not yet initialized (startup race).
    if (!HiveService.instance.isInitialized) return null;

    final isAuthenticated = SupabaseService.instance.isAuthenticated;

    // Not signed in -> go to sign-in (unless already there).
    if (!isAuthenticated) {
      return isOnAuthRoute ? null : '/sign-in';
    }

    // FIX-1 Part B (e2e-2026-06-21) — session-open / cold-boot race guard.
    // Authenticated, but the user-scoped Hive session may not be open yet
    // (web reload / deep-link straight to a gated route, process-death
    // restore, or the sign-out → sign-in gap before openForUser runs). The
    // user-scoped reads below (onboarding_completed via MigratedKey) now
    // SERVE EMPTY under FIX-1 Part A instead of throwing — which would
    // mis-route an onboarded user to /onboarding. Route through /restoring
    // instead: it opens the session (openForUser) then re-runs this tree with
    // a valid owner + the correct destination. /splash, /restoring, and
    // /coach/induction|muster are handled above; onboarding self-navigates
    // pre-session so it is exempt. RestoringScreen._onContinueAnyway opens the
    // session before popping, so the escape-hatch can't re-trap here.
    if (shouldGateOnSessionOpen(
      isInitialized: HiveService.instance.isInitialized,
      isAuthenticated: isAuthenticated,
      ownerOpen: HiveUserSession.currentOwnerFullId != null,
      isOnOnboarding: isOnOnboarding,
    )) {
      return '/restoring';
    }

    // Signed in but not onboarded -> go to onboarding.
    //
    // Test #10.1 — Read via MigratedKey so the value comes from the
    // per-user `userBox` post-migration. Pre-fix this read from the
    // SHARED `configBox` and was THE leak vector that routed Sumit
    // straight past `/onboarding/mission-brief` into `/home` with
    // Upendra's data when `clearAllData()` partial-failed during signOut.
    final isOnboarded =
        MigratedKey.readWithDefault<bool>('onboarding_completed', false);

    if (!isOnboarded) {
      return isOnOnboarding ? null : '/onboarding';
    }

    // Signed in + onboarded but on auth/onboarding route -> go home.
    if (isOnAuthRoute || isOnOnboarding) {
      return '/home';
    }

    return null;
  }
}

// ── Main Shell ──────────────────────────────────────────────────

class _MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _MainShell({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.header,
        // Bug #25 — streetlight beam indicator. indicatorColor is set to
        // transparent so Material's default pill doesn't paint; the custom
        // shape IS the selection indicator.
        indicatorColor: Colors.transparent,
        indicatorShape: const StreetlightBeamShape(),
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppColors.accent),
            label: 'Daily',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center, color: AppColors.accent),
            label: 'Workout',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant, color: AppColors.accent),
            label: 'Nutrition',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat, color: AppColors.accent),
            label: 'Coach',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppColors.accent),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ── Bug #25 — Streetlight nav bar indicator ─────────────────────
//
// Custom ShapeBorder painted behind the selected NavigationBar destination.
// Renders a soft, rounded, translucent glow/aura centered behind the icon.
// Two-layer radial gradient: outer halo (very faint, larger) + inner core
// (slightly brighter, compact pill). The result is a gentle luminous spot —
// NOT a tall rectangular beam. Icon color + label weight change remain as
// redundant a11y cues.
class StreetlightBeamShape extends ShapeBorder {
  const StreetlightBeamShape();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ShapeBorder scale(double t) => const StreetlightBeamShape();

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    // ── Layer 1: Outer halo — very faint, larger oval for the soft glow edge
    final outerRect = Rect.fromCenter(
      center: rect.center,
      width: 64,
      height: 36,
    );
    final outerGradient = const RadialGradient(
      colors: [
        Color(0x1800D4FF), // ~9% opacity at center
        Color(0x0000D4FF), // transparent at edge
      ],
    ).createShader(outerRect);
    canvas.drawOval(outerRect, Paint()..shader = outerGradient);

    // ── Layer 2: Inner core — compact pill, slightly brighter center
    final innerRect = Rect.fromCenter(
      center: rect.center,
      width: 48,
      height: 28,
    );
    final innerGradient = const RadialGradient(
      colors: [
        Color(0x2E00D4FF), // ~18% opacity at center
        Color(0x0800D4FF), // ~3% opacity at edge
      ],
    ).createShader(innerRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, const Radius.circular(14)),
      Paint()..shader = innerGradient,
    );
  }
}
