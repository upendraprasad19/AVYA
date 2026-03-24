import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Captures a RepaintBoundary widget as a PNG image and shares it
/// via the native OS share sheet.
///
/// Usage:
/// ```dart
/// final cardKey = GlobalKey();
/// // Wrap your card widget in RepaintBoundary(key: cardKey, child: ...)
/// // Then call:
/// await CardShareService.captureAndShare(cardKey);
/// ```
class CardShareService {
  CardShareService._();

  /// Capture the widget behind [repaintKey] as a PNG and open the share sheet.
  ///
  /// [filename] defaults to `icanbefitter_card_<timestamp>.png`.
  /// Fire-and-forget — errors are silently swallowed so the UI never blocks.
  static Future<void> captureAndShare(
    GlobalKey repaintKey, {
    String? filename,
  }) async {
    try {
      final boundary = repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final name =
          filename ?? 'icanbefitter_card_${DateTime.now().millisecondsSinceEpoch}.png';

      await Share.shareXFiles(
        [XFile.fromData(pngBytes, name: name, mimeType: 'image/png')],
        text: 'Shared from ICANBEFITTER',
      );
    } catch (_) {
      // Fire-and-forget — never block the UI.
    }
  }
}
