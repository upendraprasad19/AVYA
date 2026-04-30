# APK Test #6 Plan D — Profile Restructure (Rank Pill + Indian Navy Insignia)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rank takes prominent position at top of Profile via WardRankPill (replacing Edit Profile button). Inline accordion expansion shows Service Record. Edit Profile moves to first row of SETTINGS. Predictions move to REPORTS as list row with preview + bottom sheet on tap. Streak/freeze removed from Profile. Indian Navy rank insignia rendered via Flutter CustomPaint for all 11 ranks (incl. new Lt).

**Architecture:** Two new Wardroom primitives (WardRankPill + WardRankInsignia). WardRankPill uses AnimationController for accordion expansion below the pill. WardRankInsignia uses CustomPaint with parametrized stripe count + chevron/anchor/crown shapes per rank. Profile ListView body re-ordered.

**Estimated effort:** 5-7h.

**Spec reference:** `docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md` §7.

---

## Prerequisites

- Plan A has run: branch `feat/apk-test-6-batch` exists off `feat/apk-test-3-batch` tip and is checked out.
- Plan F (Theme G — rank ladder rebalance) **does not** need to land first. This plan paints insignia for all 11 codes including `Lt`; `kRankLadder` may still hold 10 entries when Plan D ships — `WardRankInsignia` keys off the `rankCode` string, not the ladder list. The Lt painter is in place ready for Plan F to wire it up.
- No Test #5 work (`feat/apk-test-5-batch`) has been merged into this branch.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `lib/shared/widgets/wardroom/ward_rank_insignia.dart` | CREATE | NEW — CustomPaint insignia for 11 ranks |
| `lib/shared/widgets/wardroom/ward_rank_pill.dart` | CREATE | NEW — accordion pill at top of Profile |
| `lib/shared/widgets/wardroom/wardroom.dart` | MODIFY | Export both new primitives |
| `lib/features/profile/screens/profile_screen.dart` | MODIFY | Re-order ListView body, remove top Edit Profile button + status strip + Service Record + YOUR PREDICTION section, add WardRankPill at top, add Predictions row in REPORTS, add Edit Profile row first in SETTINGS |
| `test/wardroom/ward_rank_insignia_test.dart` | CREATE | Golden tests for all 11 ranks at 24dp + 48dp |
| `test/wardroom/ward_rank_pill_test.dart` | CREATE | Smoke tests — collapsed render, tap expands, builder called once when expanded |
| `test/profile/profile_screen_layout_test.dart` | CREATE | Layout test — section order + no Edit Profile at top + Predictions in REPORTS + no streak/freeze on Profile |
| `docs/superpowers/notes/2026-05-01-profile-restructure-smoke.md` | CREATE | C13/C14/C15 verification log |

---

## Task D-1 — Create WardRankInsignia primitive (CustomPaint)

**Files:** Create `lib/shared/widgets/wardroom/ward_rank_insignia.dart`.

This widget keys off the `rankCode` string. The painter dispatch is internal — callers just pass `rankCode: 'LS'` and the right geometry is drawn. `AppColors.accent` (Campaign Gold) is the default colour.

- [ ] **Step 1: Create the file**

