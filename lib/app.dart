import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/colors.dart';
import 'core/router/app_router.dart';
import 'core/services/ai_service.dart';
import 'core/services/day_rollover_service.dart';
import 'core/services/error_telemetry.dart';
import 'core/services/nutrition_write_service.dart';
import 'core/services/rank_service.dart';
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
    // OI-37 (audit-2026-05-17 Hermes C2) — rank promotion invalidation hook.
    // Pre-fix the cloud `user_profile.current_rank_code` was updated but the
    // local Hive profile + UI showed the stale rank until next sync. Now
    // RankService.evaluateAndPromote updates Hive synchronously AND fires
    // this callback so all rank-reading widgets rebuild immediately.
    RankService.onStateChanged = () {
      try {
        ref.invalidate(userProfileProvider);
      } catch (_) {
        // ProviderScope may be disposing — invalidation is best-effort.
      }
    };
    // e4a7c9 — release PRO-owned resources when entitlement lapses. Wired here
    // rather than called directly from SubscriptionService because
    // sync_service.dart already imports subscription_service.dart; the reverse
    // call would create an import cycle AND touch a lazy singleton from inside
    // an entitlement write. This file already imports both.
    //
    // Cleared in dispose() below — set and clear stay symmetric (OI-51 / e7b3c5,
    // where RankService was installed and never cleared).
    SubscriptionService.onDowngrade = () {
      try {
        SyncService.instance.unsubscribeRealtime();
      } catch (_) {
        // Teardown is best-effort; a downgrade must never fail on it.
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
    // OI-51 (e7b3c5) — RankService was installed at :76 alongside the other two
    // but never cleared here, so its closure outlived every teardown. The set
    // and the clear must stay symmetric: one entry above, one entry here.
    RankService.onStateChanged = null;
    // e4a7c9 — same symmetry rule for the downgrade hook.
    SubscriptionService.onDowngrade = null;
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
          // APK Test #12.6 — record widget errors as Crashlytics
          // non-fatal + log-client-error event so we can see in-prod
          // ErrorWidget fallbacks. Both legs are best-effort.
          if (!kDebugMode) {
            try {
              FirebaseCrashlytics.instance.recordError(
                details.exception,
                details.stack,
                fatal: false,
                reason: 'widget_error_fallback',
              );
            } catch (_) {
              // Crashlytics must never break the fallback UI.
            }
          }
          // Audit 2026-05-12 P2-G — pre-fix this only sent the exception
          // string, capped at 200 chars. The stack trace was already
          // captured (and recorded to Crashlytics above) but not surfaced
          // in client_errors. Now compose exception + first ~400 chars of
          // stack so the active widget crash ("String' is not subtype
          // 'int?'" on 2026-05-11) has enough breadcrumbs to triage from
          // the server-side log without a Crashlytics seat.
          final exMsg = details.exception.toString();
          final exCapped = exMsg.length > 200 ? exMsg.substring(0, 200) : exMsg;
          final stackStr = details.stack?.toString() ?? '';
          final stackCapped = stackStr.length > 400 ? stackStr.substring(0, 400) : stackStr;
          final composed = stackCapped.isEmpty
              ? exCapped
              : '$exCapped\n--stack--\n$stackCapped';
          unawaited(ErrorTelemetry.logEvent(
            'widget_error_fallback',
            message: composed,
          ));
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
        return MobileFrame(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

/// Shows a phone-shaped frame around the app when viewed on wide screens (web).
/// On narrow screens (actual mobile), it passes through without the frame.
///
/// Public (no leading underscore) so `test/` can pump it in isolation —
/// see `test/contracts/mobile_frame_mediaquery_test.dart`.
///
/// Diagnose e2b8a4 (2026-09-19): this widget visually constrains [child] to
/// a narrow phone-shaped box via layout (`Container(width:, height:)` +
/// `ClipRect`) but, before this fix, never gave [child] a matching
/// `MediaQuery` — every descendant, including root-navigator overlay
/// content, still read the OUTER (e.g. 1280x720 desktop) size via
/// `MediaQuery.of(context)`. `showTimePicker`/`showDatePicker` (default
/// `useRootNavigator: true`) insert their dialog into the Navigator's
/// Overlay, which lives INSIDE [child] — so the dialog chose its
/// portrait/landscape layout and centered itself against the wrong, far
/// larger, LANDSCAPE-shaped size (1280x720) while actually being painted
/// and clipped inside the narrow PORTRAIT frame box (~322x652 at that
/// viewport). The result: a landscape-mode `TimePickerDialog` centered on
/// a canvas far bigger than the visible clipped window, so only whatever
/// slice of it happened to fall inside that window rendered — the
/// hour:minute header did, the dial and OK/Cancel row did not (confirmed
/// via a live `debugPrint` of `MediaQuery.sizeOf(context)` immediately
/// before calling `showTimePicker`, which printed the outer 1280x720, not
/// the frame's actual content box). This was NOT a font/theme/space-budget
/// bug — `responsivePickerBuilder`'s own theme + `ConstrainedBox` fix
/// (job #1-4 in that file's doc comment) made no difference because it
/// reads `MediaQuery.sizeOf(context)` too, and got the same wrong value.
/// Fixed by wrapping [child] in a `MediaQuery` reporting the frame's real
/// inner content size, so every descendant — including dialogs raised on
/// the root navigator — lays out against the box it's actually clipped to.
///
/// Round-1 review correction (e2b8a4): the reported size also now subtracts
/// the outer `Container`'s border width on each axis (`frameBorderWidth`,
/// implied `Container` decoration-padding — see `_paddingIncludingDecoration`
/// in Flutter's own `container.dart`) — a ~1.5%/0.8% discrepancy at the
/// diagnose's own cited viewport, never enough to flip a layout decision,
/// but the whole point of this widget is that the reported size should
/// match the box [child] actually gets, not approximately match it.
class MobileFrame extends StatelessWidget {
  final Widget child;
  const MobileFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final outerMediaQuery = MediaQuery.of(context);
    final size = outerMediaQuery.size;

    // If screen is narrow enough to be a real phone, no frame needed
    if (size.width <= 500) return child;

    // Clamp frame height to fit within the viewport (minus 24px margin).
    // Width maintains the 390:844 aspect ratio.
    const maxH = 844.0;
    const maxW = 390.0;
    const notchHeight = 36.0;
    const homeIndicatorHeight = 8.0;
    // e2b8a4 round-1 review finding: `Container`'s BoxDecoration.border
    // implies decoration-padding equal to the border width on every edge
    // (Flutter's `Container._paddingIncludingDecoration`), so the Column
    // below — and therefore [child] — actually receives `frameW/frameH`
    // minus 2x this, never the bare frame dimensions. Negligible in
    // practice (~1.5% at the diagnose's own cited viewport, far short of
    // flipping a portrait/landscape decision) but the MediaQuery this
    // widget hands to [child] should describe the box it actually gets.
    const frameBorderWidth = 2.5;
    final frameH = (size.height - 24).clamp(400.0, maxH);
    final frameW = (frameH / maxH * maxW).clamp(300.0, maxW);
    final contentWidth = frameW - (frameBorderWidth * 2);
    // The box [child] is actually clipped to, once the border inset and the
    // notch + home indicator bars are subtracted — this, not `size`, is
    // what any MediaQuery-driven layout decision inside [child] must be
    // made against (diagnose e2b8a4).
    final contentHeight =
        frameH - (frameBorderWidth * 2) - notchHeight - homeIndicatorHeight;

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
              width: frameBorderWidth,
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
                height: notchHeight,
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
              // App content — re-scoped to the frame's real content box so
              // root-navigator overlays (dialogs, pickers) lay out against
              // what they're actually clipped to, not the outer window.
              Expanded(
                child: ClipRect(
                  child: MediaQuery(
                    data: outerMediaQuery.copyWith(
                      size: Size(contentWidth, contentHeight),
                      viewInsets: EdgeInsets.zero,
                      viewPadding: EdgeInsets.zero,
                      padding: EdgeInsets.zero,
                    ),
                    child: child,
                  ),
                ),
              ),
              // Home indicator bar
              Container(
                height: homeIndicatorHeight,
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
