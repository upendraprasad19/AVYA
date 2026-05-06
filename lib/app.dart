import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/colors.dart';
import 'core/router/app_router.dart';
import 'core/services/ai_service.dart';
import 'core/services/day_rollover_service.dart';
import 'core/services/nutrition_write_service.dart';
import 'core/services/razorpay_service.dart';
import 'core/services/subscription_service.dart';
import 'package:flutter/foundation.dart';
import 'core/services/sync_service.dart';
import 'features/ai_coach/providers/ai_coach_provider.dart';
import 'features/home/providers/home_provider.dart';
import 'features/nutrition/providers/nutrition_provider.dart';
import 'features/profile/providers/profile_provider.dart';

/// Root widget. Uses ConsumerStatefulWidget so it can attach the
/// [DayRolloverObserver] which needs a [WidgetRef] to invalidate providers.
class ICanBeFitterApp extends ConsumerStatefulWidget {
  const ICanBeFitterApp({super.key});

  @override
  ConsumerState<ICanBeFitterApp> createState() => _ICanBeFitterAppState();
}

class _ICanBeFitterAppState extends ConsumerState<ICanBeFitterApp> {
  @override
  void initState() {
    super.initState();
    DayRolloverObserver.instance.init(ref);
    RazorpayService.navigatorKey = AppRouter.navigatorKey;
    // APK Test #12.2 — invalidate subscription-related providers
    // whenever SubscriptionService writes new state to Hive. Without
    // this, `refreshFromSupabase` (fire-and-forget on splash) would
    // write `isPro=true` to Hive but the Riverpod cache stayed at
    // `isPro=false` from the initial build → profile dossier showed
    // FREE despite local Hive being correct. Founder observation
    // 2026-05-06.
    SubscriptionService.onStateChanged = () {
      try {
        ref.invalidate(subscriptionInfoProvider);
        ref.invalidate(trialInfoProvider);
        ref.invalidate(messageLimitProvider);
      } catch (_) {
        // ProviderScope may be disposing — invalidation is best-effort.
      }
    };
    // APK Test #12.4 / Task #3 — NutritionWriteService.onStateChanged
    // hook. Pre-fix the service's `_invalidateNutritionProviders`
    // early-returned because `attachContainer` was never called
    // anywhere. Every nutrition write since Test #6 silently no-op'd
    // its UI invalidation. Founder observation 2026-05-06: "I logged
    // breakfast, it showed meal saved, but nothing got updated in UI".
    NutritionWriteService.onStateChanged = () {
      try {
        ref.invalidate(dailyNutritionProvider);
        ref.invalidate(nutritionSummaryProvider);
        ref.invalidate(recentFoodLogsProvider);
        ref.invalidate(macroTargetsProvider);
        ref.invalidate(aiInsightProvider);
        ref.invalidate(foodLogProvider);
      } catch (_) {
        // ProviderScope may be disposing — invalidation is best-effort.
      }
    };
  }

  @override
  void dispose() {
    DayRolloverObserver.instance.dispose();
    SyncService.instance.unsubscribeRealtime();
    AiService.instance.dispose();
    SubscriptionService.onStateChanged = null;
    NutritionWriteService.onStateChanged = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AVYA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: AppRouter.router,
      builder: (context, child) {
        ErrorWidget.builder = (FlutterErrorDetails details) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Something went wrong',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kDebugMode
                          ? details.exceptionAsString()
                          : 'Something went wrong here. The rest of the app still works — use the back button.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        };
        // Wrap in mobile device frame for web preview
        return _MobileFrame(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

/// Shows a phone-shaped frame around the app when viewed on wide screens (web).
/// On narrow screens (actual mobile), it passes through without the frame.
class _MobileFrame extends StatelessWidget {
  final Widget child;
  const _MobileFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // If screen is narrow enough to be a real phone, no frame needed
    if (size.width <= 500) return child;

    // Clamp frame height to fit within the viewport (minus 24px margin).
    // Width maintains the 390:844 aspect ratio.
    const maxH = 844.0;
    const maxW = 390.0;
    final frameH = (size.height - 24).clamp(400.0, maxH);
    final frameW = (frameH / maxH * maxW).clamp(300.0, maxW);

    return Container(
      color: AppColors.bg,
      child: Center(
        child: Container(
          width: frameW,
          height: frameH,
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: AppColors.border,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Notch / status bar
              Container(
                height: 36,
                color: AppColors.bg,
                child: Center(
                  child: Container(
                    width: 110,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.header,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              // App content
              Expanded(child: ClipRect(child: child)),
              // Home indicator bar
              Container(
                height: 8,
                color: AppColors.bg,
                child: Center(
                  child: Container(
                    width: 120,
                    height: 3.5,
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
