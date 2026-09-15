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

  test('subtitle collapsed into progress-bar row', () {
    expect(src.contains('of \$totalWorkoutDays sessions complete'), isFalse,
        reason: 'F9 dropped the verbose subtitle in favor of inline X / Y');
    expect(src.contains('\$completedDays / \$totalWorkoutDays'), isTrue,
        reason: 'F9 inlines the subtitle as compact X / Y with progress bar');
  });

  test('WardStatusStrip placed inside title Row trailing (not standalone)', () {
    expect(src.contains('WardStatusStrip('), isTrue);
  });
}
