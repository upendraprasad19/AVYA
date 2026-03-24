import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

/// Full-screen splash with ICANBEFITTER wordmark and a subtle loading indicator.
///
/// Shows for 1.5 seconds, then navigates based on auth state:
///   - Authenticated + onboarded -> /home
///   - Authenticated + not onboarded -> /onboarding
///   - Not authenticated -> /sign-in
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    // Start the fade-in animation.
    _fadeController.forward();

    // Navigate after 1.5 seconds.
    Future.delayed(const Duration(milliseconds: 1500), _navigateNext);
  }

  void _navigateNext() {
    if (!mounted) return;

    final isAuthenticated = SupabaseService.instance.isAuthenticated;

    if (!isAuthenticated) {
      context.go('/sign-in');
      return;
    }

    final isOnboarded = HiveService.instance.configBox
        .get('onboarding_completed', defaultValue: false) as bool;

    if (!isOnboarded) {
      context.go('/onboarding');
      return;
    }

    context.go('/home');
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Wordmark
              Text(
                'ICANBEFITTER',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: AppColors.accent,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              // Subtle loading indicator
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
