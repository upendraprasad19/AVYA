import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Wardroom chat bubble.
///
/// Sharp corners — 6-px card-radius overall, 2-px tail on the side that
/// points at the sender. AI bubbles sit on [AppColors.card] with a hairline
/// [AppColors.line2] border. User bubbles use Campaign Gold ([AppColors.accent])
/// with black text — they read as "your orders, sent." Error bubbles swap to
/// the warm [AppColors.bad] family with a matching subtle tint.
///
/// Body copy stays DM Sans (paragraph family). Timestamps switch to JB Mono
/// (Wardroom uppercase cadence). Rich-text markers map to semantic Wardroom
/// tokens: **accent gold**, !!warn amber!!, ++ok olive++.
class ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isLoading;
  final bool isError;
  final String? timestamp;

  /// Optional list items to render as a bullet list below the main text.
  final List<String>? bulletItems;

  /// Optional sub-text shown below the message in secondary color.
  final String? subText;

  /// URL of an attached photo (Supabase Storage).
  final String? mediaUrl;

  /// Media type (e.g. 'image').
  final String? mediaType;

  /// Bug #19 — When non-null AND [isError] is true, render a Retry button
  /// inside the error bubble. Tap re-sends the original user message.
  final VoidCallback? onRetry;

  /// Bug 2026-05-16 photo-analysis-500 — when true, the bubble renders an
  /// explicit "Photo failed to upload" failure state instead of the broken-
  /// image icon that `CachedNetworkImage.errorWidget` shows by default.
  /// Set by the provider when the photo upload itself failed OR when
  /// `ai-media-proxy` returned an error tagged `error_type='storage'`
  /// (image upload incomplete).
  ///
  /// When this is true the bubble also renders an [onMediaRetry] tap target
  /// (if provided) so the user can re-trigger the upload without typing
  /// the message again.
  final bool mediaFailed;

  /// Bug 2026-05-16 — invoked when the user taps the "Photo failed to
  /// upload — Retry" affordance. Null when no retry path is wired (e.g.
  /// the file picker has already been disposed). The widget gracefully
  /// degrades to a non-tappable failure state when null.
  final VoidCallback? onMediaRetry;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.isLoading = false,
    this.isError = false,
    this.timestamp,
    this.bulletItems,
    this.subText,
    this.mediaUrl,
    this.mediaType,
    this.onRetry,
    this.mediaFailed = false,
    this.onMediaRetry,
  });

  @override
  Widget build(BuildContext context) {
    // Sharp Wardroom corners — 6 px on body, 2 px on the tail side.
    const soft = Radius.circular(6);
    const tail = Radius.circular(2);

    final Color bg;
    final Color borderColor;
    if (isUser) {
      bg = AppColors.accent;
      borderColor = AppColors.accent;
    } else if (isError) {
      bg = AppColors.bad.withValues(alpha: 0.12);
      borderColor = AppColors.bad.withValues(alpha: 0.35);
    } else {
      bg = AppColors.card;
      borderColor = AppColors.line2;
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: isUser
              ? const BorderRadius.only(
                  topLeft: soft,
                  topRight: soft,
                  bottomLeft: soft,
                  bottomRight: tail,
                )
              : const BorderRadius.only(
                  topLeft: tail,
                  topRight: soft,
                  bottomLeft: soft,
                  bottomRight: soft,
                ),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: isLoading ? _buildLoadingDots() : _buildContent(),
      ),
    );
  }

  Widget _buildLoadingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dot(0),
        const SizedBox(width: 4),
        _dot(1),
        const SizedBox(width: 4),
        _dot(2),
      ],
    );
  }

  Widget _buildContent() {
    // Bug 2026-05-16 photo-analysis-500 — explicit failure state:
    // mediaFailed=true OR mediaUrl is null/empty while mediaType indicates
    // a photo message → render "Photo failed to upload" with optional
    // Retry button. Pre-fix the only failure surface was
    // CachedNetworkImage's broken-image icon, which gave no actionable
    // context. The user reported "the image he sent is NOT visible in
    // the chat — only the 'Analyse this photo' caption shows over a blank
    // black square."
    final bool isPhotoMessage =
        (mediaType ?? '').toLowerCase().startsWith('image') ||
            (mediaType ?? '').isNotEmpty;
    final bool hasMediaUrl = mediaUrl != null && mediaUrl!.isNotEmpty;
    final bool showFailedSlot =
        mediaFailed || (isPhotoMessage && !hasMediaUrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image thumbnail (if media attached)
        if (showFailedSlot) ...[
          _buildPhotoFailedTile(),
          if (text.isNotEmpty) const SizedBox(height: 6),
        ] else if (hasMediaUrl) ...[
          Builder(builder: (ctx) => GestureDetector(
            onTap: () => _openFullScreenImage(ctx, mediaUrl!),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sharp),
              child: CachedNetworkImage(
                imageUrl: mediaUrl!,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
                // Bug 2026-05-16 — when CachedNetworkImage itself can't
                // load the URL (CDN propagation, ACL drift), surface the
                // same "Photo failed to upload" tile as the no-URL case.
                // Keeps a single failure mode visible to the user.
                errorWidget: (context, url, error) => _buildPhotoFailedTile(),
              ),
            ),
          )),
          if (text.isNotEmpty) const SizedBox(height: 6),
        ],

        // Main message text
        if (text.isNotEmpty) _buildRichText(text),

        // Bullet list
        if (bulletItems != null && bulletItems!.isNotEmpty) ...[
          const SizedBox(height: 6),
          ...bulletItems!.map((item) => Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '\u2022 ',
                      style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700, color: isUser ? Colors.black : AppColors.accent, height: 1.8),
                    ),
                    Expanded(child: _buildRichText(item, height: 1.8)),
                  ],
                ),
              )),
        ],

        // Sub text (e.g. "Shall I update today's session?")
        if (subText != null) ...[
          const SizedBox(height: 8),
          Text(
            subText!,
            style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w400, fontStyle: FontStyle.italic, color: isUser
                  ? Colors.black.withValues(alpha: 0.7)
                  : AppColors.textMute),
          ),
        ],

        // Bug #19 — Retry button on failed AI bubbles. Re-sends the original
        // user message; the provider reuses the same coachBox row so history
        // doesn't duplicate.
        if (isError && onRetry != null) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.55),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.refresh_rounded,
                    size: 13,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'RETRY',
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Timestamp — JB Mono caps, Wardroom telegraph cadence.
        if (timestamp != null) ...[
          const SizedBox(height: 6),
          Text(
            timestamp!.toUpperCase(),
            style: AppTypography.monoXs.copyWith(
              fontSize: 8,
              letterSpacing: 1.4,
              color: isUser
                  ? Colors.black.withValues(alpha: 0.55)
                  : AppColors.textMute,
            ),
          ),
        ],
      ],
    );
  }

  /// Parses simple markup for highlighted text:
  ///   **text** → cyan highlight
  ///   !!text!! → orange warning
  ///   ++text++ → green positive
  Widget _buildRichText(String content, {double height = 1.65}) {
    final defaultColor = isUser ? Colors.black : AppColors.textPrimary;
    final defaultStyle = AppTypography.bodySm.copyWith(color: defaultColor, height: height);

    // Simple regex for **bold/cyan**, !!warning/orange!!, ++positive/green++
    final pattern = RegExp(r'\*\*(.*?)\*\*|!!(.*?)!!|\+\+(.*?)\+\+');
    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in pattern.allMatches(content)) {
      // Text before the match
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: content.substring(lastEnd, match.start),
          style: defaultStyle,
        ));
      }

      if (match.group(1) != null) {
        // **accent** — Campaign Gold emphasis.
        spans.add(TextSpan(
          text: match.group(1),
          style: defaultStyle.copyWith(
            color: isUser ? Colors.black : AppColors.accent,
            fontWeight: FontWeight.w700,
          ),
        ));
      } else if (match.group(2) != null) {
        // !!warn!! — amber warning.
        spans.add(TextSpan(
          text: match.group(2),
          style: defaultStyle.copyWith(
            color: isUser ? Colors.black : AppColors.warn,
            fontWeight: FontWeight.w700,
          ),
        ));
      } else if (match.group(3) != null) {
        // ++ok++ — olive success.
        spans.add(TextSpan(
          text: match.group(3),
          style: defaultStyle.copyWith(
            color: isUser ? Colors.black : AppColors.ok,
            fontWeight: FontWeight.w700,
          ),
        ));
      }

      lastEnd = match.end;
    }

    // Remaining text
    if (lastEnd < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastEnd),
        style: defaultStyle,
      ));
    }

    if (spans.isEmpty) {
      return Text(content, style: defaultStyle);
    }

    return RichText(text: TextSpan(children: spans));
  }

  Widget _dot(int index) {
    // On user bubble (gold bg) use black dots; on AI bubble use gold dots.
    final dotColor = isUser ? Colors.black : AppColors.accent;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: Duration(milliseconds: 600 + index * 200),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  /// Bug 2026-05-16 photo-analysis-500 — replaces the broken-image icon
  /// with a 120×120 tile that explicitly says "Photo failed to upload"
  /// and exposes an optional Retry tap target. Wired from two sites:
  ///   (a) `_buildContent` when `mediaFailed=true` OR mediaUrl missing on
  ///       a photo-message.
  ///   (b) `CachedNetworkImage.errorWidget` — same failure mode for CDN /
  ///       ACL drift cases where the URL is set but doesn't resolve.
  Widget _buildPhotoFailedTile() {
    final tile = Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        border: Border.all(color: AppColors.bad.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            color: AppColors.bad.withValues(alpha: 0.85),
            size: 22,
          ),
          const SizedBox(height: 6),
          Text(
            'PHOTO FAILED',
            textAlign: TextAlign.center,
            style: AppTypography.monoXs.copyWith(
              fontSize: 9,
              letterSpacing: 1.2,
              color: AppColors.bad,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Tap to retry',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textMute),
          ),
        ],
      ),
    );
    if (onMediaRetry == null) return tile;
    return GestureDetector(onTap: onMediaRetry, child: tile);
  }

  /// Opens a full-screen image viewer for the attached photo.
  void _openFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(imageUrl: imageUrl),
      ),
    );
  }
}

/// Full-screen image viewer with dark background and close button.
class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
            errorWidget: (context, url, error) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textSecondary,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  'Failed to load image',
                  style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
