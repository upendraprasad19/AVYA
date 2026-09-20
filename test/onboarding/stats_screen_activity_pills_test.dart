// Regression contract for the founder-reported "Stats screen activity pills
// unresponsive" symptom (onboarding batch, 2026-09-19, bug e2b8a4 finding 3).
// StatsScreen (lib/features/onboarding/screens/stats_screen.dart) had ZERO
// prior test coverage — this is the first test to actually pump it.
//
// Writer: `_activitySelector()`'s `GestureDetector.onTap` (stats_screen.dart
// ~:282) calls `setState(() => _activity = opt.$2)`. Reader: the same
// method's `Container.decoration.color`, which switches between
// `AppColors.accent` (selected) and `AppColors.card` (unselected) based on
// `_activity == opt.$2`.
//
// `/onboarding/stats` requires an authenticated session (the route bounces
// to sign-in for a signed-out user) and driving a real sign-in is a
// prohibited agent action, so this widget test drives the exact
// gesture-handling logic StatsScreen ships (tap → setState → color swap)
// directly, with no auth dependency — found NO defect: all four pills
// (SEDENTARY/LIGHT/MODERATE/HEAVY) register taps and update selection
// correctly, including re-selecting the already-active pill and the
// pre-selected default ('moderate').
//
// LIVE-VERIFIED (2026-09-19): a temporary dev-panel button (since removed)
// pushed StatsScreen directly — bypassing the router's auth gate the same
// way `/dev` itself is always reachable — and drove all four pills in the
// real Browser pane, under MobileFrame, at the exact desktop-shaped viewport
// that broke bug e2b8a4's OTHER finding (the wake-time picker, see
// mobile_frame_mediaquery_test.dart). All four selected/deselected
// correctly with no console errors. Unlike the time-picker dialog,
// `_activitySelector()` reads no MediaQuery size/orientation and raises no
// root-navigator overlay, so it was never structurally exposed to that bug
// in the first place. Conclusion: no independent StatsScreen defect exists.
// The founder's friend most likely described the SAME wake-time-picker
// lockup (severe enough that the founder's own account needed a Remote
// Control workaround to escape it) rather than a distinct third bug.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/onboarding/screens/stats_screen.dart';
import 'package:icanbefitter/core/theme/colors.dart';

void main() {
  Future<void> pumpStats(WidgetTester tester, {String? initialActivity}) {
    return tester.pumpWidget(
      MaterialApp(
        home: StatsScreen(
          goal: 'build_muscle',
          initial: initialActivity == null
              ? null
              : {'activity_level': initialActivity},
        ),
      ),
    );
  }

  Color pillColor(WidgetTester tester, String label) {
    // The pill's own Container directly wraps its Text — the NEAREST
    // Container ancestor, not just any Container ancestor (WardFrame /
    // Scaffold internals also introduce Container ancestors further up).
    final container = tester.widget<Container>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first,
    );
    return (container.decoration as BoxDecoration).color as Color;
  }

  testWidgets('default selection is MODERATE (pre-selected accent fill)',
      (tester) async {
    await pumpStats(tester);
    expect(pillColor(tester, 'MODERATE'), AppColors.accent,
        reason:
            'stats_screen.dart seeds _activity to "moderate" when no initial '
            'value is supplied — MODERATE must render pre-selected');
    expect(pillColor(tester, 'SEDENTARY'), AppColors.card,
        reason: 'every other pill must render unselected');
  });

  for (final target in ['SEDENTARY', 'LIGHT', 'MODERATE', 'HEAVY']) {
    testWidgets('tapping $target selects it and deselects the others',
        (tester) async {
      await pumpStats(tester, initialActivity: 'moderate');

      await tester.tap(find.text(target));
      await tester.pump();

      for (final label in ['SEDENTARY', 'LIGHT', 'MODERATE', 'HEAVY']) {
        expect(
          pillColor(tester, label),
          label == target ? AppColors.accent : AppColors.card,
          reason: label == target
              ? 'tapping $target must select it (accent fill) — this is '
                  'the exact gesture the founder reported as unresponsive'
              : '$label must deselect when a different pill is tapped',
        );
      }
    });
  }

  testWidgets('tapping the already-selected pill keeps it selected',
      (tester) async {
    await pumpStats(tester, initialActivity: 'heavy');

    await tester.tap(find.text('HEAVY'));
    await tester.pump();

    expect(pillColor(tester, 'HEAVY'), AppColors.accent,
        reason: 're-tapping the active pill must not toggle it off — '
            'the writer unconditionally sets _activity, it does not toggle');
  });
}
