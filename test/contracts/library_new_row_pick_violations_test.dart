// Batch C1 B-pass (reviewer B, 2026-10-26): `newRowPickViolations` (test/helpers/library_injury_floor.dart) is the R6 (i) and
// (ii) check that test/plan_generator/generator_golden_test.dart runs over every picked new id. Until now its only proof that
// it can fail was a one-off mutation recorded in the diagnose doc: no committed test fed it a violating row. This file does,
// one per branch, plus the mirror cases (an original E row is not scoped in; a clean new row passes).
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_injury_floor.dart';

void main() {
  late List<Map<String, dynamic>> lib;
  late Map<String, Map<String, dynamic>> byId;

  setUpAll(() {
    lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    byId = {for (final r in lib) r['id'] as String: r};
  });

  Map<String, dynamic> copyOf(Map<String, dynamic> r) => jsonDecode(jsonEncode(r)) as Map<String, dynamic>;

  List<String> check(Map<String, dynamic> row, {Map<String, Map<String, dynamic>>? ids}) => newRowPickViolations(
        personaKey: 'p',
        builtIds: [row['id'] as String],
        byId: ids ?? {...byId, row['id'] as String: row},
        library: lib,
      );

  Map<String, dynamic> firstNew(bool Function(Map<String, dynamic>) where) =>
      lib.firstWhere((r) => isNewRowId(r['id'] as String) && where(r));

  // A shipped new row that passes today: a strength row with its required tokens present (and not a skill / olympic /
  // plyometric / high-impact / coaching row), found rather than named so the file does not depend on one id.
  Map<String, dynamic> clean() => firstNew((r) =>
      r['discipline'] == 'strength' &&
      r['high_impact'] != true &&
      r['requires_coaching'] != true &&
      requiredTokens(r, lib).isNotEmpty &&
      newRowPickViolations(personaKey: 'p', builtIds: [r['id'] as String], byId: byId, library: lib).isEmpty);

  test('isNewRowId: G and N ids are new, E ids and junk are not', () {
    expect(isNewRowId('G0001'), isTrue);
    expect(isNewRowId('G3888'), isTrue);
    expect(isNewRowId('N03'), isTrue);
    expect(isNewRowId('E036'), isFalse);
    expect(isNewRowId('E274'), isFalse);
    expect(isNewRowId('Gx'), isFalse);
    expect(lib.where((r) => isNewRowId(r['id'] as String)).length, 629);
  });

  test('a clean new row yields no violation (the positive control for every case below)', () {
    expect(check(clean()), isEmpty);
  });

  for (final discipline in kNeverPickedDisciplines) {
    test('(i) a picked new $discipline row is a violation', () {
      final r = firstNew((x) => x['discipline'] == discipline);
      expect(check(r).where((v) => v.contains(' (i) ')), isNotEmpty, reason: '${r['id']} ${r['name']}');
    });
  }

  test('(i) a picked new high_impact row, and a picked new requires_coaching row, are each a violation', () {
    final a = copyOf(clean())..['high_impact'] = true;
    expect(check(a).where((v) => v.contains(' (i) ')), isNotEmpty);
    final b = copyOf(clean())..['requires_coaching'] = true;
    expect(check(b).where((v) => v.contains(' (i) ')), isNotEmpty);
  });

  test('(ii) a picked new row that lost a floor token is a violation, naming the token', () {
    final r = copyOf(clean());
    final need = requiredTokens(r, lib).first;
    r['injury_contraindications'] = [
      for (final t in (r['injury_contraindications'] as List).cast<String>())
        if (t != need) t,
      if (!requiredTokens(r, lib).contains('neck')) 'neck', // a tag that is not required, so the row is not untagged
    ];
    final v = check(r).where((x) => x.contains('without floor token $need')).toList();
    expect(v, isNotEmpty, reason: 'required $need, tags now ${r['injury_contraindications']}');
  });

  test('(ii) a picked new row with no tags at all is a violation unless its name is in the safe pool', () {
    final r = copyOf(clean())
      ..['injury_contraindications'] = <String>[]
      ..['name'] = 'Zz Not In The Safe Pool';
    final noFloor = copyOf(r)..['variant_family'] = 'zz_no_such_family';
    expect(check(noFloor).where((v) => v.contains('untagged and not a safe-pool name')), isNotEmpty);
  });

  test('an id that is not in the library is a violation, not a skip', () {
    final v = newRowPickViolations(personaKey: 'p', builtIds: const ['G9999'], byId: byId, library: lib);
    expect(v.single, contains('not in the library'));
  });

  test('MIRROR: an original E row is out of scope even when it is broken, and a built id list with no new id is clean', () {
    final broken = copyOf(byId['E036']!)
      ..['discipline'] = 'olympic'
      ..['injury_contraindications'] = <String>[];
    expect(check(broken), isEmpty);
    expect(newRowPickViolations(personaKey: 'p', builtIds: const [], byId: byId, library: lib), isEmpty);
  });
}
