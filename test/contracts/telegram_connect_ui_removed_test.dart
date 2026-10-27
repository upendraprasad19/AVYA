// test/contracts/telegram_connect_ui_removed_test.dart
//
// Regression test for OI-227 / code-review finding 4 (2026-09-21): the
// "Connect @AVYACoachBot" flow was removed from the AI Coach UI (no working
// linking token — see docs/audit/open_issues.md OI-227) without any test
// pinning the removal, on account-tier files.
//
// SOURCE-GREP ONLY — this proves presence/absence in the source text, not
// rendered behaviour. `compact_header.dart` and `telegram_view.dart` are
// both `part of 'screen.dart'`, and the containing State touches Riverpod
// providers (channelProvider, chatHistoryProvider, subscription state) and
// a live AI-coach chat pipeline that would need substantial fixture
// scaffolding to pump as a real widget. Per this repo's own
// feedback_source_grep_false_confidence.md, treat this as PRESENCE
// evidence only — a future extraction/rename could relocate this code
// without tripping these assertions. If this screen ever gets a proper
// widget-test harness, migrate these three checks onto it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final compactHeaderSrc = File(
    'lib/features/ai_coach/screens/ai_coach/compact_header.dart',
  ).readAsStringSync();
  final telegramViewSrc = File(
    'lib/features/ai_coach/screens/ai_coach/telegram_view.dart',
  ).readAsStringSync();

  group('compact_header.dart — telegram connect menu item', () {
    test('no PopupMenuItem offers to connect Telegram', () {
      expect(
        compactHeaderSrc.contains("value: 'telegram'"),
        isFalse,
        reason: 'OI-227 — the connect entry point must stay removed until '
            'a real linking-token handshake exists (phase 2).',
      );
      expect(
        compactHeaderSrc.contains('_openTelegramBot()'),
        isFalse,
        reason: 'the header itself must not call the broken deep link — '
            'only the already-connected CTA in telegram_view.dart may.',
      );
    });

    test('switch_channel toggle is still present', () {
      expect(
        compactHeaderSrc.contains("value: 'switch_channel'"),
        isTrue,
        reason: 'channelProvider persists coach_channel to Hive — a user '
            "already on channel=='telegram' needs this to get back to "
            'in-app chat. Removing it too would strand them with no UI '
            'path back.',
      );
    });
  });

  group('telegram_view.dart — connected-only CTA', () {
    test('the OPEN TELEGRAM button only renders when connected', () {
      // The `if (telegramConnected) ...[` gate must wrap the CTA block —
      // asserting the gate literally precedes the button text in source
      // order (not just that both strings exist somewhere in the file).
      final gateIndex = telegramViewSrc.indexOf('if (telegramConnected)');
      final ctaIndex = telegramViewSrc.indexOf('OPEN TELEGRAM');
      expect(gateIndex, greaterThan(-1),
          reason: 'the connected-only gate must exist');
      expect(ctaIndex, greaterThan(-1),
          reason: 'the CTA text must exist for an already-connected user');
      expect(gateIndex, lessThan(ctaIndex),
          reason: 'the gate must precede the CTA it guards, not merely '
              'coexist with it elsewhere in the file');
    });

    test('not-connected copy no longer invites a connect attempt', () {
      expect(telegramViewSrc.contains('Connect @AVYACoachBot'), isFalse,
          reason: 'the old CTA copy promised a working handshake that '
              "does not exist — must not survive as dead not-connected "
              'text even if the button itself is gone');
      expect(telegramViewSrc.contains('Coming Soon'), isTrue,
          reason: 'the not-connected state must say something honest '
              'about the feature status');
    });
  });
}
