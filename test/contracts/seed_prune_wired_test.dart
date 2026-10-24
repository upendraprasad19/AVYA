// Batch A Task 2 — presence only. The prune is proven behaviourally in
// library_seed_prune_behavioral_test.dart; this pins that `_seedExercises`
// actually CALLS it, after `putAll`, because `_seedExercises` loads its input
// from the asset bundle and cannot run in a unit test.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//.*'), '');

void main() {
  test('_seedExercises prunes retired ids after putAll', () {
    final src = _strip(
        File('lib/core/services/seed_service.dart').readAsStringSync());
    final start = src.indexOf('Future<void> _seedExercises()');
    expect(start, isNonNegative, reason: '_seedExercises not found');
    final end = src.indexOf('Future<void> _seedFoods()', start);
    final body = src.substring(start, end < 0 ? src.length : end);
    final put = body.indexOf('exerciseBox.putAll(entries)');
    final prune = body.indexOf('pruneRetired(');
    expect(put, isNonNegative, reason: 'putAll moved');
    expect(prune, greaterThan(put),
        reason: 'pruneRetired must run after putAll in _seedExercises');
  });
}
