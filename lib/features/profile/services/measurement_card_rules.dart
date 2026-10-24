import '../../../core/constants/body_measurement_sites.dart';
import '../../../core/constants/body_measurement_specs.dart';
import '../../../core/copy/measurement_copy.dart';
import '../../../core/services/health_read_service.dart';
import '../../../core/utils/measurement_units.dart';

/// One tile of the Progress comparison card (L2b Landing C): a site, its latest
/// value, and how it differs from the first value ever held for that site.
///
/// [value] and [delta] are in the DISPLAYED unit ([inches]); the strings are
/// built from them by `MeasurementCopy` so the visual text and the screen-reader
/// sentence cannot disagree. [firstDate] and [delta] are both null when the site
/// has been held on one day only.
class MeasurementCardRow {
  const MeasurementCardRow({
    required this.site,
    required this.label,
    required this.latestDate,
    required this.firstDate,
    required this.value,
    required this.delta,
    required this.inches,
    required this.titleText,
    required this.valueText,
    required this.deltaText,
    required this.semanticsLabel,
  });

  final String site;
  final String label;
  final String latestDate;
  final String? firstDate;
  final double value;
  final double? delta;
  final bool inches;
  final String titleText;
  final String valueText;
  final String? deltaText;
  final String semanticsLabel;
}

/// PURE: the card's tiles, one per site that has a value, in registry order.
///
/// [entries] MUST be newest first (the order `measurementHistory()` returns).
/// The change is `display(latest) - display(first)` rounded to 0.1, NOT the
/// difference of the centimetre values converted afterwards: the displayed
/// number is what an inch user typed, so the delta of displays is the delta of
/// the numbers the person can see (79.6 -> 80.9 cm shows 31.3 -> 31.9 in, +0.6;
/// converting the 1.3 cm difference would say +0.5). [todayIst] decides when a
/// date carries its year (only when it is not the current IST year); it is
/// passed in, never read from the device clock here.
List<MeasurementCardRow> measurementCardRows({
  required List<MeasurementEntry> entries,
  required bool inches,
  required String todayIst,
}) {
  final latest = HealthReadService.latestBySiteOf(entries);
  final first = HealthReadService.firstBySiteOf(entries);
  final rows = <MeasurementCardRow>[];
  for (final site in kBodyMeasurementSites) {
    final now = latest[site];
    if (now == null) continue;
    final label = kBodyMeasurementSpecs[site]!.label;
    final value = inches ? inchesFromCm(now.cm) : now.cm;
    final since = first[site];
    String? firstDate;
    double? delta;
    if (since != null && since.date != now.date) {
      final base = inches ? inchesFromCm(since.cm) : since.cm;
      firstDate = since.date;
      delta = roundMeasurementToTenth(value - base);
    }
    final shortLatest = formatShortIstDate(now.date, todayIst: todayIst);
    final shortFirst = firstDate == null
        ? null
        : formatShortIstDate(firstDate, todayIst: todayIst);
    rows.add(MeasurementCardRow(
      site: site,
      label: label,
      latestDate: now.date,
      firstDate: firstDate,
      value: value,
      delta: delta,
      inches: inches,
      titleText: MeasurementCopy.cardTileTitle(label, shortLatest),
      valueText: MeasurementCopy.cardValue(value, inches: inches),
      deltaText: delta == null || shortFirst == null
          ? null
          : MeasurementCopy.cardDeltaLine(
              delta,
              inches: inches,
              shortFirstDate: shortFirst,
            ),
      semanticsLabel: MeasurementCopy.cardTileSemantics(
        label: label,
        value: value,
        inches: inches,
        longLatestDate: formatLongIstDate(now.date, todayIst: todayIst),
        delta: delta,
        longFirstDate: firstDate == null
            ? null
            : formatLongIstDate(firstDate, todayIst: todayIst),
      ),
    ));
  }
  return rows;
}
