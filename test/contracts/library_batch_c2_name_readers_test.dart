// test/contracts/library_batch_c2_name_readers_test.dart
//
// Batch C2a (OI-460): production code quotes exercise names (the injury substitutes, the warm-up and cool-down lists;
// the universal pools were deleted with the cascade in Unit 1B-F). A name that matched a REMOVED row resolves to nothing after the removal, silently (queryV4 / search
// return no row, the slot falls through). This pins every quoted name against the shipped library: a name resolves to at
// most one row by name or alias, and a name equal to a removed row's name resolves to EXACTLY one (its alias target).
//
// Mutation: re-add a removed row's name to a quoted list; it then resolves to nothing -> red (the MUTATION test below).
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/injury_substitutes.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/warmup_cooldown.dart';

import '../helpers/injury_safe_pool.dart';

List<Map<String, dynamic>> _library() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

List<Map<String, dynamic>> _removedEntries() =>
    ((jsonDecode(File('scripts/data/library_batch_c2_removals.json').readAsStringSync()) as Map<String, dynamic>)['entries'] as List)
        .cast<Map<String, dynamic>>()
        .where((e) => e['decision'] == 'remove')
        .toList();

String _norm(Object? s) => '$s'.trim().toLowerCase();

/// Shipped rows a quoted [name] resolves to, by name or `name_aliases` (case-insensitive, trimmed).
List<String> resolve(List<Map<String, dynamic>> lib, String name) => [
      for (final r in lib)
        if (_norm(r['name']) == _norm(name) ||
            ((r['name_aliases'] as List?) ?? const []).any((a) => _norm(a) == _norm(name)))
          r['id'] as String
    ];

/// Every (source, name) quoted by production code.
Map<String, Set<String>> quotedNames() => {
      'InjurySubstitutes._preferred': {
        for (final inj in const ['shoulder', 'knee', 'lower_back', 'wrist', 'hip', 'elbow', 'ankle', 'neck'])
          ...InjurySubstitutes.preferredFor([inj]),
      },
      'warmup/cooldown lists': WarmupCooldownSelector.allMoveNames.toSet(),
      'kV14SafePool': kV14SafePool.toSet(),
    };

/// Violations for [quoted] against [lib] and the removed-name set [removedNames].
List<String> nameViolations(
  Map<String, Set<String>> quoted,
  List<Map<String, dynamic>> lib,
  Set<String> removedNames,
) {
  final out = <String>[];
  quoted.forEach((source, names) {
    for (final n in names) {
      final hits = resolve(lib, n);
      if (hits.length > 1) out.add('$source: "$n" resolves to ${hits.length} rows $hits');
      if (removedNames.contains(_norm(n)) && hits.length != 1) {
        out.add('$source: "$n" names a removed row and resolves to ${hits.length} rows');
      }
    }
  });
  return out;
}

void main() {
  late List<Map<String, dynamic>> lib;
  late Set<String> removedNames;
  setUpAll(() {
    lib = _library();
    removedNames = {for (final e in _removedEntries()) _norm(e['name'])};
  });

  test('every quoted production name resolves to at most one row, and a removed row\'s name to exactly one', () {
    expect(nameViolations(quotedNames(), lib, removedNames), isEmpty);
  });

  test('non-vacuity: the sources are non-empty, most quoted names resolve to a row, and removed names exist', () {
    final q = quotedNames();
    for (final e in q.entries) {
      expect(e.value, isNotEmpty, reason: e.key);
    }
    final all = {for (final names in q.values) ...names};
    final resolved = all.where((n) => resolve(lib, n).length == 1).length;
    expect(resolved, greaterThan(all.length ~/ 2), reason: 'most quoted names must resolve; the resolver may be reading nothing');
    // 50 removals of Batch C2a plus the 6 of Batch C2b (OI-462): the count follows the removals file.
    expect(removedNames.length, greaterThanOrEqualTo(_removedEntries().map((e) => _norm(e['name'])).toSet().length));
    expect(_removedEntries(), hasLength(greaterThanOrEqualTo(56)));
  });

  test('MUTATION: a pool that re-adds a removed name with no alias target is red', () {
    final q = quotedNames();
    final withGhost = {
      ...q,
      'mutated list': {...q['InjurySubstitutes._preferred']!, 'Ghost Removed Row'},
    };
    // A removed name no shipped row carries: nothing resolves it.
    final ghostLib = lib;
    final violations = nameViolations(withGhost, ghostLib, {...removedNames, _norm('Ghost Removed Row')});
    expect(violations, isNotEmpty);
    expect(violations.single, contains('Ghost Removed Row'));
  });

  // Batch C2b (OI-462): the field also holds IDS on 21 rows (E043 named "E111"), so an id of a removed row with no shipped row of
  // that id dangles too.
  List<String> danglingRemovedRefs(List<Map<String, dynamic>> rows) {
    final removedIds = {for (final e in _removedEntries()) e['id'] as String};
    return [
      for (final r in rows)
        for (final f in const ['standard_swap', 'progression_to', 'regression_to'])
          if (r[f] is String && removedNames.contains(_norm(r[f])) && !rows.any((x) => _norm(x['name']) == _norm(r[f])))
            '${r['id']}.$f -> ${r[f]}'
          else if (r[f] is String && removedIds.contains(r[f]) && !rows.any((x) => x['id'] == r[f]))
            '${r['id']}.$f -> ${r[f]} (id)',
    ];
  }

  test('no row\'s standard_swap / progression_to / regression_to names a removed row (B-pass finding 2)', () {
    expect(danglingRemovedRefs(lib), isEmpty);
  });

  test('MUTATION: a swap pointing at a removed name is red', () {
    final probe = lib.map((r) => {...r}).toList();
    final removedName = _removedEntries().first['name'] as String;
    probe.first['standard_swap'] = removedName;
    expect(danglingRemovedRefs(probe), isNotEmpty);
  });

  test('MUTATION: a swap pointing at a removed ID is red (E043 named E111)', () {
    final probe = lib.map((r) => {...r}).toList();
    probe.first['standard_swap'] = 'E111';
    expect(danglingRemovedRefs(probe), isNotEmpty);
  });

  test('MUTATION: an alias carried by two rows is red', () {
    final dup = lib.map((r) => {...r}).toList();
    final target = dup.firstWhere((r) => (r['name_aliases'] as List?)?.isNotEmpty ?? false);
    final alias = (target['name_aliases'] as List).first as String;
    final other = dup.firstWhere((r) => r['id'] != target['id']);
    other['name_aliases'] = [...((other['name_aliases'] as List?) ?? const []), alias];
    expect(
      nameViolations({'probe': {alias}}, dup, removedNames),
      isNotEmpty,
    );
  });
}
