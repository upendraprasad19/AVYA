// test/contracts/equipment_tier_consistency_test.dart
//
// Batch 13-A (D-4): gains-only equipment_tier deepening. The library had bodyweight
// moves tagged e.g. ["bodyweight","full_gym"] (skipping the middle tiers they trivially
// satisfy), so Glute Bridge / Reverse Fly / RDL etc. were hidden from home/basic-gym
// users (the shallow-pool → universalPool fallback class, recurrence of 40a426).
//
// Invariant (gains-only): every exercise is selectable at AT LEAST every tier it is
// physically doable at — `derive(equipment_needed) ⊆ equipment_tier`. Over-tags (a row
// listed at a tier it CANNOT do) are intentionally tolerated this batch — a separate
// drop-side pass corrects them — so this asserts SUBSET, not equality.
//
// The `derive` here uses the REAL EquipmentVocab.normalize + tierItems (not a hardcoded
// copy), so it can never disagree with the runtime equipment filter (Round-2 P2).
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';

const _tiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];

/// The tiers an exercise is doable at = every tier whose canonical items ⊇ its
/// (normalized) equipment_needed. Empty need = no requirement → every tier (vacuous).
List<String> _derive(Object? equipmentNeeded) {
  final need = EquipmentVocab.fromProfile(equipmentNeeded); // canonical, crash-safe
  return _tiers.where((t) => need.every(EquipmentVocab.tierItems[t]!.contains)).toList();
}

void main() {
  final rows = (jsonDecode(
    File('assets/data/exercise_library.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();

  group('equipment_tier consistency (Batch 13-A D-4, gains-only)', () {
    test('derive(equipment_needed) ⊆ equipment_tier for every row (no under-tag)', () {
      final offenders = <String>[];
      for (final r in rows) {
        final derived = _derive(r['equipment_needed']).toSet();
        final tier = ((r['equipment_tier'] as List?) ?? const [])
            .map((e) => e.toString().toLowerCase())
            .toSet();
        final under = derived.difference(tier);
        if (under.isNotEmpty) {
          offenders.add('${r['id']} ${r['name']}: doable at $under but not listed (has $tier)');
        }
      }
      expect(offenders, isEmpty,
          reason: 'Under-tagged rows (hidden from a tier they are doable at):\n${offenders.join('\n')}');
    });

    test('every equipment_tier is non-empty + only the 4 canonical tiers', () {
      final offenders = <String>[];
      for (final r in rows) {
        final tier = ((r['equipment_tier'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        if (tier.isEmpty) offenders.add('${r['id']}: EMPTY equipment_tier');
        for (final t in tier) {
          if (!_tiers.contains(t)) offenders.add('${r['id']}: bogus tier "$t"');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}
