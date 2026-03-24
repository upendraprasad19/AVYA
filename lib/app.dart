import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/colors.dart';
import 'core/router/app_router.dart';

class ICanBeFitterApp extends StatelessWidget {
  const ICanBeFitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ICANBEFITTER',
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
    final screenWidth = MediaQuery.of(context).size.width;

    // If screen is narrow enough to be a real phone, no frame needed
    if (screenWidth <= 500) return child;

    return Container(
      color: const Color(0xFF020305),
      child: Center(
        child: Container(
          width: 400,
          height: 860,
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: const Color(0xFF1a1f2e),
              width: 3,
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
                height: 44,
                color: AppColors.bg,
                child: Center(
                  child: Container(
                    width: 120,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0a0f18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              // App content
              Expanded(
                child: ClipRRect(
                  child: child,
                ),
              ),
              // Home indicator bar
              Container(
                height: 8,
                color: AppColors.bg,
                child: Center(
                  child: Container(
                    width: 134,
                    height: 4,
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
