// test/contracts/equipment_tier_consistency_test.dart
//
// Batch 13-A (D-4): gains-only equipment_tier deepening. The library had bodyweight
// moves tagged e.g. ["bodyweight","full_gym"] (skipping the middle tiers they trivially
// satisfy), so Glute Bridge / Reverse Fly / RDL etc. were hidden from home/basic-gym
// users (the shallow-pool → universalPool fallback class, recurrence of 40a426).
//
// Invariant (OI-89, 2026-08-28): `derive(equipment_needed) == equipment_tier`. EQUALITY.
//
// This was a SUBSET assertion — under-tags banned, over-tags "intentionally tolerated
// this batch, a separate drop-side pass corrects them". That pass is OI-89, and it is
// this one. Over-tagging was never a tolerable imprecision: `equipment_tier` was the
// ONLY thing queryV4 filtered on, so a row tagged `bodyweight` while needing a barbell
// was SERVED to bodyweight users. Chin Up was exactly that row, in the shipped APK.
// Tolerating the over-tag side is what made the bug possible, so both sides are hard
// failures now.
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

  group('equipment_tier consistency (OI-89: equality, both sides)', () {
    test('derive(equipment_needed) == equipment_tier for every row', () {
      final offenders = <String>[];
      for (final r in rows) {
        final derived = _derive(r['equipment_needed']).toSet();
        final tier = ((r['equipment_tier'] as List?) ?? const [])
            .map((e) => e.toString().toLowerCase())
            .toSet();
        final under = derived.difference(tier);
        final over = tier.difference(derived);
        if (under.isNotEmpty) {
          offenders.add('${r['id']} ${r['name']}: doable at $under, not listed');
        }
        if (over.isNotEmpty) {
          offenders.add('${r['id']} ${r['name']}: listed at $over '
              'but needs ${r['equipment_needed']}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'equipment_tier must EQUAL derive(equipment_needed). UNDER = '
              'hidden from a tier it can do. OVER = served to a tier it CANNOT '
              'do, which is the whole of OI-89.\n${offenders.join('\n')}');
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

    test('every movement pattern keeps a floor a bodyweight user can actually fill',
        () {
      // The restore + audit REMOVED rows from the bodyweight tier (16 of them,
      // Chin Up included). A correction that empties a pattern has traded one bug
      // for another: the cascade would fall through to universalPoolV4 and hand
      // back the very rows the floor just rejected.
      //
      // Two thresholds, because they answer different questions:
      //   baseline — performable with the bodyweight tier's items
      //   core     — performable with the UN-EXCLUDABLE floor alone, so a user who
      //              ticks every Customize box still fills the slot
      const strength = [
        'horizontal_push', 'vertical_push', 'horizontal_pull', 'vertical_pull',
        'knee_dominant', 'hip_dominant', 'core', 'elbow_flexion',
        'elbow_extension', 'shoulder_isolation', 'hip_isolation',
      ];
      final baselineItems = EquipmentVocab.tierItems['bodyweight']!.toSet();
      const coreItems = {'none', 'bodyweight', 'wall'};

      final short = <String>[];
      for (final p in strength) {
        var base = 0, core = 0;
        for (final r in rows) {
          if (r['is_active'] == false) continue;
          final pats = (r['movement_pattern'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [];
          if (!pats.contains(p)) continue;
          final need = EquipmentVocab.fromProfile(r['equipment_needed']).toSet();
          if (need.every(baselineItems.contains)) base++;
          if (need.every(coreItems.contains)) core++;
        }
        if (base < 3) short.add('$p: only $base baseline row(s), need 3');
        if (core < 1) short.add('$p: NO row performable with the un-excludable floor');
      }
      expect(short, isEmpty, reason: short.join('\n'));
    });
  });
}
