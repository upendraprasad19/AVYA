// ⑥ Batch 6 (W2.3) — readiness check-in: PURE model + deterministic mode engine.
//
// Lives in `core/utils` (like ⑦b's `detraining.dart`) so it is importable from
// BOTH `core/services` (HealthWriteService.logReadiness) and `features/*`
// (train session adjustment, profile trends) without a layering violation, and
// is unit-testable in isolation (no Hive / Flutter imports).
//
// 6-A ships: the 3×3 check-in → a Green/Yellow/Red level → a Red-day isolation
// SET-DROP (the 0-set floor is automatic — `removeLastSet` never goes below 1).
// The LOAD cut (−% on compound prescriptions) is 6-B — it must be applied at
// `exercise_card.dart` (the prefill), NOT here, because `ExerciseData.weight`
// is dead `'0kg'` on the materialized day (ignored for users with history).

/// The three deterministic session modes derived from the 3×3 check-in.
enum ReadinessLevel { green, yellow, red }

/// One day's readiness check-in. Each axis is 0 (best) / 1 (mid) / 2 (worst):
/// Sleep    → Solid(0)  / Okay(1)     / Rough(2)
/// Soreness → Fresh(0)  / A little(1) / Beat up(2)
/// Energy   → Charged(0)/ Normal(1)   / Running low(2)
class ReadinessCheckin {
  final int sleep;
  final int soreness;
  final int energy;

  /// IST date key (`istDateStr`) — one check-in per calendar day.
  final String date;

  const ReadinessCheckin({
    required this.sleep,
    required this.soreness,
    required this.energy,
    required this.date,
  });

  ReadinessLevel get level =>
      readinessLevelFor(sleep: sleep, soreness: soreness, energy: energy);

  /// The Hive/cloud row shape. `level` is denormalized for cheap trend reads.
  Map<String, dynamic> toMap() => {
        'date': date,
        'sleep': sleep,
        'soreness': soreness,
        'energy': energy,
        'level': level.name,
      };

  /// Crash-safe reconstruct (coerces num→int, clamps [0,2], missing → mid/1).
  static ReadinessCheckin fromMap(Map<dynamic, dynamic> map) => ReadinessCheckin(
        sleep: _axis(map['sleep']),
        soreness: _axis(map['soreness']),
        energy: _axis(map['energy']),
        date: (map['date'] ?? '').toString(),
      );

  static int _axis(dynamic v) {
    final n = (v is num) ? v.toInt() : int.tryParse('$v') ?? 1;
    return n < 0 ? 0 : (n > 2 ? 2 : n); // clamp to [0,2]
  }
}

/// Deterministic Green/Yellow/Red from the flag count. An axis at the worst
/// level (`>= 2`) is a "flag": 0 flags → green, 1-2 → yellow, 3 → red.
/// Pure + total — every (sleep,soreness,energy) maps to exactly one level.
ReadinessLevel readinessLevelFor({
  required int sleep,
  required int soreness,
  required int energy,
}) {
  var flags = 0;
  if (sleep >= 2) flags++;
  if (soreness >= 2) flags++;
  if (energy >= 2) flags++;
  if (flags >= 3) return ReadinessLevel.red;
  if (flags >= 1) return ReadinessLevel.yellow;
  return ReadinessLevel.green;
}

/// Maps MEASURED sleep hours onto the readiness sleep axis (0 best → 2 worst),
/// so a Health-Connect reading feeds the same flag count as a tapped answer.
///
/// Founder-locked 2026-09-01. Both boundary values belong to the MIDDLE band:
///   > 6.5      → 0 (Solid)
///   4.5 … 6.5  → 1 (Okay)   ← 6.5 and 4.5 BOTH land here
///   < 4.5      → 2 (Rough)
///
/// Because this returns the same 0/1/2 a tap does, [readinessLevelFor] needs
/// no change at all — measured sleep is just a better-sourced axis value.
int sleepAxisFromHours(double hours) {
  if (hours > 6.5) return 0;
  if (hours >= 4.5) return 1;
  return 2;
}

/// The readiness sheet's SLEEP-row state, resolved from whatever measurement
/// we hold for today.
///
/// `null`  -> STATE B: no measurement, the sheet must ASK (3 tap rows).
/// `0/1/2` -> STATE A: show the measured value + band, no tap needed.
///
/// Extracted from the widget deliberately: a private `initState` branch cannot
/// be mutation-tested, and this is the one decision that changes what the user
/// sees. The widget must call THIS, not re-derive the branch inline.
int? resolveSleepAxis(double? measuredHours) =>
    measuredHours == null ? null : sleepAxisFromHours(measuredHours);
