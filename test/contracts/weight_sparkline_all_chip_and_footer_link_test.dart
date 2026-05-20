// Bug 2026-05-20 (diagnose b3f7a2) regression test — pins the
// WeightSparkline dashboard widget to expose an `all` time-range chip
// AND a `View full history →` footer link to /profile/reports.
//
// Pre-fix the chip set was hardcoded to `['7d', '30d', '90d']` per the
// original `daily.jsx` handoff. Founder asked "what if user wants to
// see more than 90 days?" — option C locked: hybrid (ALL chip on
// dashboard + link to Reports).

import 'dart:io';
import 'package:test/test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final src =
      File('lib/features/home/widgets/weight_sparkline.dart').readAsStringSync();
  final stripped = _stripComments(src);

  group('WeightSparkline — ALL chip + view-full-history link', () {
    test('go_router is imported (needed for context.go navigation)', () {
      expect(
        stripped.contains("import 'package:go_router/go_router.dart'"),
        isTrue,
        reason: "weight_sparkline.dart must import go_router so the "
            "'View full history →' link can context.go('/profile/reports').",
      );
    });

    test('_ranges constant includes the "all" entry', () {
      // Match any single-quoted 'all' inside a list literal — robust to
      // formatting tweaks (trailing comma, line breaks).
      expect(
        RegExp(r"_ranges\s*=\s*\[[^\]]*'all'").hasMatch(stripped),
        isTrue,
        reason: "_ranges must include 'all' so the dashboard exposes a "
            "full-history chip. Pre-fix the constant was "
            "['7d', '30d', '90d'] only.",
      );
    });

    test('_filteredEntries switch handles the "all" branch', () {
      // The switch case can be written `'all' => ...` or via the default
      // arm. We require the explicit arm so the intent is grep-able.
      expect(
        RegExp(r"'all'\s*=>").hasMatch(stripped),
        isTrue,
        reason: "_filteredEntries switch must have an explicit `'all' =>` "
            "case rather than relying on the default arm. Required for "
            "intent legibility.",
      );
    });

    test('footer link navigates to /profile/reports', () {
      expect(
        stripped.contains("context.go('/profile/reports')"),
        isTrue,
        reason: "The 'View full history →' footer link must call "
            "context.go('/profile/reports') so the user can reach the "
            "rich Reports view (1Y/6M/3M/1M/1W chips + projection).",
      );
    });

    test('footer link uses the agreed copy "View full history"', () {
      expect(
        stripped.contains('View full history'),
        isTrue,
        reason: "Footer link copy must be 'View full history →'. If you "
            "want to change the copy, update this test + the diagnose-doc "
            "in the same commit.",
      );
    });
  });
}
