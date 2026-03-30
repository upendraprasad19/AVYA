import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Message bubble matching the mockup design.
///
/// AI messages: dark bg (#161d28), border #1c2535, top-left radius 4px.
/// User messages: cyan bg, right-aligned.
/// Supports rich text with highlighted spans (cyan, orange, green).
/// Supports optional media attachment (image thumbnail).
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
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.accent
              : isError
                  ? AppColors.red.withValues(alpha: 0.1)
                  : AppColors.input,
          borderRadius: isUser
              ? const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(4),
                )
              : const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
          border: isUser
              ? null
              : Border.all(
                  color: isError
                      ? AppColors.red.withValues(alpha: 0.3)
                      : AppColors.border,
                ),
        ),
        child: isLoading
            ? _buildLoadingDots()
            : _buildContent(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image thumbnail (if media attached)
        if (mediaUrl != null && mediaUrl!.isNotEmpty) ...[
          Builder(builder: (ctx) => GestureDetector(
            onTap: () => _openFullScreenImage(ctx, mediaUrl!),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.row),
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
                    borderRadius: BorderRadius.circular(AppRadius.row),
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
                errorWidget: (context, url, error) => Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(AppRadius.row),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textSecondary,
                      size: 28,
                    ),
                  ),
                ),
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
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 12,
                        color:
                            isUser ? Colors.black : AppColors.textPrimary,
                        height: 1.8,
                      ),
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
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: isUser
                  ? Colors.black.withValues(alpha: 0.6)
                  : AppColors.textSecondary,
            ),
          ),
        ],

        // Timestamp
        if (timestamp != null) ...[
          const SizedBox(height: 4),
          Text(
            timestamp!,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 9,
              fontWeight: FontWeight.w400,
              color: isUser
                  ? Colors.black.withValues(alpha: 0.5)
                  : AppColors.textSecondary,
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
    final defaultStyle = GoogleFonts.getFont(
      'DM Sans',
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: defaultColor,
      height: height,
    );

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
        // **cyan**
        spans.add(TextSpan(
          text: match.group(1),
          style: defaultStyle.copyWith(
            color: isUser ? Colors.black : AppColors.accent,
            fontWeight: FontWeight.w700,
          ),
        ));
      } else if (match.group(2) != null) {
        // !!orange!!
        spans.add(TextSpan(
          text: match.group(2),
          style: defaultStyle.copyWith(
            color: isUser ? Colors.black : AppColors.orange,
            fontWeight: FontWeight.w700,
          ),
        ));
      } else if (match.group(3) != null) {
        // ++green++
        spans.add(TextSpan(
          text: match.group(3),
          style: defaultStyle.copyWith(
            color: isUser ? Colors.black : AppColors.green,
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
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: Duration(milliseconds: 600 + index * 200),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
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
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
