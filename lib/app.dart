import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/colors.dart';
import 'core/router/app_router.dart';
import 'core/services/day_rollover_service.dart';
import 'core/services/razorpay_service.dart';

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
  }

  @override
  void dispose() {
    DayRolloverObserver.instance.dispose();
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
                      details.exceptionAsString(),
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
      color: const Color(0xFF020305),
      child: Center(
        child: Container(
          width: frameW,
          height: frameH,
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: const Color(0xFF1a1f2e),
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
                      color: const Color(0xFF0a0f18),
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
