import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/auth/screens/splash_screen.dart';
import 'package:icanbefitter/features/auth/screens/sign_in_screen.dart';
import 'package:icanbefitter/features/onboarding/screens/onboarding_chat_screen.dart';
import 'package:icanbefitter/features/home/screens/home_screen.dart';
import 'package:icanbefitter/features/train/screens/train_screen.dart';
import 'package:icanbefitter/features/train/screens/active_workout_screen.dart';
import 'package:icanbefitter/features/train/screens/template_builder_screen.dart';
import 'package:icanbefitter/features/train/screens/graduation_screen.dart';
import 'package:icanbefitter/features/nutrition/screens/nutrition_screen.dart';
import 'package:icanbefitter/features/nutrition/screens/diet_plan_screen.dart';
import 'package:icanbefitter/features/ai_coach/screens/ai_coach_screen.dart';
import 'package:icanbefitter/features/profile/screens/profile_screen.dart';
import 'package:icanbefitter/features/profile/screens/edit_profile_screen.dart';
import 'package:icanbefitter/features/profile/screens/reports_screen.dart';
import 'package:icanbefitter/features/onboarding/screens/plan_generation_screen.dart';
import 'package:icanbefitter/shared/repositories/plan_generator.dart';

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
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
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
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// Auth redirect logic.
  ///
  /// Gracefully handles the case where Supabase is not yet initialized
  /// (e.g., placeholder credentials during development).
  static String? _authRedirect(BuildContext context, GoRouterState state) {
    final isOnSplash = state.matchedLocation == '/splash';
    final isOnAuthRoute = state.matchedLocation == '/sign-in';
    final isOnOnboarding = state.matchedLocation == '/onboarding';

    // Let splash screen handle its own navigation.
    if (isOnSplash) return null;

    // Guard against Hive not yet initialized (startup race).
    if (!HiveService.instance.isInitialized) return null;

    final isAuthenticated = SupabaseService.instance.isAuthenticated;

    // Not signed in -> go to sign-in (unless already there).
    if (!isAuthenticated) {
      return isOnAuthRoute ? null : '/sign-in';
    }

    // Signed in but not onboarded -> go to onboarding.
    final isOnboarded = HiveService.instance.configBox
        .get('onboarding_completed', defaultValue: false) as bool;

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
