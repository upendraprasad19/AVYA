// Regression contract for bug e2b8a4 (2026-09-19, live web E2E — 3rd
// finding on this bug id): on a wide (desktop-browser) viewport, `MobileFrame`
// (lib/app.dart, formerly private `_MobileFrame`) visually constrains the
// app to a narrow phone-shaped box via layout (`Container(width:, height:)`
// + `ClipRect`) but never gave its `child` a matching `MediaQuery` — every
// descendant, including root-navigator overlay content, still read the
// OUTER (e.g. 1280x720 desktop) size via `MediaQuery.of(context)`.
//
// `showTimePicker`/`showDatePicker` (default `useRootNavigator: true`)
// insert their dialog into the Navigator's Overlay, which lives INSIDE
// `child` — so the dialog chose its portrait/landscape layout and centered
// itself against the wrong, far larger, LANDSCAPE-shaped size (1280x720)
// while actually being painted and clipped inside the narrow PORTRAIT frame
// box (~322x652 at that viewport). Live-confirmed via a `debugPrint` of
// `MediaQuery.sizeOf(context)` immediately before calling `showTimePicker`
// in the dev panel's "Test time picker (NO builder)" QA button: it printed
// the OUTER 1280x720, not the frame's actual ~322x652 content box. This
// explains why the dial + OK/Cancel row rendered as genuinely absent while
// the hour:minute header did render — only the slice of the (wrongly
// landscape-laid-out, wrongly centered) dialog that happened to fall inside
// the narrow clipped window was visible. It also explains why the bug
// persisted identically with or without `responsivePickerBuilder`'s own
// theme + `ConstrainedBox` fix: that fix reads `MediaQuery.sizeOf(context)`
// too, and got the same wrong (outer) value.
//
// Fixed by wrapping `child` in a `MediaQuery` reporting the frame's real
// inner content size (frame width x (frame height - notch - home
// indicator)), so every descendant — including dialogs raised on the root
// navigator — lays out against the box it's actually clipped to.
//
// NOTE ON WHAT THIS FILE CANNOT PROVE, stated so nobody re-attempts it as
// "obviously easy": an end-to-end widget test that pumps a bare
// showTimePicker inside MobileFrame and checks `find.text('OK')` /
// `tester.getSize()` does NOT discriminate fixed-vs-broken — tried and
// mutation-disproven (2026-09-19). `ClipRect` only affects the PAINT phase;
// `find`/`getSize` operate on the LAYOUT tree, which flutter_test still
// resolves correctly regardless of what MediaQuery.size claims, because
// `_TimePickerDialogState`'s own `LayoutBuilder` clamps against the REAL
// incoming BoxConstraints (genuinely bounded by MobileFrame's real
// Container/ClipRect), not against MediaQuery.size. A probe test that
// printed `MediaQuery.sizeOf` inside the dialog's own builder confirmed it
// reads the wrong 1280x720 EVEN with the fix reverted, yet the dialog's
// rendered outer size still came out portrait-shaped (~317x647) — Flutter
// silently absorbs the mismatch at the constraint level, in a way a
// widget test cannot tell apart from the fixed case. The tests below (the
// direct `MediaQuery.of(context)` capture) are the actual, mutation-proven
// regression pin; the live-browser evidence (screenshots + the DIAG
// debugPrint quoted above) is what proves the VISUAL symptom is fixed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/app.dart';

