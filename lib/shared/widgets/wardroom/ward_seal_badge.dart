import 'package:flutter/material.dart';

import 'ward_glyphs.dart';

/// Wrapper over [SealGlyph] with preset sizes for the three Wardroom
/// seal placements:
///
/// * [WardSealVariant.report] — Weekly Report header (42 px, e.g.
///   `REPORT / W14`).
/// * [WardSealVariant.subscription] — Profile subscription card corner
///   (54 px, e.g. `PRO / ANNUAL`).
/// * [WardSealVariant.founder] — Profile footer founder mark (40 px).
/// * [WardSealVariant.phase] — Train phase-unlock callout (54 px, e.g.
///   `PHASE 2 / UNLOCK`).
enum WardSealVariant { report, subscription, founder, phase }

class WardSealBadge extends StatelessWidget {
  const WardSealBadge({
    super.key,
    required this.label,
    required this.subline,
    this.variant = WardSealVariant.report,
    this.color,
  });

  final String label;
  final String subline;
  final WardSealVariant variant;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final size = switch (variant) {
      WardSealVariant.report => 42.0,
      WardSealVariant.subscription => 54.0,
      WardSealVariant.phase => 54.0,
      WardSealVariant.founder => 40.0,
    };
    return SealGlyph(
      label: label,
      date: subline,
      size: size,
      color: color,
    );
  }
}
