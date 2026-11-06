// Batch 8 UNIT 3-a1 — REG-1 (a4e2d9): a PRO whose SILENT splash auto-advance
// failed or raced must NOT be stranded on the free "go PRO" PlanExpiredCard
// (nor on a naive-suppression RECOVERY dead-end). Home + Train now render a
// one-tap PRO `PhaseGeneratingCard` on expiry instead, and the splash records
// the failure via telemetry instead of a swallowed debugPrint.
//
// Home + Train are heavy ConsumerWidgets whose full pump needs the whole
// provider graph, so the guard is pinned SOURCE-anchored (comment-stripped per
// feedback_source_grep_strip_comments_first) — it FAILS if the isPro guard or
// the PRO card is removed. The `PhaseGeneratingCard` itself IS pumpable in
// isolation, so its actionable recourse CTA gets a real behavioral widget test.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/features/train/widgets/phase_generating_card.dart';

String _stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

void main() {
  final home = _stripComments(
      File('lib/features/home/screens/home_screen.dart').readAsStringSync());
  final train = _stripComments(
      File('lib/features/train/screens/train/screen.dart').readAsStringSync());
  final splash = _stripComments(
      File('lib/features/auth/screens/splash_screen.dart').readAsStringSync());
  final advance = _stripComments(
      File('lib/shared/services/pro_phase_advance.dart').readAsStringSync());
  final card = _stripComments(
      File('lib/features/train/widgets/phase_generating_card.dart')
          .readAsStringSync());

  group('Home expiry surface is PRO-aware (REG-1)', () {
    test('a PRO user gets PhaseGeneratingCard, guarded by reactive isPro', () {
      expect(home.contains('ref.watch(subscriptionInfoProvider).isPro'), isTrue,
          reason: 'isPro must be watched REACTIVELY (H-1), not snapshotted');
      expect(
          RegExp(r'if \(isPro\)\s*\{\s*return PhaseGeneratingCard')
              .hasMatch(home),
          isTrue,
          reason: 'the expired branch must route a PRO to PhaseGeneratingCard');
    });
    test('a FREE user still gets the 3-door PlanExpiredCard', () {
      expect(home.contains('PlanExpiredCard('), isTrue,
          reason: 'free-tier expiry recovery is unchanged');
    });
  });

  group('Train expiry surface is PRO-aware (REG-1)', () {
    test('reactive isPro drives the expired ternary', () {
      expect(
          train.contains('final isPro = ref.watch(subscriptionInfoProvider).isPro'),
          isTrue);
      expect(RegExp(r'isPro\s*\?\s*PhaseGeneratingCard').hasMatch(train), isTrue,
          reason: 'PRO → PhaseGeneratingCard; free → PlanExpiredCard');
      expect(train.contains('PlanExpiredCard('), isTrue,
          reason: 'free-tier expiry recovery is unchanged on Train too');
    });
  });

  group('Splash auto-advance no longer swallows failures (REG-1)', () {
    test('delegates to the shared advance + records failures via telemetry', () {
      expect(splash.contains('advanceProPhaseIfExpired(ref)'), isTrue,
          reason: 'splash + the card share one code path');
      expect(splash.contains("reason: 'splash_auto_advance_phase'"), isTrue,
          reason: 'the fire-and-forget catch must record the failure');
      expect(
          splash.contains(
              "debugPrint('[splash._autoGenerateNextPhaseForPro]"),
          isFalse,
          reason: 'the silent debugPrint-only swallow is the REG-1 root cause');
    });
  });

  group('Shared advance function guards keep redundant calls safe', () {
    test('advanceProPhaseIfExpired is isPro + isPhaseExpired gated', () {
      expect(
          advance.contains('Future<bool> advanceProPhaseIfExpired(WidgetRef ref)'),
          isTrue);
      expect(advance.contains('.isPro()'), isTrue,
          reason: 'non-PRO must early-return false');
      expect(advance.contains('.isPhaseExpired()'), isTrue,
          reason: 'a second concurrent call after generation must no-op');
      expect(advance.contains('autoGenerateNextPhaseIfNeeded'), isTrue);
    });
  });

  group('PhaseGeneratingCard is double-tap guarded + telemetered', () {
    test('the CTA calls the shared advance, guarded by _busy', () {
      expect(card.contains('advanceProPhaseIfExpired(ref)'), isTrue);
      expect(card.contains('if (_busy) return'), isTrue,
          reason: 'double-tap must not double-generate');
      expect(card.contains('ErrorTelemetry.recordNonFatal'), isTrue,
          reason: 'a generation failure must be recorded, not swallowed');
    });

    testWidgets('renders an actionable regenerate CTA (PRO recourse)',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: PhaseGeneratingCard()),
          ),
        ),
      );
      await tester.pump(); // runs the (safe, self-guarded) impression log
      expect(find.text('Phase complete, Officer.'), findsOneWidget);
      expect(find.textContaining('Generate next phase'), findsOneWidget,
          reason: 'the paying user must have a tappable way forward');
      // The CTA is a gesture target (not a dead placeholder like the bug it fixes).
      expect(find.byType(GestureDetector), findsWidgets);
    });
  });
}
