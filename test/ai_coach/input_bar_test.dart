import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/read_screen_source.dart';

/// F12 · Test #9 — Coach input bar layout invariants.
void main() {
  late String src;

  setUpAll(() {
    final dir = Directory('lib/features/ai_coach/screens/ai_coach');
    expect(dir.existsSync(), isTrue, reason: 'Run from project root');
    src = readScreenSource('ai_coach');
  });

  test('mic↔send morph driven by AnimatedSwitcher with 200ms duration', () {
    expect(src.contains('AnimatedSwitcher('), isTrue);
    expect(src.contains('Duration(milliseconds: 200)'), isTrue,
        reason: 'F12 morph must be 200ms FadeTransition');
  });

  test('mic icon uses Material Icons.mic (WhatsApp glyph)', () {
    expect(src.contains('Icons.mic'), isTrue,
        reason: 'F12 mic icon must be Material Icons.mic, not karaoke emoji');
  });

  test('send icon uses Material Icons.arrow_upward', () {
    expect(src.contains('Icons.arrow_upward'), isTrue,
        reason: 'F12 send icon must be arrow_upward (matches WhatsApp)');
  });

  test('long-press handlers wired for recording UX', () {
    expect(src.contains('onLongPressStart:'), isTrue);
    expect(src.contains('onLongPressMoveUpdate:'), isTrue);
    expect(src.contains('onLongPressEnd:'), isTrue);
  });

  test('recording state has slide-to-cancel hint', () {
    expect(src.contains('slide to cancel'), isTrue);
  });
}
