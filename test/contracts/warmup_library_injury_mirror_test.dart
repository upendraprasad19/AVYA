// Batch 13-B — warmup/library injury-tag VALUE-AGREEMENT drift guard.
//
// `WarmupCooldownSelector._moveInjuries` is a SEPARATE hard-coded copy of injury
// tags (the warmup/cooldown/cardio moves aren't library rows, so there's no field
// to read). But three of its keys — Push Up, Band Pull Apart, Baithak — DO exist as
// selectable library exercises, and their tags MUST equal the library's
// `injury_contraindications` for the same move, or a shoulder-injured user (say)
// could be filtered out of the main-plan Push Up while still handed it in the warmup.
//
// The existing drift guard (`allFixedMoves ⊆ mappedMoves`) checks PRESENCE only — it
// can't catch a VALUE mismatch. This test closes that gap: if a future batch retags
// one of the 3 overlap moves in the library but forgets the `_moveInjuries` mirror
// (or vice-versa), this fails.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/warmup_cooldown.dart';

void main() {
  test('main-cascade overlap moves: _moveInjuries == library injury_contraindications',
      () {
    final lib = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    final libByName = <String, Set<String>>{};
    for (final e in lib) {
      final m = Map<String, dynamic>.from(e as Map);
      final ic = m['injury_contraindications'];
      libByName[(m['name'] as String).toLowerCase()] = ic is List
          ? ic.map((t) => t.toString().toLowerCase()).toSet()
          : <String>{};
    }

    for (final move in WarmupCooldownSelector.mainCascadeOverlapMoves) {
      final mirror = (WarmupCooldownSelector.moveInjuries[move] ?? const {})
          .map((t) => t.toLowerCase())
          .toSet();
      expect(libByName.containsKey(move.toLowerCase()), isTrue,
          reason: 'overlap move "$move" must exist as a library exercise');
      expect(mirror, libByName[move.toLowerCase()],
          reason: 'warmup _moveInjuries["$move"] drifted from the library '
              'injury_contraindications — the warmup would filter differently from '
              'the main plan. Sync both in the same commit.');
    }
  });
}
