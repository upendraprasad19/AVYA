@Timeout(Duration(minutes: 2))
library;

// L2a (OI-297) - PRESENCE ONLY (source-grep, said plainly). Two rules:
//
//  1. the six named Dart consumers of the body-measurement site list use the
//     registry symbol (or, for the snapshot, the reader that does) and none
//     carries a literal site list;
//  2. LIB-WIDE: no flat list / set / map literal under lib/ other than the
//     registry itself carries two or more of the four site tokens, so a sixth
//     hard-coded copy cannot appear in a file nobody thought to name (the L2b
//     sheet and provider are the next consumers).
//
// What rule 2 cannot see, said plainly: a literal that contains a call or a
// statement (`[f('chest'), ...]`), an `==` / `||` chain, a `switch`, a single
// token on its own. The Edge Function copies are the parity test's business
// (body_measurement_sites_parity_test.dart). The behaviour of the registry and
// of the pull rule is tested in test/sync/measurement_push_rules_test.dart;
// the whitelist call sites in test/ai_coach/log_measurement_site_whitelist_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// file -> the registry symbol it must use.
const _consumers = <String, String>{
  'lib/core/services/sync/sync_health.dart': 'measurementLegacyPayload(',
  'lib/core/services/sync_service.dart': 'mergeCloudSitesIntoLocal(',
  'lib/features/ai_coach/providers/ai_coach_provider.dart':
      'isBodyMeasurementSite(',
  'lib/features/ai_coach/services/conversational_log_handler.dart':
      'isBodyMeasurementSite(',
  // L2b Landing A: the snapshot no longer walks the sites itself; it asks the
  // reader, and the reader walks the registry.
  'lib/features/ai_coach/services/ai_snapshot_builder.dart': 'latestBySite(',
  'lib/core/services/health_read_service.dart': 'kBodyMeasurementSites',
};

const _registryPath = 'lib/core/constants/body_measurement_sites.dart';

// A list literal that starts with a site token: ['waist', ... / ['chest', ...
final _siteListLiteral = RegExp(r"\[\s*'(chest|waist|hips|arms)'\s*,");

final _siteToken = RegExp('''(['"])(chest|waist|hips|arms)\\1''');

/// A bracket pair holding no nested bracket, call, statement or arrow: a flat
/// list / set / map literal of plain values. Function bodies always hold a `;`
/// or a `(` and never match.
final _flatLiteral = RegExp(r'[\[{][^\[\]{};()]*[\]}]');

/// [src] without `/* */` blocks and `//` line comments (a `//` after an even
/// number of quotes on its line, so `'https://x'` survives).
String stripComments(String src) {
  final noBlocks = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlocks.split('\n').map((line) {
    final i = line.indexOf('//');
    if (i < 0) return line;
    final head = line.substring(0, i);
    final quotes = "'".allMatches(head).length + '"'.allMatches(head).length;
    return quotes.isEven ? head : line;
  }).join('\n');
}

/// Every flat literal in [src] (comments ignored) carrying at least two
/// DISTINCT site tokens.
List<String> multiSiteLiterals(String src) => [
  for (final m in _flatLiteral.allMatches(stripComments(src)))
    if (_siteToken
            .allMatches(m.group(0)!)
            .map((t) => t.group(2))
            .toSet()
            .length >=
        2)
      m.group(0)!,
];

void main() {
  for (final e in _consumers.entries) {
    test('${e.key} derives from the registry', () {
      final src = stripComments(File(e.key).readAsStringSync());
      expect(
        src.contains(e.value),
        isTrue,
        reason: '${e.key} no longer uses ${e.value}',
      );
      expect(
        _siteListLiteral.hasMatch(src),
        isFalse,
        reason: '${e.key} carries a literal site list',
      );
      expect(
        multiSiteLiterals(src),
        isEmpty,
        reason: '${e.key} carries a multi-site literal',
      );
    });
  }

  test('the rules file iterates the registry, not a literal list', () {
    final src = stripComments(
      File(
        'lib/core/services/sync/measurement_push_rules.dart',
      ).readAsStringSync(),
    );
    expect(src.contains('kBodyMeasurementSites'), isTrue);
    expect(_siteListLiteral.hasMatch(src), isFalse);
    expect(multiSiteLiterals(src), isEmpty);
  });

  test('LIB-WIDE: the registry holds the only multi-site literal under lib/', () {
    final offenders = <String>[];
    var scanned = 0;
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      scanned++;
      if (f.path == _registryPath) continue;
      for (final lit in multiSiteLiterals(f.readAsStringSync())) {
        offenders.add('${f.path}: ${lit.replaceAll(RegExp(r'\s+'), ' ')}');
      }
    }
    expect(scanned, greaterThan(100), reason: 'the walk must see lib/');
    expect(
      offenders,
      isEmpty,
      reason:
          'derive from kBodyMeasurementSites '
          '(lib/core/constants/body_measurement_sites.dart) instead of '
          'copying the list',
    );
  });

  test('the scan is not vacuous: it sees the registry\'s own literal', () {
    expect(
      multiSiteLiterals(File(_registryPath).readAsStringSync()),
      hasLength(1),
    );
  });

  group('multiSiteLiterals (the scanner, negative controls)', () {
    test('flags lists, sets and maps in either quote style', () {
      expect(multiSiteLiterals("final a = ['chest', 'waist'];"), hasLength(1));
      expect(multiSiteLiterals("const a = {'waist', 'hips'};"), hasLength(1));
      expect(multiSiteLiterals('final a = {"chest": 1, "arms": 2};'), hasLength(1));
      expect(
        multiSiteLiterals("const a = [\n  'hips',\n  'x',\n  'arms',\n];"),
        hasLength(1),
      );
    });

    test('ignores one token, code blocks, calls and comments', () {
      expect(multiSiteLiterals("const a = ['chest', 'delt', 'biceps'];"), isEmpty);
      expect(
        multiSiteLiterals("void f() { final a = 'chest'; final b = 'arms'; }"),
        isEmpty,
      );
      expect(multiSiteLiterals("g('chest', 'waist');"), isEmpty);
      expect(multiSiteLiterals("// ['chest', 'waist']"), isEmpty);
      expect(multiSiteLiterals("/* ['chest', 'waist'] */"), isEmpty);
      expect(multiSiteLiterals("final x = 1; // ['chest', 'waist']"), isEmpty);
    });

    test('a // inside a string literal does not hide what follows', () {
      expect(
        multiSiteLiterals("final u = 'https://x'; final a = ['hips', 'arms'];"),
        hasLength(1),
      );
    });
  });
}