```dart
// lib/shared/widgets/wardroom/ward_rank_insignia.dart
//
// Indian Navy rank insignia rendered via CustomPaint. One widget,
// 11 painters, dispatched by `rankCode`.
//
// Sizes:
//   24dp — used inside WardRankPill (top of Profile)
//   48dp — used inside Service Record popups + ladder detail sheets
//   16dp — used inside compact RankChip variants (existing widget)
//
// All shapes drawn with `AppColors.accent` (Campaign Gold) by default.
// Pass `color:` to override (e.g. dimmed past-rank rows).
//
// Source: docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md §7.3.

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class WardRankInsignia extends StatelessWidget {
  const WardRankInsignia({
    super.key,
    required this.rankCode,
    required this.size,
    this.color,
  });

  final String rankCode;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final paint = color ?? AppColors.accent;

    final painter = _painterForCode(rankCode, paint);
    if (painter == null) {
      // Fallback: text-only label inside a gold-ringed circle.
      return _TextFallback(rankCode: rankCode, size: size, color: paint);
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: painter),
    );
  }

  CustomPainter? _painterForCode(String code, Color color) {
    switch (code) {
      case 'SD2':
        // Text-only fallback (no military insignia for entry rank).
        return null;
      case 'SD1':
        return _ChevronPainter(color: color);
      case 'LS':
        return _AnchorPainter(color: color);
      case 'PO':
        return _AnchorWithCrownPainter(color: color);
      case 'CPO':
        return _CrossedAnchorsPainter(color: color);
      case 'MCPO':
        return _CrownStarCrossedAnchorsPainter(color: color);
      case 'SubLt':
        return _StripePainter(color: color, thickStripes: 0, thinStripes: 1, curl: true);
      case 'Lt':
        return _StripePainter(color: color, thickStripes: 2, thinStripes: 0, curl: false);
      case 'LtCdr':
        return _StripePainter(color: color, thickStripes: 2, thinStripes: 1, curl: false);
      case 'Cdr':
        return _StripePainter(color: color, thickStripes: 3, thinStripes: 0, curl: false);
      case 'Capt':
        return _StripePainter(color: color, thickStripes: 4, thinStripes: 0, curl: false);
      default:
        return null;
    }
  }
}

// ── Text fallback (used by SD2 + unknown codes) ──────────────────

class _TextFallback extends StatelessWidget {
  const _TextFallback({
    required this.rankCode,
    required this.size,
    required this.color,
  });

  final String rankCode;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.2),
        ),
        child: Center(
          child: Text(
            rankCode.toUpperCase(),
            style: AppTypography.mono.copyWith(
              fontSize: size * 0.32,
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chevron (SD1) ────────────────────────────────────────────────

class _ChevronPainter extends CustomPainter {
  _ChevronPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.13
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.18, h * 0.62)
      ..lineTo(w * 0.50, h * 0.30)
      ..lineTo(w * 0.82, h * 0.62);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.color != color;
}

// ── Anchor (LS) ──────────────────────────────────────────────────

class _AnchorPainter extends CustomPainter {
  _AnchorPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _drawAnchor(canvas, size, color, scale: 1.0, offsetY: 0);
  }

  @override
  bool shouldRepaint(_AnchorPainter old) => old.color != color;
}

void _drawAnchor(Canvas canvas, Size size, Color color,
    {required double scale, required double offsetY}) {
  final stroke = Paint()
    ..color = color
    ..strokeWidth = size.width * 0.08 * scale
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  final fill = Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  final w = size.width;
  final h = size.height;
  final cx = w * 0.5;
  final topY = h * (0.18 + offsetY);
  final shankBottomY = h * (0.66 + offsetY);
  final crownY = h * (0.82 + offsetY);

  // Crown ring at top
  final ringR = w * 0.08 * scale;
  canvas.drawCircle(Offset(cx, topY), ringR, stroke);

  // Shank
  canvas.drawLine(Offset(cx, topY + ringR), Offset(cx, shankBottomY), stroke);

  // Stock (horizontal crossbar)
  final stockHalf = w * 0.18 * scale;
  final stockY = h * (0.32 + offsetY);
  canvas.drawLine(
      Offset(cx - stockHalf, stockY), Offset(cx + stockHalf, stockY), stroke);

  // Crown (curved arms)
  final armHalf = w * 0.26 * scale;
  final armPath = Path()
    ..moveTo(cx - armHalf, shankBottomY)
    ..quadraticBezierTo(cx - armHalf * 0.6, crownY, cx, shankBottomY + h * 0.04 * scale)
    ..quadraticBezierTo(cx + armHalf * 0.6, crownY, cx + armHalf, shankBottomY)
    ..close();
  canvas.drawPath(armPath, fill);
}

// ── Anchor + Crown (PO) ──────────────────────────────────────────

class _AnchorWithCrownPainter extends CustomPainter {
  _AnchorWithCrownPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Crown above
    _drawCrown(canvas, size, color,
        cx: size.width * 0.5, cy: size.height * 0.16, width: size.width * 0.32);
    // Anchor below — shrunk to 80% so they fit together at 24dp
    _drawAnchor(canvas, size, color, scale: 0.78, offsetY: 0.12);
  }

  @override
  bool shouldRepaint(_AnchorWithCrownPainter old) => old.color != color;
}

void _drawCrown(Canvas canvas, Size size, Color color,
    {required double cx, required double cy, required double width}) {
  final fill = Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  final halfW = width / 2;
  final h = width * 0.55;

  // Three arches with small balls on top.
  final base = Path()
    ..moveTo(cx - halfW, cy + h * 0.4)
    ..lineTo(cx + halfW, cy + h * 0.4)
    ..lineTo(cx + halfW, cy + h * 0.55)
    ..lineTo(cx - halfW, cy + h * 0.55)
    ..close();
  canvas.drawPath(base, fill);

  // Three small balls on top (jewels).
  final ballR = width * 0.07;
  canvas.drawCircle(Offset(cx - halfW * 0.7, cy - h * 0.05), ballR, fill);
  canvas.drawCircle(Offset(cx, cy - h * 0.18), ballR * 1.1, fill);
  canvas.drawCircle(Offset(cx + halfW * 0.7, cy - h * 0.05), ballR, fill);

  // Connect balls to base with thin lines.
  final stroke = Paint()
    ..color = color
    ..strokeWidth = width * 0.06
    ..style = PaintingStyle.stroke;
  canvas.drawLine(
      Offset(cx - halfW * 0.7, cy - h * 0.05), Offset(cx - halfW * 0.6, cy + h * 0.4), stroke);
  canvas.drawLine(Offset(cx, cy - h * 0.18), Offset(cx, cy + h * 0.4), stroke);
  canvas.drawLine(
      Offset(cx + halfW * 0.7, cy - h * 0.05), Offset(cx + halfW * 0.6, cy + h * 0.4), stroke);
}

// ── Crossed Anchors (CPO) ────────────────────────────────────────

class _CrossedAnchorsPainter extends CustomPainter {
  _CrossedAnchorsPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    // First anchor rotated -25°
    canvas.save();
    canvas.rotate(-0.436);
    canvas.translate(-size.width / 2, -size.height / 2);
    _drawAnchor(canvas, size, color, scale: 0.85, offsetY: 0);
    canvas.restore();

    // Second anchor rotated +25°
    canvas.save();
    canvas.rotate(0.436);
    canvas.translate(-size.width / 2, -size.height / 2);
    _drawAnchor(canvas, size, color, scale: 0.85, offsetY: 0);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CrossedAnchorsPainter old) => old.color != color;
}

// ── Crown + Star + Crossed Anchors (MCPO) ────────────────────────

class _CrownStarCrossedAnchorsPainter extends CustomPainter {
  _CrownStarCrossedAnchorsPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Star at very top
    _drawStar(canvas, color,
        cx: size.width * 0.5, cy: size.height * 0.1, radius: size.width * 0.08);

    // Crown below star
    _drawCrown(canvas, size, color,
        cx: size.width * 0.5, cy: size.height * 0.26, width: size.width * 0.28);

    // Crossed anchors below crown — shrunk + offset down
    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.62);
    canvas.scale(0.7);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.save();
    canvas.rotate(-0.436);
    canvas.translate(-size.width / 2, -size.height / 2);
    _drawAnchor(canvas, size, color, scale: 0.85, offsetY: 0);
    canvas.restore();
    canvas.save();
    canvas.rotate(0.436);
    canvas.translate(-size.width / 2, -size.height / 2);
    _drawAnchor(canvas, size, color, scale: 0.85, offsetY: 0);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CrownStarCrossedAnchorsPainter old) => old.color != color;
}

void _drawStar(Canvas canvas, Color color,
    {required double cx, required double cy, required double radius}) {
  final fill = Paint()
    ..color = color
    ..style = PaintingStyle.fill;
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final angle = (i * 36 - 90) * 3.14159265 / 180;
    final r = i.isEven ? radius : radius * 0.45;
    final x = cx + r * (i.isEven ? _cos(angle) : _cos(angle));
    final y = cy + r * (i.isEven ? _sin(angle) : _sin(angle));
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  canvas.drawPath(path, fill);
}

double _cos(double a) {
  // dart:math is the canonical source; this small wrapper keeps the
  // painter file self-contained for the golden test.
  return _internalMathCos(a);
}

double _sin(double a) => _internalMathSin(a);

// Re-export of dart:math via aliases so the painter file imports
// stay tidy. Using these names rather than direct `math.cos` keeps
// the per-painter private helpers symmetric with `_drawAnchor` etc.
double _internalMathCos(double a) {
  return _cosImpl(a);
}

double _internalMathSin(double a) {
  return _sinImpl(a);
}

// Pull in dart:math via a private import alias above this line in
// the file (handled by the import block at the top during Step 1
// — ADD `import 'dart:math' as math;` to the file imports).

double _cosImpl(double a) => math.cos(a);
double _sinImpl(double a) => math.sin(a);

// ── Stripes (officer ranks: SubLt / Lt / LtCdr / Cdr / Capt) ─────

class _StripePainter extends CustomPainter {
  _StripePainter({
    required this.color,
    required this.thickStripes,
    required this.thinStripes,
    required this.curl,
  });

  final Color color;
  final int thickStripes;
  final int thinStripes;
  final bool curl; // SubLt — small loop above the topmost stripe

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Layout: stripes stack vertically inside a "shoulder board" rectangle
    // that occupies the central 80% of the box. Thick = h*0.10, thin = h*0.05,
    // gap = h*0.04 between stripes.
    const thickH = 0.10;
    const thinH = 0.05;
    const gap = 0.04;

    final totalStripes = thickStripes + thinStripes;
    final totalH = thickStripes * thickH + thinStripes * thinH +
        (totalStripes - 1).clamp(0, totalStripes) * gap;
    final centerY = 0.5;
    var y = centerY - totalH / 2;

    for (var i = 0; i < thickStripes; i++) {
      final rect = Rect.fromLTWH(w * 0.15, h * y, w * 0.70, h * thickH);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(h * 0.012)), fill);
      y += thickH + gap;
    }
    for (var i = 0; i < thinStripes; i++) {
      final rect = Rect.fromLTWH(w * 0.18, h * y, w * 0.64, h * thinH);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(h * 0.008)), fill);
      y += thinH + gap;
    }

    if (curl) {
      // Small loop above the (single) thin stripe — Sub-Lieutenant detail.
      final loopCenter = Offset(w * 0.5, h * (centerY - thinH / 2 - gap - 0.04));
      final loopR = h * 0.05;
      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.02;
      canvas.drawCircle(loopCenter, loopR, stroke);
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) =>
      old.color != color ||
      old.thickStripes != thickStripes ||
      old.thinStripes != thinStripes ||
      old.curl != curl;
}
```

