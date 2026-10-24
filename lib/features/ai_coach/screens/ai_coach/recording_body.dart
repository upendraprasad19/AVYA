part of 'screen.dart';

// Bug 2026-05-22 / pre-batch lint sweep — extension on State subclass
// calls @protected setState. Analyzer's protected-member rule doesn't
// model "extension on same State", so file-level ignore. Runtime fine.
// ignore_for_file: invalid_use_of_protected_member

extension _RecordingBody on _AiCoachScreenState {

  // ── Helpers ────────────────────────────────────────────────────

  Future<void> _openTelegramBot() async {
    final uri = Uri.parse('https://t.me/AVYACoachBot');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ────────────────────────────────────────────────────────────────
  // F12 · Push-to-talk + morph helpers (Test #9 batch)
  // ────────────────────────────────────────────────────────────────

  Widget _buildRecordingBody() {
    final mins = _recordingElapsed.inMinutes;
    final secs = _recordingElapsed.inSeconds % 60;
    final timer =
        '${mins.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: AppColors.bad,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          timer,
          style: AppTypography.mono.copyWith(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            _slideToCancel
                ? 'Release to cancel'
                : '← slide to cancel',
            style: AppTypography.bodySm.copyWith(
              color: _slideToCancel ? AppColors.bad : AppColors.textMute,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  void _maybeSendText(bool isPro) {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    // Reuse existing gated send path (handles trial + daily cap + paywall).
    _sendMessage(text);
  }

  void _onTapAttach(bool isPro) {
    // F12 · paperclip currently routes to existing media picker.
    // F14/F15/F17 will refine gating + sheet styling separately.
    if (!isPro) {
      showPaywallSheet(context, feature: 'Photo Analysis');
      return;
    }
    _showMediaSourceSheet();
  }

  void _startRecordingPushToTalk(Offset startGlobal) {
    setState(() {
      _recordingElapsed = Duration.zero;
      _recordingStartOffset = startGlobal;
      _slideToCancel = false;
    });
    _recordingTicker?.cancel();
    _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isRecording) return;
      setState(() {
        _recordingElapsed = _recordingElapsed + const Duration(seconds: 1);
      });
    });
    // Reuse existing speech_to_text wiring (see docs/diagnoses/INDEX.md).
    // _startListening() flips _isRecording = true via setState.
    _startListening();
  }

  void _updateRecording(Offset currentGlobal) {
    final start = _recordingStartOffset;
    if (start == null) return;
    final dx = currentGlobal.dx - start.dx;
    final shouldCancel = dx < -50;
    if (shouldCancel != _slideToCancel) {
      setState(() => _slideToCancel = shouldCancel);
    }
  }

  void _stopRecordingPushToTalk({required bool send, required bool isPro}) {
    _recordingTicker?.cancel();
    _recordingTicker = null;
    final cancelled = !send;
    if (cancelled) {
      // Slide-to-cancel: stop speech, drop transcript, clear field.
      _speech?.stop();
      setState(() {
        _isRecording = false;
        _recordingElapsed = Duration.zero;
        _recordingStartOffset = null;
        _slideToCancel = false;
        _recognizedText = '';
      });
      _messageController.clear();
      return;
    }
    // Released away from cancel zone — stop listening, populate field, send.
    // _stopListening() copies _recognizedText into _messageController.
    _stopListening();
    setState(() {
      _recordingElapsed = Duration.zero;
      _recordingStartOffset = null;
      _slideToCancel = false;
    });
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      _sendMessage(text);
    }
  }

  void _showHoldToTalkTooltip() {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(builder: (_) {
      return Positioned(
        bottom: 90,
        right: 22,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardHi,
              border: Border.all(color: AppColors.line2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Hold to record voice message',
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
        ),
      );
    });
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () => entry.remove());
  }
}
