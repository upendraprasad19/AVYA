// test/contracts/custom_food_mutations_writer_to_reader_test.dart
//
// SoT contract for custom_food_mutations (audit-fixwave 2026-07-02 / F6).
// The write path was correct but unregistered — this pins the writer→cloud
// contract so a future table rename / key drift fails a gate instead of
// silently breaking custom-food sync. Comment-stripped so a contract described
// only in a comment cannot satisfy it.
//
// closes-diagnose: (coverage — no bug; registration of a correct-but-unpinned path)

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final prov = _strip(File(
          'lib/features/nutrition/providers/nutrition_provider.dart')
      .readAsStringSync());

  group('custom_food_mutations writer→cloud contract', () {
    test('addCustomFood writes a custom_food_ Hive key', () {
      expect(prov.contains('addCustomFood'), isTrue);
      expect(prov.contains("'custom_food_"), isTrue,
          reason: 'writer must key customBox under custom_food_<ms>');
    });
    test('addCustomFood triggers immediate custom-items sync', () {
      expect(prov.contains('syncCustomItemsNow'), isTrue,
          reason: 'custom food must sync to user_custom_foods immediately');
    });
    test('cloud table is user_custom_foods with onConflict id', () {
      final comm = _strip(
          File('lib/core/services/sync/sync_community.dart').readAsStringSync());
      expect(comm.contains('user_custom_foods'), isTrue);
      expect(comm.contains("onConflict: 'id'") ||
          comm.contains('onConflict: "id"'), isTrue,
          reason: 'user_custom_foods upsert keys on the row id (v5 uuid)');
    });
  });
}