> **Note for the implementer:** the file as written above is structured for clarity in the plan; before saving, **collapse the `_cos` / `_sin` indirection** down to a single `import 'dart:math' as math;` at the top and replace the `_cos(x) / _sin(x)` calls with `math.cos(x) / math.sin(x)` directly inside `_drawStar`. The wrapping helpers were a documentation artefact. The final import block at the top of the file should be exactly:
>
> ```dart
> import 'dart:math' as math;
>
> import 'package:flutter/material.dart';
> import 'package:icanbefitter/core/theme/colors.dart';
> import 'package:icanbefitter/core/theme/typography.dart';
> ```
>
> and `_drawStar` should call `math.cos(angle)` / `math.sin(angle)` directly. Delete `_cos`, `_sin`, `_internalMathCos`, `_internalMathSin`, `_cosImpl`, `_sinImpl` entirely.

- [ ] **Step 2: Verify it compiles**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter analyze lib/shared/widgets/wardroom/ward_rank_insignia.dart
```

Expect: `No issues found!`

- [ ] **Step 3: Smoke render at runtime (optional but recommended)**

Wrap one painter in a temporary scaffold and run the dev flavour to eyeball it. Skip if you trust the goldens in Task D-3.

- [ ] **Step 4: Commit**

```bash
git add lib/shared/widgets/wardroom/ward_rank_insignia.dart
git commit -m "$(cat <<'EOF'
feat(wardroom): WardRankInsignia primitive (Test #6 D-1)

CustomPaint dispatch by rankCode for all 11 Indian Navy ranks:
- SD2 — text fallback (gold-ringed circle)
- SD1 — chevron
- LS — anchor
- PO — anchor + crown
- CPO — crossed anchors
- MCPO — crown + star + crossed anchors
- SubLt — 1 thin stripe + curl
- Lt — 2 thick stripes  (NEW, ladder additions)
- LtCdr — 2 thick + 1 thin
- Cdr — 3 thick stripes
- Capt — 4 thick stripes

Sizes: 16dp / 24dp / 48dp. Default colour AppColors.accent.

Spec: docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md §7.3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task D-2 — Add WardRankInsignia to Wardroom barrel

**Files:** `lib/shared/widgets/wardroom/wardroom.dart`.

- [ ] **Step 1: Open and add export**

Add (in alphabetical position, between `ward_rule.dart` and `ward_seal_badge.dart`):

```dart
export 'ward_rank_insignia.dart';
export 'ward_rank_pill.dart';
```

(The `ward_rank_pill.dart` export is added preemptively — its file is created in D-4.)

Also update the barrel header comment block to mention the new primitives. Replace the `* **Badge**     — [WardSealBadge]` line with:

```dart
/// * **Badge**     — [WardSealBadge], [WardRankInsignia]
/// * **Composite** — [WardRankPill]
```

- [ ] **Step 2: Verify**

```bash
flutter analyze lib/shared/widgets/wardroom/wardroom.dart
```

Expect: `No issues found!` (note: until D-4 lands the `ward_rank_pill.dart` export will fail — temporarily hold this commit until D-4 is ready, OR add only the `ward_rank_insignia.dart` export now and the pill export in D-5).

**Decision: split the barrel update across D-2 and D-5** so each commit compiles cleanly:

- D-2 adds **only** `export 'ward_rank_insignia.dart';`.
- D-5 adds `export 'ward_rank_pill.dart';` + the `**Composite**` doc line.

Re-run analyze after applying only the insignia export.

- [ ] **Step 3: Commit**

```bash
git add lib/shared/widgets/wardroom/wardroom.dart
git commit -m "$(cat <<'EOF'
feat(wardroom): export WardRankInsignia (Test #6 D-2)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task D-3 — Golden tests for all 11 insignia

**Files:** Create `test/wardroom/ward_rank_insignia_test.dart`.

Goldens lock visual stability — once accepted, any change to a painter shows up in the diff.

- [ ] **Step 1: Create the file**

```dart
// test/wardroom/ward_rank_insignia_test.dart
//
// Golden tests for all 11 Indian Navy rank insignia at 24dp (pill
// size) and 48dp (popup size).
//
// Run with `--update-goldens` once to seed PNGs into
// `test/wardroom/goldens/`. Subsequent runs just compare.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_insignia.dart';

const _ranks = [
  'SD2', 'SD1', 'LS', 'PO', 'CPO', 'MCPO',
  'SubLt', 'Lt', 'LtCdr', 'Cdr', 'Capt',
];

Widget _wrap(Widget child, double size) => MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF02070F),
        body: Center(
          child: SizedBox(width: size, height: size, child: child),
        ),
      ),
    );

