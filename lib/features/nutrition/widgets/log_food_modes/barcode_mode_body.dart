import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// BARCODE mode body for `LogFoodSheet`. Refactored from
/// `_BarcodeScanSheet` to render inside the parent sheet rather than
/// opening as a separate modal. Keeps the same MobileScanner controller
/// + result-editor flow; on save, calls [onLogged].
///
/// NOTE: This task creates the body shell. The full implementation
/// reuses the result-editor logic from `barcode_scan_sheet.dart` — see
/// Task 6 where the legacy `_BarcodeScanSheet` body is extracted into a
/// shared `BarcodeBody` and the entry-point `showBarcodeScanSheet`
/// helper kept for any external callers (none today).
class BarcodeModeBody extends ConsumerStatefulWidget {
  const BarcodeModeBody({super.key, required this.onLogged});

  final VoidCallback onLogged;

  @override
  ConsumerState<BarcodeModeBody> createState() => _BarcodeModeBodyState();
}

class _BarcodeModeBodyState extends ConsumerState<BarcodeModeBody> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Placeholder shell — Task 6 will fill this in by extracting the
    // _BarcodeScanSheetState build body from barcode_scan_sheet.dart
    // verbatim (controller is already wired here).
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'POINT YOUR CAMERA AT A PRODUCT BARCODE',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: MobileScanner(controller: _controller),
              ),
            ),
          ),
          // Body finalised in Task 6.
        ],
      ),
    );
  }
}
