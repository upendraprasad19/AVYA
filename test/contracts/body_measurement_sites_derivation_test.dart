@Timeout(Duration(minutes: 2))
library;

// L2a (OI-297) - PRESENCE ONLY (source-grep, said plainly): the five Dart
// consumers of the body-measurement site list derive from the registry and
// none carries a literal site list. The behaviour of the registry and of the
// pull rule is tested in test/sync/measurement_push_rules_test.dart; this file
// only keeps a sixth hard-coded copy from re-appearing.

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
  'lib/features/ai_coach/services/ai_snapshot_builder.dart':
      'kBodyMeasurementSites',
};

// A list literal that starts with a site token: ['waist', ... / ['chest', ...
final _siteListLiteral = RegExp(r"\[\s*'(chest|waist|hips|arms)'\s*,");

String _stripComments(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  for (final e in _consumers.entries) {
    test('${e.key} derives from the registry', () {
      final src = _stripComments(File(e.key).readAsStringSync());
      expect(src.contains(e.value), isTrue,
          reason: '${e.key} no longer uses ${e.value}');
      expect(_siteListLiteral.hasMatch(src), isFalse,
          reason: '${e.key} carries a literal site list');
    });
  }

  test('the rules file iterates the registry, not a literal list', () {
    final src = _stripComments(
        File('lib/core/services/sync/measurement_push_rules.dart')
            .readAsStringSync());
    expect(src.contains('kBodyMeasurementSites'), isTrue);
    expect(_siteListLiteral.hasMatch(src), isFalse);
  });
}
