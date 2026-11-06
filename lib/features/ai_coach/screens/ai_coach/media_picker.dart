part of 'screen.dart';

// Bug 2026-05-22 / pre-batch lint sweep (Theme B fold) — A11 extracted
// chat-screen helpers into part-file extensions on _AiCoachScreenState.
// `setState` is a @protected member of State; extension methods can't
// call it under the analyzer's default rules even when the extension is
// on the same State subclass. The runtime semantics are fine — this is
// purely an analyzer rule that doesn't model "extension on State".
// File-level ignore matches the same pattern recording_body.dart needs.
// ignore_for_file: invalid_use_of_protected_member

extension _MediaPicker on _AiCoachScreenState {

  /// Shows a bottom sheet with Camera and Gallery options.
  void _showMediaSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
          border: Border(
            top: BorderSide(color: AppColors.line2, width: 1),
            left: BorderSide(color: AppColors.line2, width: 1),
            right: BorderSide(color: AppColors.line2, width: 1),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(AppRadius.soft),
                ),
              ),
              Text(
                'Send a Photo',
                style: AppTypography.h3,
              ),
              const SizedBox(height: 4),
              Text(
                'Your AI coach will analyse the image',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(height: 16),
              // Camera option
              _mediaOption(
                icon: Icons.camera_alt,
                label: 'Camera',
                subtitle: 'Take a photo now',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
              // Gallery option
              _mediaOption(
                icon: Icons.photo_library,
                label: 'Gallery',
                subtitle: 'Choose from photos',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mediaOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return WardCard(
      variant: WardCardVariant.inset,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
              border: Border.all(color: AppColors.accent, width: 2),
            ),
            child: Icon(icon, color: AppColors.accent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.h3.copyWith(fontSize: 14),
                ),
                Text(
                  subtitle,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: AppColors.textDim,
            size: 20,
          ),
        ],
      ),
    );
  }

  /// Pick an image from camera or gallery, compress it, upload, and send.
  Future<void> _pickImage(ImageSource source) async {
    // audit-2026-05-16 F8.1 / E.8 — `featurePhotoAnalysis` is documented as
    // a PRO feature in docs/architecture/business-rules.md, but pre-fix had ZERO client-side gate
    // callsites — free users could silently upload photos to chat (server-
    // side ai-media-proxy enforced a separate PRO check, but the client UX
    // never surfaced the paywall). Gate at the entry point.
    // OI-44 Unit 6 — awaited so `_pickImage`'s own Future completes only once
    // the gate has routed. It is the last statement here, so nothing races it;
    // `gateAndVerify` returning a Future (rather than the old `void`) is what
    // makes this expressible at all.
    await SubscriptionService.instance.gateAndVerify(
      AppConstants.featurePhotoAnalysis,
      onPro: () => _doPickImage(source),
      onFree: () {
        if (!mounted) return;
        showPaywallSheet(context, feature: 'Photo Analysis');
      },
    );
  }

  /// PRO-only image picker body (extracted from _pickImage for gate routing).
  Future<void> _doPickImage(ImageSource source) async {
    try {
      // On web, camera is not available
      if (kIsWeb && source == ImageSource.camera) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Camera is not available on web. Use gallery instead.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              backgroundColor: AppColors.card,
            ),
          );
        }
        return;
      }

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() {
        _isUploadingMedia = true;
        _uploadProgress = 0.0;
      });

      // Read the file bytes
      final Uint8List imageBytes = await pickedFile.readAsBytes();

      // Compress if needed (flutter_image_compress for native, skip on web)
      Uint8List compressedBytes;
      if (!kIsWeb) {
        try {
          // Dynamic import to avoid web compilation issues
          final compressed = await _compressImage(imageBytes);
          compressedBytes = compressed ?? imageBytes;
        } catch (e) {
          debugPrint('[AiCoachScreen._pickAndUploadImage] $e');
          compressedBytes = imageBytes;
        }
      } else {
        compressedBytes = imageBytes;
      }

      // Check size limit (2MB)
      if (compressedBytes.lengthInBytes > 2 * 1024 * 1024) {
        // Try harder compression
        if (!kIsWeb) {
          final recompressed = await _compressImage(imageBytes, quality: 60);
          compressedBytes = recompressed ?? compressedBytes;
        }
      }

      setState(() => _uploadProgress = 0.3);

      // Upload to Supabase Storage
      final supabase = SupabaseService.instance;
      final userId = supabase.currentUser?.id;
      if (userId == null) {
        throw Exception('Not authenticated');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = '$userId/$timestamp.jpg';

      await supabase.client.storage.from('chat-media').uploadBinary(
            storagePath,
            compressedBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception(
                'Upload timed out. Please check your connection and try again.'),
          );

      setState(() => _uploadProgress = 0.7);

      // Bug t1m5b0 (APK Test #16.2) — `chat-media` is a PRIVATE bucket
      // (storage.buckets.public = false, confirmed 2026-05-18). The
      // pre-fix call `getPublicUrl(storagePath)` returned a URL of shape
      // `${SUPABASE_URL}/storage/v1/object/public/chat-media/<path>`,
      // which Supabase Storage rejects with HTTP 400 "Bad Request"
      // because /public/... is only valid for buckets where public=true.
      // ai-media-proxy's service-role fetch hit that 400 on every
      // attempt; the typed HttpError mapped it to `error_type=storage`
      // and the client surfaced "PHOTO FAILED · Tap to retry" with no
      // path to recovery (the 500/1500/3000 ms retry backoff couldn't
      // help — the URL was permanently bad).
      //
      // Fix: createSignedUrl(path, ttlSeconds) returns a URL of shape
      // `.../storage/v1/object/sign/chat-media/<path>?token=<jwt>`
      // which Storage accepts for private buckets. ai-media-proxy's
      // parseStorageUrl already handles the `sign/<bucket>/<path>?token=...`
      // shape (supabase/functions/ai-media-proxy/index.ts:178). 600s TTL
      // is plenty — the Edge Function fetches the URL within seconds of
      // receiving the request; we keep buffer for retry budgets.
      final publicUrl = await supabase.client.storage
          .from('chat-media')
          .createSignedUrl(storagePath, 600);

      setState(() => _uploadProgress = 1.0);

      // Track last media request in coachBox (rate limit: max once per 7 days)
      final coachBox = HiveService.instance.coachBox;
      await coachBox.put(
          'last_media_request_at', DateTime.now().toIso8601String());

      // Send the message with media URL
      final messageText = _messageController.text.trim();
      _messageController.clear();

      unawaited(ref.read(sendMessageProvider.notifier).sendWithMedia(
            messageText,
            mediaUrl: publicUrl,
            mediaType: 'image',
            // Unit 8 (coach-media-consent) — the raw chat-media Storage
            // path, stable beyond publicUrl's 600s signed-URL TTL.
            mediaStoragePath: storagePath,
          ));
      _scrollToBottom();
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('ai_coach_photo_upload_failed',
          message: clipped));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to upload photo: ${errStr.length > 80 ? errStr.substring(0, 80) : errStr}',
              style: AppTypography.body.copyWith(color: AppColors.bad),
            ),
            backgroundColor: AppColors.card,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingMedia = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  /// Compress image bytes using flutter_image_compress (native only).
  Future<Uint8List?> _compressImage(Uint8List bytes,
      {int quality = 85}) async {
    // flutter_image_compress only works on mobile platforms
    if (kIsWeb) return bytes;

    try {
      // Use dynamic import pattern to avoid web compilation issues
      final result =
          await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1920,
        minHeight: 1920,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      return result;
    } catch (e) {
      debugPrint('[AiCoachScreen._compressImage] $e');
      return null;
    }
  }
}
