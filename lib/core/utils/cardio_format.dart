/// One formatter pair for cardio and distance values (OI-389 U7), so the
/// expanded row, the week strip, the chips, the receipt, the preview and the
/// PR value print the same text. Pure, no Flutter.
///
/// `space` is the character between a number and its unit: the chips and the
/// preview pass a plain space, the Train expanded row passes NBSP. Timed
/// formatting never comes through here (`60 secs`, the timed `Xm Ys` row).
library;

/// A cardio or distance duration in decimal minutes, matching how cardio is
/// typed (D2): under 60 s `45s`; otherwise one decimal with a trailing `.0`
/// dropped: 1800 → `30 min`, 750 → `12.5 min`, 1830 → `30.5 min`,
/// 735 → `12.3 min` (display rounds; the stored 735 s does not),
/// 3597 → `60 min`. One token before the unit, so the PR tile's split on a
/// space renders `12.5` + `min`.
String formatSetDuration(int secs, {String space = ' '}) {
  if (secs < 60) return '${secs}s';
  var t = (secs / 60).toStringAsFixed(1);
  if (t.endsWith('.0')) t = t.substring(0, t.length - 2);
  return '$t${space}min';
}

/// A distance: metres under 1 km (`40 m`), else one decimal (`5.0 km`). The
/// boundary is on the ROUNDED metres, so 0.9996 km reads `1.0 km`, never
/// `1000 m`.
String formatDistance(double km, {String space = ' '}) {
  final m = (km * 1000).round();
  if (m < 1000) return '$m${space}m';
  return '${km.toStringAsFixed(1)}${space}km';
}

/// The detail line for a cardio or distance row or set (OI-389 U7). Parts in
/// order: duration, km, reps, weight; a zero part is omitted.
///
/// The set count, per type:
/// - `distance` always leads with it (`1 set · 40 m · 40.0 kg`), and with
///   every other part zero reads `1 set`;
/// - `cardio` has none (`20 min · 5.0 km`), except a set kept by the writer's
///   reps rule (no duration, no km, reps shown), which leads with it so its
///   sets stay visible (`3 sets · 20 reps · 100.0 kg`).
/// With nothing to show it reads `—`. [sets] <= 0 never prints a count.
String cardioDistanceDetail({
  required String loggingType,
  required int sets,
  required int durationSec,
  required double km,
  required int reps,
  required double weightKg,
  String space = ' ',
  String separator = ' · ',
}) {
  final parts = <String>[
    if (durationSec > 0) formatSetDuration(durationSec, space: space),
    // B-pass F5: a km that rounds to 0 m is omitted, never "0 m".
    if ((km * 1000).round() > 0) formatDistance(km, space: space),
    if (reps > 0) '$reps$space${reps == 1 ? 'rep' : 'reps'}',
    if (weightKg > 0) '${weightKg.toStringAsFixed(1)}${space}kg',
  ];
  final leadWithCount = sets > 0 &&
      (loggingType == 'distance' ||
          (durationSec <= 0 && (km * 1000).round() <= 0 && reps > 0));
  if (leadWithCount) {
    parts.insert(0, '$sets$space${sets == 1 ? 'set' : 'sets'}');
  }
  return parts.isEmpty ? '—' : parts.join(separator);
}