void main() {
  group('e2b8a4 — MobileFrame propagates its REAL content size via MediaQuery', () {
    testWidgets(
        'wide (desktop) viewport: child sees the frame\'s inner content '
        'size, not the outer window size', (tester) async {
      // A landscape-shaped desktop browser window — the exact shape that
      // triggered the bug live (1280x720).
      const outerSize = Size(1280, 720);
      const outerData = MediaQueryData(
        size: outerSize,
        // Deliberately non-zero + distinguishable from the zero the frame
        // resets to, so the assertions below prove an actual OVERRIDE
        // happened rather than coincidentally matching a default.
        viewInsets: EdgeInsets.only(bottom: 40),
        viewPadding: EdgeInsets.only(top: 24),
        padding: EdgeInsets.only(top: 24),
      );

      late MediaQueryData captured;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: outerData,
            child: MobileFrame(
              child: Builder(builder: (context) {
                captured = MediaQuery.of(context);
                return const SizedBox.shrink();
              }),
            ),
          ),
        ),
      );

      // Independently re-derive the expected content box using the same
      // formula MobileFrame uses, so this test doesn't hardcode a value
      // that silently drifts from the widget's own clamp/aspect-ratio logic.
      const maxH = 844.0;
      const maxW = 390.0;
      const notchHeight = 36.0;
      const homeIndicatorHeight = 8.0;
      // e2b8a4 round-1 review finding: Container's Border.all implies
      // decoration-padding on this axis too, so the reported size must
      // subtract it on BOTH width and height, not just clamp the outer
      // frame dimensions verbatim.
      const frameBorderWidth = 2.5;
      final expectedFrameH = (outerSize.height - 24).clamp(400.0, maxH);
      final expectedFrameW =
          (expectedFrameH / maxH * maxW).clamp(300.0, maxW);
      final expectedContentWidth = expectedFrameW - (frameBorderWidth * 2);
      final expectedContentHeight = expectedFrameH -
          (frameBorderWidth * 2) -
          notchHeight -
          homeIndicatorHeight;

      expect(captured.size.width, closeTo(expectedContentWidth, 0.01),
          reason: 'e2b8a4: child must see the frame\'s actual clipped '
              'width (net of the frame border\'s decoration-padding), not '
              'the outer 1280 and not the bare frame width either — '
              'otherwise a root-navigator dialog centers itself against '
              'the wrong (far wider, or merely approximate) box');
      expect(captured.size.height, closeTo(expectedContentHeight, 0.01),
          reason: 'e2b8a4: child must see the frame\'s actual content '
              'height (frame height minus notch and home-indicator bars), '
              'not the outer 720 — this is what flips a dialog\'s '
              'landscape/portrait layout choice');
      // The reported size must be genuinely PORTRAIT-shaped (taller than
      // wide) even though the outer window is landscape-shaped — this is
      // the exact flag Flutter's pickers use to choose their layout, and
      // is why the pre-fix code silently chose the wrong one.
      expect(captured.size.height, greaterThan(captured.size.width),
          reason: 'e2b8a4: the frame\'s real content box is portrait — a '
              'picker computing orientation from the unfixed outer size '
              'would wrongly conclude landscape');

      expect(captured.viewInsets, EdgeInsets.zero,
          reason: 'e2b8a4: the frame draws its own fake device chrome; '
              'the real desktop browser\'s viewInsets must not leak through');
      expect(captured.viewPadding, EdgeInsets.zero);
      expect(captured.padding, EdgeInsets.zero);
    });

    testWidgets(
        'narrow (real mobile) viewport: child receives the ORIGINAL '
        'MediaQuery unchanged — no frame, no override', (tester) async {
      const outerSize = Size(400, 800);
      const outerData = MediaQueryData(
        size: outerSize,
        viewInsets: EdgeInsets.only(bottom: 40),
        viewPadding: EdgeInsets.only(top: 24),
        padding: EdgeInsets.only(top: 24),
      );

      late MediaQueryData captured;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: outerData,
            child: MobileFrame(
              child: Builder(builder: (context) {
                captured = MediaQuery.of(context);
                return const SizedBox.shrink();
              }),
            ),
          ),
        ),
      );

      expect(captured, outerData,
          reason: 'e2b8a4: a real phone-width viewport must pass straight '
              'through with no frame and no MediaQuery override at all — '
              'this must not regress while fixing the wide-viewport case');
    });
  });
}