void main() {
  for (final code in _ranks) {
    testWidgets('renders $code at 24dp', (tester) async {
      await tester.pumpWidget(
        _wrap(WardRankInsignia(rankCode: code, size: 24), 24),
      );
      await expectLater(
        find.byType(WardRankInsignia),
        matchesGoldenFile('goldens/insignia_${code.toLowerCase()}_24.png'),
      );
    });

    testWidgets('renders $code at 48dp', (tester) async {
      await tester.pumpWidget(
        _wrap(WardRankInsignia(rankCode: code, size: 48), 48),
      );
      await expectLater(
        find.byType(WardRankInsignia),
        matchesGoldenFile('goldens/insignia_${code.toLowerCase()}_48.png'),
      );
    });
  }

  testWidgets('unknown code falls back to text label', (tester) async {
    await tester.pumpWidget(
      _wrap(const WardRankInsignia(rankCode: 'XYZ', size: 24), 24),
    );
    expect(find.text('XYZ'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Seed the goldens**

```bash
flutter test test/wardroom/ward_rank_insignia_test.dart --update-goldens
```

Expect 22 PNGs created in `test/wardroom/goldens/insignia_*.png` plus the existing test passes.

- [ ] **Step 3: Re-run without `--update-goldens` to confirm parity**

```bash
flutter test test/wardroom/ward_rank_insignia_test.dart
```

Expect: all 23 tests pass (22 goldens + 1 text fallback).

- [ ] **Step 4: Commit**

```bash
git add test/wardroom/ward_rank_insignia_test.dart test/wardroom/goldens/
git commit -m "$(cat <<'EOF'
test(wardroom): goldens for WardRankInsignia (Test #6 D-3)

22 goldens (11 ranks × 2 sizes) + 1 text fallback test.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task D-4 — Create WardRankPill widget

**Files:** Create `lib/shared/widgets/wardroom/ward_rank_pill.dart`.

StatefulWidget. Internal `_expanded` bool + `AnimationController` (200ms ease-out). Pill collapsed = `[insignia 24dp] [shortCapsName mono caps] [chevron]`. Tap toggles. Expanded delegates content to `expandedContentBuilder` so the Profile screen owns the Service Record content (keeps the pill itself dumb + portable).

- [ ] **Step 1: Create the file**

```dart
// lib/shared/widgets/wardroom/ward_rank_pill.dart
//
// Rank pill at top of Profile. Displays [insignia] [shortCapsName]
// [chevron]. Tap toggles inline accordion expansion below the pill.
//
// Dumb in: rankCode + shortCapsName + expandedContentBuilder.
// The Profile screen owns the Service Record content via the
// builder slot — pill stays portable + testable.
//
// Animation: 200ms ease-out vertical expand. Chevron rotates 180°
// in the same window via Transform.rotate.
//
// Source: docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md §7.2.

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_insignia.dart';

class WardRankPill extends StatefulWidget {
  const WardRankPill({
    super.key,
    required this.rankCode,
    required this.shortCapsName,
    required this.expandedContentBuilder,
  });

  final String rankCode;
  final String shortCapsName;
  final Widget Function(BuildContext) expandedContentBuilder;

  @override
  State<WardRankPill> createState() => _WardRankPillState();
}

class _WardRankPillState extends State<WardRankPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _curve;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Pill (always visible) ────────────────────────────────
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bgRaise,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.35),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WardRankInsignia(rankCode: widget.rankCode, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.shortCapsName,
                    style: AppTypography.mono.copyWith(
                      fontSize: 12,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Expanded Service Record content ──────────────────────
        SizeTransition(
          sizeFactor: _curve,
          axisAlignment: -1.0, // grow downward
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: widget.expandedContentBuilder(context),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
flutter analyze lib/shared/widgets/wardroom/ward_rank_pill.dart
```

Expect: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/shared/widgets/wardroom/ward_rank_pill.dart
git commit -m "$(cat <<'EOF'
feat(wardroom): WardRankPill primitive (Test #6 D-4)

Stateful pill at top of Profile. Tap toggles a 200ms ease-out
inline accordion expansion below the pill. Service Record
content delegated to expandedContentBuilder (Profile owns it).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task D-5 — Add WardRankPill to barrel + smoke tests

**Files:** Modify `lib/shared/widgets/wardroom/wardroom.dart`. Create `test/wardroom/ward_rank_pill_test.dart`.

- [ ] **Step 1: Add the export**

Open `lib/shared/widgets/wardroom/wardroom.dart` and append (alphabetical, after `ward_rank_insignia.dart`):

```dart
export 'ward_rank_pill.dart';
```

Also update the doc-block at the top — replace the placeholder line added in D-2 with the final form:

```dart
/// * **Badge**     — [WardSealBadge], [WardRankInsignia]
/// * **Composite** — [WardRankPill]
```

- [ ] **Step 2: Create the smoke tests**

```dart
// test/wardroom/ward_rank_pill_test.dart
//
// Smoke tests for WardRankPill — collapsed render, tap expands,
// builder called once when expanded.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_pill.dart';

void main() {
  testWidgets('renders pill collapsed by default', (tester) async {
    var builderCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WardRankPill(
          rankCode: 'LS',
          shortCapsName: 'LEADING SEAMAN',
          expandedContentBuilder: (ctx) {
            builderCalls++;
            return const Text('SERVICE-RECORD-CONTENT');
          },
        ),
      ),
    ));

    expect(find.text('LEADING SEAMAN'), findsOneWidget);
    expect(find.text('SERVICE-RECORD-CONTENT'), findsNothing);
    // SizeTransition with sizeFactor = 0 may still build the child;
    // the assertion that matters is "0 builder invocations" which
    // proves we lazy-build only when expanded.
    expect(builderCalls, 0);
  });

  testWidgets('tap expands the pill and calls the builder', (tester) async {
    var builderCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WardRankPill(
          rankCode: 'LS',
          shortCapsName: 'LEADING SEAMAN',
          expandedContentBuilder: (ctx) {
            builderCalls++;
            return const Text('SERVICE-RECORD-CONTENT');
          },
        ),
      ),
    ));

    await tester.tap(find.text('LEADING SEAMAN'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(find.text('SERVICE-RECORD-CONTENT'), findsOneWidget);
    expect(builderCalls, 1);
  });

  testWidgets('second tap collapses the pill', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WardRankPill(
          rankCode: 'LS',
          shortCapsName: 'LEADING SEAMAN',
          expandedContentBuilder: (ctx) =>
              const Text('SERVICE-RECORD-CONTENT'),
        ),
      ),
    ));

    await tester.tap(find.text('LEADING SEAMAN'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.text('SERVICE-RECORD-CONTENT'), findsOneWidget);

    await tester.tap(find.text('LEADING SEAMAN'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.text('SERVICE-RECORD-CONTENT'), findsNothing);
  });
}
```

- [ ] **Step 3: Run the tests**

```bash
flutter test test/wardroom/ward_rank_pill_test.dart
```

Expect: 3 passed.

- [ ] **Step 4: Commit**

```bash
git add lib/shared/widgets/wardroom/wardroom.dart test/wardroom/ward_rank_pill_test.dart
git commit -m "$(cat <<'EOF'
feat(wardroom): export WardRankPill + smoke tests (Test #6 D-5)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task D-6 — Build the Service Record dropdown content helper

**Files:** Modify `lib/features/profile/screens/profile_screen.dart`.

Add a private `_buildRankServiceRecord(BuildContext, String currentRankCode)` method that returns the accordion content. Re-uses the existing `RankService` API (`getCurrentRank`, `getNextRank`, `getLadder`) so we don't duplicate gate logic.

- [ ] **Step 1: Locate the right region**

```bash
grep -n "Widget _buildPredictionCard\|Widget _build" lib/features/profile/screens/profile_screen.dart | head -10
```

Insert the new helper just above `_buildPredictionCard` (around line 1214 in the current file). Keep all rank-related helpers grouped.

- [ ] **Step 2: Add the helper**

```dart
// Near the other private builders inside _ProfileScreenState.
//
// Service Record dropdown content for WardRankPill.
//
// Renders:
//   - Current rank header (large insignia + display name + days held)
//   - Next 2-3 rungs as compact rows (insignia + shortName + gate copy)
//   - "View full roadmap →" button routing to /train/roadmap
//
// NO streak/freeze chips here (Plan D removed them from Profile entirely).
Widget _buildRankServiceRecord(BuildContext context, String currentRankCode) {
  final rankService = RankService.instance;
  final current = rankService.getCurrentRank();
  final ladder = rankService.getLadder();

  // Show current + next 2 (or terminal note if Captain).
  final currentIdx = ladder.indexWhere((e) => e.entry.code == current.entry.code);
  final upcomingCount = current.entry.isTerminal ? 0 : 2;
  final upcoming = (currentIdx >= 0 && currentIdx + 1 < ladder.length)
      ? ladder.skip(currentIdx + 1).take(upcomingCount).toList()
      : <LadderEntryView>[];

  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Eyebrow
        Text(
          'SERVICE RECORD',
          style: AppTypography.mono.copyWith(
            fontSize: 10,
            color: AppColors.textDim,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),

        // Current rank — large
        Row(
          children: [
            WardRankInsignia(rankCode: current.entry.code, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current.entry.displayName,
                    style: AppTypography.titleM.copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    current.entry.isTerminal
                        ? 'TERMINAL RANK'
                        : 'CURRENT',
                    style: AppTypography.mono.copyWith(
                      fontSize: 10,
                      color: AppColors.accent,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        if (upcoming.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.line2),
          const SizedBox(height: 12),
          // Upcoming rungs
          ...upcoming.map((view) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Opacity(
                      opacity: 0.55,
                      child: WardRankInsignia(
                        rankCode: view.entry.code,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            view.entry.shortName,
                            style: AppTypography.bodyM.copyWith(
                              color: AppColors.textDim,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (view.gateText != null)
                            Text(
                              view.gateText!,
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.textMute,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],

        const SizedBox(height: 12),

        // View full roadmap button
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.go('/train/roadmap'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              foregroundColor: AppColors.accent,
            ),
            child: Text(
              'View full roadmap →',
              style: AppTypography.bodyM.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
```

If `LadderEntryView` is not in scope, add the import:

```dart
import 'package:icanbefitter/core/services/rank_service.dart';
```

(this import already exists in many places in this file via `service_record_section.dart`; verify with `grep -n "rank_service" lib/features/profile/screens/profile_screen.dart` and add if missing).

- [ ] **Step 3: Verify it compiles**

```bash
flutter analyze lib/features/profile/screens/profile_screen.dart
```

Expect: 0 errors. Warnings about unused helpers are OK at this step — the helper gets wired up in D-7.

- [ ] **Step 4: Do not commit yet** — D-7 wires this helper into the ListView body, and we want the wiring + helper in a single commit so the diff is reviewable. Move on.

---

## Task D-7 — Replace Edit Profile button at top of Profile with WardRankPill

**Files:** `lib/features/profile/screens/profile_screen.dart`.

Three sub-changes inside this single task:

1. The existing top-of-page region renders `ProfileIdentity` with `onTapEdit: () => context.go('/profile/edit')`. We keep `ProfileIdentity` but pass a NEW callback (`onTapEdit: null` OR a no-op so the Edit button hides). Verify `ProfileIdentity` supports null `onTapEdit` — if not, add a parameter or omit the button rendering inline.
2. Below `ProfileIdentity` (and before the `_buildNutritionTargets` block), insert `WardRankPill`.
3. Remove the standalone `ServiceRecordSection` widget that currently lives further down (around line 534).

- [ ] **Step 1: Inspect ProfileIdentity for the edit-button hook**

```bash
grep -n "onTapEdit\|EditProfile\|_buildEditButton\|class ProfileIdentity" lib/features/profile/widgets/profile_identity.dart
```

If the widget always renders an Edit button when `onTapEdit != null`, our path is to pass `onTapEdit: null` (already nullable in most builds) OR to add a `showEditButton: false` flag. The safer route: open the file, locate the edit-button rendering inside `ProfileIdentity.build`, and gate it on `widget.onTapEdit != null`. If the gate is already there, pass `onTapEdit: null` from the screen.

- [ ] **Step 2: Update profile_screen.dart top region**

Locate the `ProfileIdentity` call (around line 483):

```dart
ProfileIdentity(
  // ... existing args ...
  onTapEdit: () => context.go('/profile/edit'),
)
```

Change to:

```dart
ProfileIdentity(
  // ... existing args (unchanged) ...
  onTapEdit: null,   // moved into SETTINGS section (D-9)
),
const SizedBox(height: 14),

// Plan D: rank pill replaces top Edit Profile button.
Padding(
  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
  child: WardRankPill(
    rankCode: RankService.instance.getCurrentRank().entry.code,
    shortCapsName:
        RankService.instance.getCurrentRank().entry.shortName.toUpperCase(),
    expandedContentBuilder: (ctx) =>
        _buildRankServiceRecord(ctx, RankService.instance.getCurrentRank().entry.code),
  ),
),
```

If `AppSpacing.screenPadding` is not in scope, use the same screen padding the rest of the file already uses (search the file for an existing `Padding` wrapper for guidance).

> **shortCapsName note:** `RankLadderEntry.shortName` (e.g. `'Leading Seaman'`, `'CDR'`) is the raw value. `.toUpperCase()` converts it to caps (e.g. `'LEADING SEAMAN'`, `'CDR'`). Spec §7.2 example values map exactly: `Seaman 2nd → SEAMAN 2ND`, `Leading Seaman → LEADING SEAMAN`, `CDR → CDR`. **Trade-off:** `'Seaman 2nd Class'.toUpperCase() = 'SEAMAN 2ND CLASS'` is slightly longer than spec's `'SEAMAN 2'`. Acceptable — the pill text uses 12sp mono and doesn't truncate at 360 dp width. If you find any rank where the cap-form runs over, override with a per-code map inline above the call site:
> ```dart
> const _shortCapsOverride = <String, String>{
>   'SD2': 'SEAMAN 2',
>   'SD1': 'SEAMAN 1',
>   'PO': 'PETTY OFFICER',
>   'CPO': 'CHIEF PO',
>   'MCPO': 'MASTER CHIEF',
>   'SubLt': 'SUB LT',
>   'LtCdr': 'LT CDR',
> };
> ```
> Use `_shortCapsOverride[code] ?? entry.shortName.toUpperCase()`.

- [ ] **Step 3: Remove the standalone ServiceRecordSection**

Locate (around line 534):

```dart
// U6 fix (Test #4 hotfix): ServiceRecordSection (RANK card)
const ServiceRecordSection(),
```

Delete those lines (the comment block + the widget). The Service Record content now lives inside `WardRankPill`'s expansion.

Also remove the unused import at the top:

```dart
import '../widgets/service_record_section.dart';
```

(do NOT delete `service_record_section.dart` itself in this task — leave it as dead-but-harmless code. A cleanup task at the end of the batch can delete it. This keeps the D-7 diff focused.)

- [ ] **Step 4: Verify**

```bash
flutter analyze lib/features/profile/screens/profile_screen.dart lib/features/profile/widgets/profile_identity.dart
```

Expect: 0 errors. If `ProfileIdentity.onTapEdit` is non-nullable, fix the parameter signature in the same commit and re-analyze.

- [ ] **Step 5: Commit (combined with D-6 helper)**

```bash
git add lib/features/profile/screens/profile_screen.dart lib/features/profile/widgets/profile_identity.dart
git commit -m "$(cat <<'EOF'
feat(profile): WardRankPill at top + Service Record helper (Test #6 D-6 + D-7)

- ProfileIdentity no longer renders top EDIT PROFILE button
  (moves to SETTINGS first row in D-9).
- New WardRankPill below ProfileIdentity. Tap toggles inline
  accordion expansion that renders Service Record content via
  _buildRankServiceRecord(): current rank (48dp insignia +
  display name + CURRENT badge), next 2 rungs (24dp dimmed
  insignia + shortName + gate copy), "View full roadmap →"
  button routing to /train/roadmap.
- Removed standalone ServiceRecordSection (now lives inside
  the pill's expansion).

Spec: §7.2 + §7.3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task D-8 — Remove status strip from Profile

**Files:** `lib/features/profile/screens/profile_screen.dart`.

If a status strip (streak + freeze chips, possibly via `WardStatusStrip` from Test #5 Plan D) currently renders inside Profile, remove it. Keep the same primitives in use on Home / Train / Nutrition / Coach untouched.

- [ ] **Step 1: Locate any status-strip render in Profile**

```bash
grep -n "WardStatusStrip\|StreakBadge\|FreezeBadge\|streakProvider\|streak_chip" lib/features/profile/screens/profile_screen.dart lib/features/profile/widgets/profile_identity.dart
```

If matches exist:
- Inside `profile_identity.dart` — wrap the offending call site in `// removed for Plan D` and delete.
- Inside `profile_screen.dart` — same.

If zero matches surface (because Test #5 Plan D was never merged into this branch), this task is a verification no-op — just record the empty grep result.

- [ ] **Step 2: Verify**

```bash
flutter analyze lib/features/profile/
grep -rn "StreakBadge\|FreezeBadge\|WardStatusStrip" lib/features/profile/
```

Expect: 0 errors and 0 grep matches inside `lib/features/profile/`.

- [ ] **Step 3: Commit (skip if no changes)**

If Step 1 found nothing, skip — go straight to D-9. Otherwise:

```bash
git add lib/features/profile/
git commit -m "$(cat <<'EOF'
feat(profile): remove streak/freeze chips from Profile (Test #6 D-8)

Status strip stays on Home/Train/Nutrition/Coach. Profile is
special — rank takes its place at the top via WardRankPill.

Spec: §7.4 (Removed list).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task D-9 — Add Edit Profile to SETTINGS as first row

**Files:** `lib/features/profile/screens/profile_screen.dart`.

- [ ] **Step 1: Locate the SETTINGS section**

```bash
grep -n "SectionHeader('SETTINGS')" lib/features/profile/screens/profile_screen.dart
```

Expect: line ~730. The next `_buildCard([...])` block lists the rows.

- [ ] **Step 2: Insert Edit Profile as the first row**

Open the file at the SETTINGS `_buildCard([...])` and prepend a new `ProfileRow`:

```dart
const SectionHeader('SETTINGS'),
_buildCard([
  // Plan D: Edit Profile moved here from top of Profile.
  ProfileRow(
    icon: Icons.person_outline,
    title: 'Edit Profile',
    subtitle: 'Goal, stats, preferences',
    trailing: const ProfileRowChevron(),
    onTap: () => context.go('/profile/edit'),
  ),
  ProfileRow(
    icon: Icons.notifications_outlined,
    title: 'Notifications',
    // ... unchanged ...
  ),
  // ... rest unchanged ...
]),
```

- [ ] **Step 3: Verify**

```bash
flutter analyze lib/features/profile/screens/profile_screen.dart
```

Expect: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/profile/screens/profile_screen.dart
git commit -m "$(cat <<'EOF'
feat(profile): Edit Profile as first row in SETTINGS (Test #6 D-9)

Moved from top-of-Profile (replaced by WardRankPill in D-7).
Routes to /profile/edit (unchanged).

Spec: §7.4 + obs #17.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task D-10 — Move Predictions to REPORTS as a list row

**Files:** `lib/features/profile/screens/profile_screen.dart`.

Drop the standalone `YOUR PREDICTION` section header + card. Inside REPORTS (above the existing Weekly Report card OR below Progress Photos — see Step 2 for ordering decision), add a new ListTile-style row that:
- shows the first 50 chars of the current prediction text + `…`,
- on tap, opens the existing prediction bottom sheet UI (re-uses the same UI that the old YOUR PREDICTION card opened — find the existing handler).

- [ ] **Step 1: Locate the existing YOUR PREDICTION section**

```bash
grep -n "YOUR PREDICTION\|_buildPredictionCard\|prediction_text" lib/features/profile/screens/profile_screen.dart
```

Expect:
- `~578` `const SectionHeader('YOUR PREDICTION')`
- `~582` `_buildPredictionCard()`
- `~1214` `Widget _buildPredictionCard()`

The current `_buildPredictionCard()` likely renders an inline card with full prediction text (with a "Read More" affordance). Extract its existing bottom-sheet open behaviour OR build a fresh sheet.

- [ ] **Step 2: Add a `_truncatedPredictionPreview` helper**

Just above `_buildPredictionCard`:

```dart
String _truncatedPredictionPreview(String? prediction, {int maxChars = 50}) {
  final p = (prediction ?? '').trim();
  if (p.isEmpty) return 'Tap to generate your forecast';
  if (p.length <= maxChars) return p;
  return '${p.substring(0, maxChars).trimRight()}…';
}
```

- [ ] **Step 3: Add `_showPredictionBottomSheet`**

```dart
void _showPredictionBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        // Re-use the existing inline card body — it already handles
        // empty / loading / error / loaded states.
        child: _buildPredictionCard(),
      ),
    ),
  );
}
```

(If `_buildPredictionCard` is too large for the sheet because it includes its own header / chrome, refactor it: split out a `_predictionBody()` returning just the prose, and use that inside both the row preview AND the sheet.)

- [ ] **Step 4: Replace YOUR PREDICTION section with REPORTS row**

Delete the block (around line 577-584):

```dart
// Bug #14 — Future Prediction (moved from home dashboard).
const SectionHeader('YOUR PREDICTION'),
Padding(
  padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.screenPadding),
  child: _buildPredictionCard(),
),
const SizedBox(height: 8),
```

Then inside the REPORTS section (which currently starts with `WeeklyReportCard`), insert a new card BEFORE the WeeklyReportCard:

```dart
const SectionHeader('REPORTS'),
// Plan D: Predictions row (moved from standalone YOUR PREDICTION section).
Builder(builder: (ctx) {
  final prediction = ref.watch(predictionProvider);
  return _buildCard([
    ProfileRow(
      icon: Icons.auto_awesome_outlined,
      iconColor: AppColors.accent,
      title: 'Predictions',
      subtitle: _truncatedPredictionPreview(prediction),
      trailing: const ProfileRowChevron(),
      showBorder: false,
      onTap: () => _showPredictionBottomSheet(ctx),
    ),
  ]);
}),
const SizedBox(height: 6),
WeeklyReportCard(
  // ... existing args, unchanged ...
),
// ... rest unchanged ...
```

> **Pin order:** Predictions → Weekly Report → Progress Photos. C15 specifies Predictions is **first** in REPORTS.

- [ ] **Step 5: Verify**

```bash
flutter analyze lib/features/profile/screens/profile_screen.dart
grep -n "YOUR PREDICTION" lib/features/profile/screens/profile_screen.dart
```

Expect: 0 analyze errors. 0 `YOUR PREDICTION` matches.

- [ ] **Step 6: Commit**

```bash
git add lib/features/profile/screens/profile_screen.dart
git commit -m "$(cat <<'EOF'
feat(profile): Predictions row in REPORTS (Test #6 D-10)

Removed standalone YOUR PREDICTION section header + inline card.
Inside REPORTS, a new ProfileRow shows first 50 chars of the
prediction + '…'. Tap opens a draggable bottom sheet hosting the
full prediction body (re-uses _buildPredictionCard).

Order inside REPORTS: Predictions → Weekly Report → Progress Photos.

Spec: §7.5 + obs #18.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task D-11 — Layout test for Profile screen

**Files:** Create `test/profile/profile_screen_layout_test.dart`.

The Profile screen has many providers + Hive boxes — full pump-widget tests are heavy. Use `WidgetTester` with provider overrides + `find.byType` on section headers to verify ORDER without simulating all data. The key invariants:

- C13: `WardRankPill` is present near top; no `StreakBadge` / `FreezeBadge` / `WardStatusStrip` widgets anywhere.
- C14: A `ProfileRow` with title `'Edit Profile'` is the first row inside the SETTINGS card.
- C15: A `ProfileRow` with title `'Predictions'` is the first row inside the REPORTS section.
- A `ProfileRow` titled `'Edit Profile'` does NOT appear inside `ProfileIdentity` (i.e. no top-of-page edit button).

- [ ] **Step 1: Create the test**

```dart
// test/profile/profile_screen_layout_test.dart
//
// Layout invariants for ProfileScreen after Plan D restructure.
//
// We pump the full ProfileScreen with minimal provider overrides
// to keep the tree bootable. Then we walk the rendered widget tree
// and assert section ordering + presence/absence rules.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/screens/profile_screen.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_pill.dart';

void main() {
  testWidgets('Profile layout — C13/C14/C15 invariants', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // C13a: WardRankPill is present.
    expect(find.byType(WardRankPill), findsOneWidget,
        reason: 'C13 — rank pill at top of Profile');

    // C13b: No streak/freeze chips on Profile.
    // (Class names — keep this list in sync with the primitives if renamed.)
    final forbiddenWidgetNames = ['StreakBadge', 'FreezeBadge', 'WardStatusStrip'];
    for (final name in forbiddenWidgetNames) {
      final matches = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == name,
      );
      expect(matches, findsNothing,
          reason: 'C13 — $name must not render on Profile');
    }

    // C14: SETTINGS first row is "Edit Profile".
    // The first ProfileRow whose title is "Edit Profile" must come AFTER
    // the SETTINGS section header in widget tree order.
    final settingsHeader = find.text('SETTINGS');
    expect(settingsHeader, findsOneWidget);
    final editProfile = find.text('Edit Profile');
    expect(editProfile, findsWidgets);

    // The Edit Profile row's RenderObject paint position must be below
    // the SETTINGS header. We compute Y coords to assert the order.
    final settingsY = tester.getTopLeft(settingsHeader).dy;
    final editProfileYs = editProfile.evaluate()
        .map((e) => tester.getTopLeft(find.byWidget(e.widget)).dy)
        .toList();
    expect(editProfileYs.any((y) => y > settingsY), isTrue,
        reason: 'C14 — Edit Profile must appear under SETTINGS header');

    // C14b: NO Edit Profile row above the SETTINGS header (i.e. not at top).
    expect(editProfileYs.every((y) => y > settingsY), isTrue,
        reason: 'C14 — Edit Profile must NOT appear above SETTINGS');

    // C15: Predictions is the first row inside REPORTS.
    final reportsHeader = find.text('REPORTS');
    expect(reportsHeader, findsOneWidget);
    final predictions = find.text('Predictions');
    expect(predictions, findsOneWidget,
        reason: 'C15 — Predictions row must exist');
    final reportsY = tester.getTopLeft(reportsHeader).dy;
    final predictionsY = tester.getTopLeft(predictions).dy;
    expect(predictionsY > reportsY, isTrue,
        reason: 'C15 — Predictions must appear under REPORTS');

    // C15b: No standalone YOUR PREDICTION section header anywhere.
    expect(find.text('YOUR PREDICTION'), findsNothing,
        reason: 'C15 — YOUR PREDICTION header removed');
  });
}
```

> **Bootability caveat:** if `ProfileScreen` reads providers that throw without overrides (e.g. Hive box access), the test will need provider overrides for `userProfileProvider`, `predictionProvider`, etc. Add them inside the `ProviderScope(overrides: [...])` block as the test surfaces failures. The minimal-viable list:
> - `predictionProvider.overrideWith((ref) => 'Sample prediction text for the test')`
> - `userProfileProvider.overrideWith(...)` returning `{'full_name': 'Test User', 'current_rank_code': 'LS', ...}`
> - `subscriptionInfoProvider.overrideWith(...)` returning a free-tier `SubscriptionInfo`
>
> Iterate: run the test, copy the failing provider name into the overrides list, repeat until pumps clean.

- [ ] **Step 2: Run the test**

```bash
flutter test test/profile/profile_screen_layout_test.dart
```

Expect: passes after override iteration.

- [ ] **Step 3: Commit**

```bash
git add test/profile/profile_screen_layout_test.dart
git commit -m "$(cat <<'EOF'
test(profile): layout invariants C13/C14/C15 (Test #6 D-11)

Asserts:
- WardRankPill renders at top of Profile.
- No StreakBadge / FreezeBadge / WardStatusStrip on Profile.
- Edit Profile row appears under SETTINGS header (not above).
- Predictions row appears under REPORTS header.
- No YOUR PREDICTION section header anywhere.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task D-12 — Full analyze + test + visual smoke doc

**Files:** Create `docs/superpowers/notes/2026-05-01-profile-restructure-smoke.md`.

- [ ] **Step 1: Analyze the whole tree**

```bash
flutter analyze lib/
```

Expect: `No issues found!` Fix anything that surfaces in-place.

- [ ] **Step 2: Run the targeted test suites**

```bash
flutter test test/wardroom/ test/profile/
```

Expect: all green. Insignia goldens (22) + 1 fallback + 3 pill smoke + 1 layout.

- [ ] **Step 3: Source-grep regression — no Service Record top-level + no top Edit Profile**

```bash
grep -rn "ServiceRecordSection\(\)" lib/features/profile/screens/
grep -n "YOUR PREDICTION" lib/features/profile/
```

Expect: 0 matches each.

- [ ] **Step 4: Walk through the dev APK and verify on device**

```bash
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart
```

(Or `/build-apk` skill for a release artefact.)

Tab to Profile and verify:

| # | Item | Verify |
|---|---|---|
| C13a | Rank pill at top with insignia | Insignia matches user's current rank (e.g. SD2 text-only, LS anchor, etc.) |
| C13b | Tap pill expands accordion | 200ms ease-out, Service Record content slides in below |
| C13c | Service Record content | Current rank header (48dp insignia + display name + CURRENT badge), next 2 rungs dimmed, "View full roadmap →" button tappable |
| C13d | NO streak/freeze chips on Profile | Confirm absence visually |
| C14 | SETTINGS first row is Edit Profile | Tap routes to /profile/edit |
| C15a | REPORTS first row is Predictions | Subtitle shows prediction preview (50 chars + `…`) |
| C15b | Tap Predictions opens bottom sheet | Sheet contains full prediction body |

- [ ] **Step 5: Document findings**

Create the smoke doc:

```markdown
# Profile restructure visual smoke — Test #6 Plan D

**Date:** <YYYY-MM-DD>
**APK:** dev / prod (circle one)
**Device:** <device + Android version>

## Result per criterion

- [ ] C13a — rank pill at top with correct insignia
- [ ] C13b — tap expands accordion (200ms feel)
- [ ] C13c — Service Record content correct (current 48dp / next 2 dimmed / roadmap button)
- [ ] C13d — NO streak/freeze chips on Profile
- [ ] C14 — Edit Profile is first row in SETTINGS
- [ ] C15a — Predictions is first row in REPORTS, preview text correct
- [ ] C15b — Predictions tap opens bottom sheet, full body renders

## Issues found

(none / list)

## Spec deviations

(none / list)
```

- [ ] **Step 6: Commit the doc**

```bash
git add docs/superpowers/notes/2026-05-01-profile-restructure-smoke.md
git commit -m "$(cat <<'EOF'
docs(profile): visual smoke verification log (Test #6 D-12)

C13/C14/C15 verification against spec §7.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review — spec coverage

| Spec ref | Requirement | Task |
|---|---|---|
| §7.1 | Rank prominent at top, replacing Edit Profile | D-7 |
| §7.1 | Edit Profile moves to SETTINGS first row | D-9 |
| §7.1 | Predictions to REPORTS as list row + bottom sheet | D-10 |
| §7.1 | Streak/freeze chips removed from Profile | D-8 |
| §7.1 | Indian Navy insignia via CustomPaint for all 11 ranks (incl. Lt) | D-1 |
| §7.2 | WardRankPill (insignia + shortCapsName + chevron, accordion expand) | D-4 |
| §7.2 | Animation 200ms ease-out vertical | D-4 (AnimationController + SizeTransition + easeOut) |
| §7.2 | Service Record dropdown content via builder slot | D-4 (`expandedContentBuilder`) + D-6 (Profile owns content) |
| §7.3 | WardRankInsignia 11-rank dispatch | D-1 |
| §7.3 | 24dp pill / 48dp popup sizes | D-3 (golden pairs) |
| §7.3 | AppColors.accent default + override | D-1 (`color` param) |
| §7.4 | Profile ListView body re-order | D-7 + D-8 + D-9 + D-10 |
| §7.4 | Banner eyebrow `DOSSIER · OFFICER` 65% alpha | (Out of scope — exists from Test #5 Plan D, untouched) |
| §7.5 | Predictions row preview + bottom sheet | D-10 |
| §7.6 | Tests for insignia + pill + layout | D-3 + D-5 + D-11 |
| §12 C13 | Rank pill at top + Indian Navy insignia + accordion + no streak/freeze | D-7 + D-8 (verified D-12) |
| §12 C14 | SETTINGS first row is Edit Profile | D-9 (verified D-12) |
| §12 C15 | REPORTS first row is Predictions with preview + sheet | D-10 (verified D-12) |
| §10 | Lt rank insignia (2 thick stripes) — painter ready for Plan F wiring | D-1 (`'Lt' → _StripePainter(thickStripes: 2, ...)`) |

## Self-review — placeholder scan

Search the plan for telltales of placeholder copy:

```bash
grep -nE "TODO|FIXME|<placeholder>|XXX|TBD" docs/superpowers/plans/2026-05-01-apk-test-6-plan-D-profile-restructure.md
```

Expect: 0 matches. (The `<YYYY-MM-DD>` etc. inside the smoke template doc are intended user fill-in, not placeholders in plan text.)

## Self-review — type consistency

- `WardRankInsignia({rankCode, size, color})` — verbatim across D-1, D-3, D-6, D-7. ✓
- `WardRankPill({rankCode, shortCapsName, expandedContentBuilder})` — verbatim across D-4, D-5, D-7, D-11. ✓
- `expandedContentBuilder` is `Widget Function(BuildContext)` — matches both the spec §7.2 example and the call sites. ✓
- `AppColors.accent` referenced everywhere a colour is mentioned. ✓
- `RankService.instance.getCurrentRank().entry.{code, shortName, displayName, isTerminal, ordinal}` — fields verified to exist in `lib/core/services/rank_ladder_data.dart`. ✓
- `LadderEntryView.{entry, gateText}` — verified in `rank_service.dart`. ✓

## Done definition

- All 12 tasks above have all checkboxes ticked.
- `flutter analyze lib/` reports 0 issues.
- `flutter test test/wardroom/ test/profile/` passes (22 insignia goldens + 1 fallback + 3 pill smoke + 1 layout = 27 tests minimum).
- All 3 success criteria (C13 / C14 / C15) verified manually in D-12 walkthrough.
- Commit history: 11 feature commits in linear order on `feat/apk-test-6-batch` (D-2 + D-5 + D-8 may be skipped if no-op; D-6 + D-7 share a single commit; D-12 may be doc-only).
