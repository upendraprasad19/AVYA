import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/read_screen_source.dart';

/// APK Test #15 / Bug E — AI coach scrolls to bottom on first paint.
///
/// Pre-Test-#15: opening the AI coach screen left scroll position at 0
/// (oldest message at top). User had to manually scroll down through the
/// full transcript just to see the latest exchange and reach the input
/// row. The `ref.listen(chatHistoryProvider, ...)` calls only fire on
/// VALUE CHANGES — not on the initial mount when the cached transcript
/// is already present.
///
/// Fix: added `_initialScrollDone` flag + `_jumpToBottom()` method.
/// First non-empty `messages` frame in `build()` triggers a one-time
/// `jumpTo(maxScrollExtent)` (no animation, no flash). Subsequent
/// rebuilds skip the gate.
///
/// Source-grep contract pins:
///   1. `_initialScrollDone` flag declared
///   2. `_jumpToBottom()` method exists with `jumpTo(maxScrollExtent)`
///   3. The build-time gate `!_initialScrollDone && messages.isNotEmpty`
///      is present and calls `_jumpToBottom()` (NOT `_scrollToBottom()`,
///      which animates and would flash).
///
/// closes-diagnose: 2026-05-10-coach-scroll-init
void main() {
  late String src;

  setUpAll(() {
    final dir = Directory('lib/features/ai_coach/screens/ai_coach');
    expect(dir.existsSync(), isTrue,
        reason: 'ai_coach screen folder must exist');
    src = readScreenSource('ai_coach');
  });

  group('AI coach initial-scroll contract', () {
    test('_initialScrollDone flag declared', () {
      expect(
        src.contains('bool _initialScrollDone'),
        isTrue,
        reason:
            'AI coach screen must declare a `bool _initialScrollDone` '
            'gate so first-paint scroll fires exactly once. closes-diagnose: '
            '2026-05-10-coach-scroll-init',
      );
    });

    test('_jumpToBottom method uses jumpTo (no animation)', () {
      expect(
        src.contains('void _jumpToBottom()'),
        isTrue,
        reason:
            '_jumpToBottom must exist as a separate method from '
            '_scrollToBottom. _scrollToBottom animates over 300 ms which is '
            'right for "new message arrived" but wrong for first paint — '
            'the user would see a visible scroll-from-top flash.',
      );
      expect(
        src.contains('jumpTo(_scrollController.position.maxScrollExtent)'),
        isTrue,
        reason:
            '_jumpToBottom must call ScrollController.jumpTo, not animateTo, '
            'so the screen lands instantly at the bottom on open with no '
            'visible scroll motion.',
      );
    });

    test('build-time gate fires once on first non-empty messages', () {
      expect(
        src.contains('!_initialScrollDone && messages.isNotEmpty'),
        isTrue,
        reason:
            'Build method must contain the gate '
            '`if (!_initialScrollDone && messages.isNotEmpty)` so the '
            'one-time initial jump fires on the first frame where the '
            'transcript is non-empty. ref.listen alone does not trigger '
            'on initial mount.',
      );
      // The gate must call _jumpToBottom (instant) — calling _scrollToBottom
      // would re-introduce the visible animation flash.
      final gateWindow = _extractGateWindow(src);
      expect(
        gateWindow.contains('_jumpToBottom()'),
        isTrue,
        reason:
            'gate body must call _jumpToBottom(), not _scrollToBottom() — '
            '_scrollToBottom animates and would flash the user from top to '
            'bottom on every open.',
      );
      expect(
        gateWindow.contains('_initialScrollDone = true'),
        isTrue,
        reason:
            'gate body must flip _initialScrollDone = true so the jump '
            'fires exactly once per screen mount.',
      );
    });

    test('forbidden: bare initState scroll without gate', () {
      // A naive fix would be to call `_scrollToBottom()` from initState.
      // That fails because the messages provider may not be loaded yet,
      // and even if it is, the ScrollController doesn't have clients
      // until after first build. The build-time gate is the right place.
      // Pin that initState does NOT directly call scroll.
      final initStateWindow = _extractInitStateWindow(src);
      expect(
        initStateWindow.contains('_scrollToBottom()') ||
            initStateWindow.contains('_jumpToBottom()'),
        isFalse,
        reason:
            'forbidden: scroll calls in initState. ScrollController has no '
            'clients yet at that point. Use the build-time gate '
            '(!_initialScrollDone && messages.isNotEmpty) instead.',
      );
    });
  });
}

/// Extracts the area around the `_initialScrollDone` build-time gate so
/// later assertions scope to that block, not unrelated _scrollToBottom
/// callsites elsewhere in the file.
String _extractGateWindow(String src) {
  const marker = '!_initialScrollDone && messages.isNotEmpty';
  final start = src.indexOf(marker);
  if (start < 0) {
    fail('Could not locate _initialScrollDone gate marker in source. '
        'Did the build-time gate get refactored? Update this test.');
  }
  final end = (start + 400).clamp(0, src.length);
  return src.substring(start, end);
}

/// Extracts the initState method body so the forbidden-pattern test can
/// scope precisely. Window is sized to encompass the whole initState
/// (~50 lines) without bleeding into _initSpeech or other methods.
String _extractInitStateWindow(String src) {
  const marker = 'void initState() {';
  final start = src.indexOf(marker);
  if (start < 0) {
    fail('Could not locate initState marker.');
  }
  // initState in this file is ~12 lines / ~400 chars
  final end = (start + 500).clamp(0, src.length);
  return src.substring(start, end);
}
