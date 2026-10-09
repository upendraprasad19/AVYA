// Obs 5, internal-testing batch 2026-09-14. Flutter's stock `showLicensePage`
// auto-enumerates EVERY registered package license, including dev/build
// tooling internals (_fe_analyzer_shared, analyzer, analyzer_buffer,
// accessibility, ...) that mean nothing to a user — a raw dependency-tree
// dump, not curated attribution. This screen replaces that as the direct tap
// target: it shows just the artwork attribution + "Powered by Flutter", with
// a single row to reach the full stock list for anyone who actually wants it.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class CreditsLicensesScreen extends StatelessWidget {
  const CreditsLicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Credits & Licences',
          style: AppTypography.titleL.copyWith(fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(
                'ICANBEFITTER',
                style: AppTypography.h1.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 12),
              Text(
                'Exercise artwork CC BY-SA 4.0 — workout-guide (Bryl Lim), '
                'traced from Everkinetic.',
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  color: AppColors.textDim,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Powered by Flutter',
                style: AppTypography.monoXs.copyWith(
                  fontSize: 11,
                  color: AppColors.textMute,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.stackL),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(color: AppColors.line2),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'ICANBEFITTER',
                    applicationLegalese:
                        'Exercise artwork CC BY-SA 4.0 — workout-guide '
                        '(Bryl Lim), traced from Everkinetic.',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'View all open-source licences',
                            style: AppTypography.body.copyWith(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: AppColors.textDim,
                        ),
                      ],
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
