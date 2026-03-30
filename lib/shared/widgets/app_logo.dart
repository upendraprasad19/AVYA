import 'package:flutter/material.dart';
import 'package:icanbefitter/core/constants/app_environment.dart';
import 'package:icanbefitter/core/theme/colors.dart';

/// App logo widget — shows AVYA logo with a gold "QA" badge in dev flavor.
/// Use this everywhere the logo appears (AppBar, splash, onboarding).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 32});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Image.asset('assets/avya_logo.png', height: height),
        if (kIsDevFlavor)
          Positioned(
            top: -5,
            right: -14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.proGold,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'QA',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
