import 'package:icanbefitter/core/utils/injury_vocab.dart';

import 'cardio_finisher.dart';

/// Unit 3C (OI-396, founder d74 / d78): which stored cardio finisher a screen may SHOW. Pure (no Hive): the inputs
/// come from `FinisherShowContextReader.read()` (`finisher_show_context.dart`), read once per build by every caller.
class FinisherSafety {
  const FinisherSafety._();

  /// The one "injured" predicate (d78: the PROFILE is the only signal). True when the profile's injuries normalise
  /// to at least one canonical token, the engine's own `normalizedInjuries` test, so `['none']`, `'none'`, `[]` and
  /// free text no alias maps are NOT injured.
  static bool isInjured(Object? profileInjuries) =>
      InjuryVocab.normalize(InjuryVocab.fromProfile(profileInjuries)).isNotEmpty;

  /// The finisher maps a screen shows for a stored [raw] finisher. Switch off -> none. No injury -> every map entry
  /// (non-map entries dropped). Injured -> [raw]'s maps only when there is at least one and EVERY item is
  /// [CardioFinisher.injuredGymFinisherName] (by `exercise_name ?? name`, trimmed, case-insensitive), else none: a
  /// plan made before the injury never shows a jumping finisher.
  static List<Map<String, dynamic>> shownFinisherMaps(
    Object? raw, {
    required bool enabled,
    required bool injured,
  }) {
    if (!enabled || raw is! List) return const [];
    final maps = [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    if (!injured) return maps;
    if (maps.isEmpty || maps.length != raw.length) return const [];
    final bike = CardioFinisher.injuredGymFinisherName.toLowerCase();
    final allBike = maps.every((m) {
      final name = m['exercise_name'] ?? m['name'];
      return name is String && name.trim().toLowerCase() == bike;
    });
    return allBike ? maps : const [];
  }

  /// [shownFinisherMaps] of a stored `schedule_*` row (or a plan-blob day map).
  static List<Map<String, dynamic>> shownOfRow(Map<dynamic, dynamic>? row, FinisherShowContext ctx) =>
      shownFinisherMaps(row?['finisher'], enabled: ctx.enabled, injured: ctx.injured);

  /// A finisher row's detail line (round 2 B-F1): `'<sets> rounds · <reps>'`, e.g. `8 rounds · 30s fast / 30s slow`.
  /// The timed renderers would otherwise strip the digits of the reps text ("30s fast / 30s slow" -> 3030 s).
  static String detail(Object? sets, Object? reps) {
    final n = sets is num ? sets.toInt() : int.tryParse('${sets ?? ''}'.trim());
    final text = '${reps ?? ''}'.trim();
    if (n == null || n <= 0) return text;
    final rounds = n == 1 ? '1 round' : '$n rounds';
    return text.isEmpty ? rounds : '$rounds · $text';
  }

  /// The section's minutes label: `'<round(seconds / 60)> MIN'`, like `budgetMinutes` (240 -> `4 MIN`).
  static String minutesLabel(int seconds) => '${(seconds / 60).round()} MIN';
}

/// The two inputs of [FinisherSafety.shownFinisherMaps], read together (`FinisherShowContextReader.read()`).
class FinisherShowContext {
  const FinisherShowContext({required this.enabled, required this.injured});

  /// `disable_cardio_finisher_shown` not set.
  final bool enabled;

  /// [FinisherSafety.isInjured] of the profile.
  final bool injured;
}
