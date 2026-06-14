import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

import 'pwa_install_interop_stub.dart'
    if (dart.library.js_interop) 'pwa_install_interop_web.dart' as pwa;

/// Web-only "Add to Home Screen" banner (Unit 3 obs 6). The browser's
/// `beforeinstallprompt` event is captured in `web/index.html`; this surfaces a
/// custom, dismissible Wardroom prompt. NOT rendered on Android/iOS (`kIsWeb`
/// gate) — the app is installed natively there. iOS Safari (which never fires
/// `beforeinstallprompt`) gets a manual "Share → Add to Home Screen" hint.
///
/// Dismiss persists in `configBox['pwa_banner_dismissed']` — a per-device/
/// browser preference (NOT user data; registered in
/// `UserConfigMigrator._intentionallyShared`).
class PwaInstallBanner extends StatefulWidget {
  const PwaInstallBanner({super.key});

  static const dismissKey = 'pwa_banner_dismissed';

  @override
  State<PwaInstallBanner> createState() => _PwaInstallBannerState();
}

class _PwaInstallBannerState extends State<PwaInstallBanner> {
  bool _dismissed = false;
  bool _canInstall = false;
  bool _iosSafari = false;
  Timer? _recheck;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    _dismissed =
        HiveService.instance.configBox.get(PwaInstallBanner.dismissKey) == true;
    _canInstall = pwa.pwaCanInstall();
    _iosSafari = pwa.pwaIsIosSafari();
    // `beforeinstallprompt` often fires shortly AFTER first paint — re-check
    // once so a banner that wasn't installable on mount can still appear.
    if (!_dismissed && !_canInstall && !_iosSafari) {
      _recheck = Timer(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        if (pwa.pwaCanInstall()) setState(() => _canInstall = true);
      });
    }
  }

  @override
  void dispose() {
    _recheck?.cancel();
    super.dispose();
  }

  void _dismiss() {
    HiveService.instance.configBox.put(PwaInstallBanner.dismissKey, true);
    setState(() => _dismissed = true);
  }

  Future<void> _install() async {
    await pwa.pwaPromptInstall();
    // The browser's `appinstalled` event clears canInstall; hide either way.
    if (mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _dismissed) return const SizedBox.shrink();
    if (!_canInstall && !_iosSafari) return const SizedBox.shrink();

    final isHint = !_canInstall && _iosSafari;
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, 0, AppSpacing.gutter, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(AppRadius.cardM),
      ),
      child: Row(
        children: [
          const Icon(Icons.add_to_home_screen,
              size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Install ICANBEFITTER',
                    style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  isHint
                      ? 'Tap Share, then "Add to Home Screen".'
                      : 'Add to your home screen — works like the app.',
                  style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
                ),
              ],
            ),
          ),
          if (!isHint) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _install,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
                child: Text('INSTALL',
                    style: AppTypography.monoXs.copyWith(
                        color: AppColors.bgDeep,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _dismiss,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: AppColors.textMute),
            ),
          ),
        ],
      ),
    );
  }
}
