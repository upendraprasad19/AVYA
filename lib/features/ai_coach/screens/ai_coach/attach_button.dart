part of 'screen.dart';

extension _AttachButton on _AiCoachScreenState {

  // ────────────────────────────────────────────────────────────────
  // PHOTO ATTACHMENT BUTTON + FLOW
  // ────────────────────────────────────────────────────────────────

  /// Builds the attach-photo icon button.
  /// PRO users: opens media source picker.
  /// Free users: gold-locked icon -> paywall.
  ///
  /// F12 (Test #9 batch): no longer wired into the input bar — the new single
  /// 48dp bubble uses an inline `IconButton(Icons.attach_file)` instead.
  /// Preserved here so F14/F15/F17 lock-badge work can reuse the styling.
  // ignore: unused_element
  Widget _buildAttachButton(bool isPro, bool isSending) {
    if (_isUploadingMedia) {
      // Show upload progress indicator
      return SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
            const Icon(
              Icons.photo,
              color: AppColors.accent,
              size: 12,
            ),
          ],
        ),
      );
    }

    if (!isPro) {
      // Gold-locked sharp 2-px tile for free users
      return GestureDetector(
        onTap: () => showPaywallSheet(context, feature: 'Photo Analysis'),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.proGoldTint,
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            border: Border.all(color: AppColors.proGold, width: 2),
          ),
          child: Stack(
            children: [
              const Center(
                child: Icon(
                  Icons.attach_file,
                  color: AppColors.proGold,
                  size: 14,
                ),
              ),
              Positioned(
                bottom: 1,
                right: 1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.proGold,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.header, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.lock,
                    size: 5,
                    color: AppColors.bgDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // PRO user — active sharp 2-px accent tile
    return GestureDetector(
      onTap: isSending ? null : () => _showMediaSourceSheet(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(color: AppColors.accent, width: 2),
        ),
        child: const Icon(
          Icons.attach_file,
          color: AppColors.accent,
          size: 14,
        ),
      ),
    );
  }
}
