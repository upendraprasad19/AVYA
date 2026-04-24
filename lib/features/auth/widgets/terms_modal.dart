import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Blocking modal that gates the sign-in screen until the user has
/// accepted the Privacy Policy + Terms of Service. Acceptance is stored
/// in Hive (`userBox['terms_accepted_at']` + `terms_version`) and synced
/// to Supabase `users` on the next post-auth upsert.
///
/// Call [maybeShow] from the sign-in screen's `initState`
/// (via a post-frame callback so the context has a navigator). It is a
/// no-op when the user has already accepted the current [AppConstants.termsVersion].
class TermsModal extends StatelessWidget {
  const TermsModal._();

  /// Show the modal if the user hasn't accepted the current terms version.
  ///
  /// Returns `true` if the modal was shown (and accepted), `false` if the
  /// user had already accepted — no user-visible effect in the latter case.
  static Future<bool> maybeShow(BuildContext context) async {
    if (_alreadyAccepted()) return false;
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => const PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 60,
          ),
          child: TermsModal._(),
        ),
      ),
    );
    return true;
  }

  static bool _alreadyAccepted() {
    try {
      final box = HiveService.instance.userBox;
      final stamp = box.get('terms_accepted_at');
      final storedVersion = box.get('terms_version');
      return stamp is String &&
          stamp.isNotEmpty &&
          storedVersion == AppConstants.termsVersion;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _recordAcceptance() async {
    try {
      final box = HiveService.instance.userBox;
      await box.put(
        'terms_accepted_at',
        DateTime.now().toUtc().toIso8601String(),
      );
      await box.put('terms_version', AppConstants.termsVersion);
    } catch (_) {
      // Best-effort — if Hive isn't open yet, the modal will simply show
      // again next launch. Not fatal.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Double gold rule eyebrow.
          Container(
            margin: const EdgeInsets.only(bottom: 2),
            height: 1,
            color: AppColors.accent,
          ),
          const SizedBox(height: 4),
          Container(
            height: 1,
            color: AppColors.accent.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 10),
          Text(
            'BEFORE WE BEGIN',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your privacy, our promise.',
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'ICANBEFITTER stores your health data locally on your device and '
            'syncs it to our secure backend only to give you AI coaching, '
            'workout plans, and progress tracking. We never sell your data.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textDim,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _LinkRow(
            label: 'Privacy Policy',
            url: 'https://icanbefitter.vercel.app/privacy',
          ),
          const SizedBox(height: 8),
          _LinkRow(
            label: 'Terms of Service',
            url: 'https://icanbefitter.vercel.app/terms',
          ),
          const SizedBox(height: 22),
          _AcceptButton(onAccepted: () async {
            await _recordAcceptance();
            if (context.mounted) Navigator.of(context).pop();
          }),
        ],
      ),
    );
  }
}

class _LinkRow extends StatefulWidget {
  const _LinkRow({required this.label, required this.url});

  final String label;
  final String url;

  @override
  State<_LinkRow> createState() => _LinkRowState();
}

class _LinkRowState extends State<_LinkRow> {
  final _recognizer = TapGestureRecognizer();

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse(widget.url),
        mode: LaunchMode.externalApplication,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.open_in_new,
            size: 14,
            color: AppColors.accent,
          ),
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _AcceptButton extends StatelessWidget {
  const _AcceptButton({required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAccepted,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'I ACCEPT',
              style: AppTypography.mono.copyWith(
                color: AppColors.bgDeep,
                letterSpacing: 2,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
