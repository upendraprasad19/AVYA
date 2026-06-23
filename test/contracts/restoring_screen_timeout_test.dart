// test/contracts/restoring_screen_timeout_test.dart
//
// Contract — Theme D (closes-diagnose 4a3b08).
//
// Pins the 15s → 30s timeout threshold + soft-hint copy. Pre-fix, the
// CONTINUE-button threshold was 15 seconds. Telemetry from APK +28/+30
// showed the founder's restore total is 35.9s every cold start (Step A
// alone is 23.8s — `custom_exercises` 18.9s + `user_preferences` 11.5s
// + `user_progress` 7.4s), so the 15s gate tripped for every user on
// every cold start.
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  late String src;

  setUpAll(() {
    src = _stripComments(
        File('lib/features/auth/screens/restoring_screen.dart')
            .readAsStringSync());
  });

  test('CONTINUE-button threshold raised from 15s to 30s', () {
    expect(
      RegExp(r'_ctaAfter\s*=\s*Duration\s*\(\s*seconds:\s*30\s*\)')
          .hasMatch(src),
      isTrue,
      reason: 'restoring_screen must declare _ctaAfter = Duration(seconds: '
          '30). Pre-fix the threshold was 15s, tripping for every user on '
          'every cold start (founder telemetry: 35.9s total median).',
    );
  });

  test('soft-hint threshold at 15s (informational only, no CTA)', () {
    expect(
      RegExp(r'_softHintAfter\s*=\s*Duration\s*\(\s*seconds:\s*15\s*\)')
          .hasMatch(src),
      isTrue,
      reason: 'restoring_screen must declare _softHintAfter = Duration('
          'seconds: 15). The soft-hint at 15s reassures users with an '
          'old mental model; the escape-hatch CTA at 30s gives them an '
          'actual exit.',
    );
  });

  test('two distinct Timers — soft hint + timeout CTA', () {
    expect(
      src.contains('Timer? _softHintTimer'),
      isTrue,
      reason: 'must declare a Timer? _softHintTimer for the 15s soft hint.',
    );
    expect(
      src.contains('Timer? _timeoutTimer'),
      isTrue,
      reason: 'must keep Timer? _timeoutTimer for the 30s CTA.',
    );
  });

  test('initState schedules both timers from _softHintAfter / _ctaAfter', () {
    expect(
      RegExp(r'_softHintTimer\s*=\s*Timer\s*\(\s*_softHintAfter')
          .hasMatch(src),
      isTrue,
      reason: 'initState must initialize _softHintTimer from _softHintAfter.',
    );
    expect(
      RegExp(r'_timeoutTimer\s*=\s*Timer\s*\(\s*_ctaAfter').hasMatch(src),
      isTrue,
      reason: 'initState must initialize _timeoutTimer from _ctaAfter.',
    );
  });

  test('dispose + _onContinueAnyway both cancel both timers', () {
    // Find dispose body and assert both cancels present.
    final disposeIdx = src.indexOf('void dispose()');
    expect(disposeIdx, greaterThan(-1));
    final disposeBody = src.substring(disposeIdx, disposeIdx + 300);
    expect(
      disposeBody.contains('_softHintTimer?.cancel()'),
      isTrue,
      reason: 'dispose must cancel _softHintTimer.',
    );
    expect(
      disposeBody.contains('_timeoutTimer?.cancel()'),
      isTrue,
      reason: 'dispose must cancel _timeoutTimer.',
    );

    // Signature-agnostic match: _onContinueAnyway became `Future<void> … async`
    // (FIX-1 Part B b8e3f1 — it now awaits openForUser before nav). The
    // contract is that it still cancels _softHintTimer, not its return type.
    final continueIdx = src.indexOf('_onContinueAnyway()');
    expect(continueIdx, greaterThan(-1));
    final continueBody = src.substring(continueIdx, continueIdx + 300);
    expect(
      continueBody.contains('_softHintTimer?.cancel()'),
      isTrue,
      reason: '_onContinueAnyway must cancel _softHintTimer too (user '
          'is leaving — no need for further hints).',
    );
  });

  test('"Almost there…" soft-hint copy present', () {
    expect(
      src.contains("'Almost there…'"),
      isTrue,
      reason: 'soft-hint copy must be "Almost there…" — informational '
          'tone for the 15-30s window.',
    );
  });

  test('soft-hint shown ONLY when _showSoftHint && !_showTimeoutCta', () {
    // Critical: at the 30s mark, both _showSoftHint AND _showTimeoutCta
    // are true. We want ONLY the CTA visible then, not both rendered
    // stacked.
    expect(
      RegExp(r'if\s*\(\s*_showSoftHint\s*&&\s*!\s*_showTimeoutCta\s*\)')
          .hasMatch(src),
      isTrue,
      reason: 'soft-hint render condition must be _showSoftHint && '
          '!_showTimeoutCta — otherwise the CTA replaces the hint at '
          '30s, and we want one or the other, never both.',
    );
  });
}
