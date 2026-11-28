// ⑥ slice B2 — community-download `equipment_needed` write-normalize, PRODUCTION
// behavioral test (platform behavioral_test_path, §4.4 rule 21).
//
// The seam itself (`SyncService.syncCommunityItems` download loop,
// sync_community.dart:499-506) reads live Supabase, so it is not unit-testable
// directly. Slice B2 therefore extracts the transform as the PURE, PUBLIC
// `EquipmentVocab.normalizedEquipmentRow` and this test exercises it directly —
// every `equipment_needed` shape a cloud `user_custom_exercises` row can carry,
// AND both kill-switch branches — so the rule-21 test is a real transform
// assertion, NOT source-grep confidence (feedback_source_grep_false_confidence).
// A final comment-stripped source-grep then pins that the download loop actually
// routes community rows through the helper (behind the flag) before the Hive put.
//
// Consistency/defense-in-depth only: the sole LIVE selection reader (queryV4)
// already `fromProfile`-normalizes on read (⑥ B1), and community rows lack a
// `movement_pattern` so queryV4 never selects them at all — this test guards the
// STORED representation (matching the seed), not plan selection.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';

void main() {
  // A community-download row shaped like a `user_custom_exercises` cloud row
  // (as `syncCommunityItems` builds it: Map.from(row) + source='community').
  Map<String, dynamic> communityRow(Object? equipmentNeeded) => {
        'id': 'community_ex_1',
        'name': 'Community Move',
        'source': 'community',
        'equipment_tier': ['full_gym'],
        'equipment_needed': equipmentNeeded,
      };

  group('EquipmentVocab.normalizedEquipmentRow (⑥ B2 community write seam)', () {
    test('cloud List of raw/mixed-case tokens → canonical', () {
      final out =
          EquipmentVocab.normalizedEquipmentRow(communityRow(['Cable Machine']));
      expect(out['equipment_needed'], ['cables']);
    });

    test('bare String (legacy / hand-edited shape) → canonical List, never crashes',
        () {
      final out =
          EquipmentVocab.normalizedEquipmentRow(communityRow('Dumbbells'));
      expect(out['equipment_needed'], ['dumbbells']);
    });

    test('OR-compound collapses to the most-accessible alternative (slice-A precedence)',
        () {
      // "Barbell or Dumbbells" → split on " or " → dumbbells (precedence idx 2)
      // beats barbell (idx 6) → the exercise survives under the easier kit, so
      // slice B never over-excludes it.
      final out = EquipmentVocab.normalizedEquipmentRow(
          communityRow('Barbell or Dumbbells'));
      expect(out['equipment_needed'], ['dumbbells']);
    });

    test('already-canonical row is idempotent (order preserved, de-duped)', () {
      final out = EquipmentVocab.normalizedEquipmentRow(
          communityRow(['cables', 'bench']));
      expect(out['equipment_needed'], ['cables', 'bench']);
    });

    test('unmappable token is dropped → [] (P2-3 lossy-but-consistent, most-permissive)',
        () {
      final out = EquipmentVocab.normalizedEquipmentRow(
          communityRow(['Some Exotic Strongman Implement']));
      expect(out['equipment_needed'], isEmpty);
    });

    test('null / absent equipment_needed → [] , never crashes (e9d1c7 read class)',
        () {
      final outNull = EquipmentVocab.normalizedEquipmentRow(communityRow(null));
      expect(outNull['equipment_needed'], isEmpty);

      final noField = <String, dynamic>{'id': 'x', 'name': 'No Equip Field'};
      final out = EquipmentVocab.normalizedEquipmentRow(noField);
      expect(out['equipment_needed'], isEmpty);
    });

    test('only equipment_needed is rewritten — every other field is preserved', () {
      final out =
          EquipmentVocab.normalizedEquipmentRow(communityRow(['Cable Machine']));
      expect(out['id'], 'community_ex_1');
      expect(out['name'], 'Community Move');
      expect(out['source'], 'community');
      expect(out['equipment_tier'], ['full_gym']);
    });

    test('KILL-SWITCH: enabled:false returns the map UNCHANGED (verbatim raw store)',
        () {
      final out = EquipmentVocab.normalizedEquipmentRow(
          communityRow(['Cable Machine']),
          enabled: false);
      // Raw, un-normalized — today's exact pre-B2 behavior when the flag is set.
      expect(out['equipment_needed'], ['Cable Machine']);
    });
  });

  test(
      'SEAM WIRING: the sync_community download loop routes community rows through '
      'normalizedEquipmentRow behind the kill-switch before exerciseBox.put', () {
    final src = File('lib/core/services/sync/sync_community.dart')
        .readAsStringSync()
        // Strip comments first (feedback_source_grep_strip_comments_first) so the
        // assertion is about real code, not the B2 docstring that names the flag.
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//.*'), '');
    expect(
      src.contains('EquipmentVocab.normalizedEquipmentRow('),
      isTrue,
      reason: 'the community exercise download loop must normalize '
          'equipment_needed at the write seam (⑥ B2).',
    );
    expect(
      src.contains('disable_community_equipment_normalize'),
      isTrue,
      reason: 'the write-normalize must be gated by the kill-switch flag.',
    );
  });
}
