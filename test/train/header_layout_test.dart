import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/read_screen_source.dart';

/// F9 · Test #9 — Train header layout invariants.
void main() {
  late String src;

  setUpAll(() {
    final dir = Directory('lib/features/train/screens/train');
    expect(dir.existsSync(), isTrue, reason: 'Run from project root');
    src = readScreenSource('train');
  });

  test('title uses Fraunces h1 32sp (standardized cross-screen)', () {
    expect(src.contains('AppTypography.h1.copyWith('), isTrue,
        reason: 'Title must use h1 (Fraunces) per F9 standardization');
    expect(src.contains('fontSize: 32'), isTrue,
        reason: 'Title must be 32 sp (was 28); cross-screen standard');
  });

  test('eyebrow includes WK + PHASE meta', () {
    expect(src.contains('TRAIN \\u00B7 WK'), isTrue);
    expect(src.contains('PHASE \$currentPhase'), isTrue,
        reason: 'eyebrow must include PHASE number per F9');
  });

  test('no progress bar in the plan header; only a hold week shows its session count', () {
    // Founder call 2026-11-02 (train-header-b2): the `0 / 6` bar went. The hold
    // week keeps its OWN session count as plain text (no bar, no percent).
    expect(src.contains('of \$totalWorkoutDays sessions complete'), isFalse);
    expect(src.contains('WardBar('), isFalse,
        reason: 'the plan-header progress bar was removed');
    expect(src.contains('\$completedDays / \$totalWorkoutDays SESSIONS'), isTrue,
        reason: 'the hold-week sessions readout stays');
    expect(src.contains('progressPercent'), isFalse);
  });

  test('WardStatusStrip placed inside title Row trailing (not standalone)', () {
    expect(src.contains('WardStatusStrip('), isTrue);
  });
}
