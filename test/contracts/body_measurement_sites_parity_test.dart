@Timeout(Duration(minutes: 2))
library;

// L2a (OI-297): the body-measurement site list is ONE set. The Dart constant,
// its TS twin, the live `body_measurements` columns, the two Edge Function
// prompt lists and the keys of a pushed payload must agree, so a site added in
// one place and missed in another cannot stay device-only (the writer/reader
// drift OI-297 names).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/body_measurement_sites.dart';
import 'package:icanbefitter/core/services/sync/measurement_push_rules.dart';

/// Columns of `body_measurements` that are not sites.
const _notSites = {'id', 'user_id', 'date', 'notes', 'created_at'};

/// Every `Measurement types:` list in [path]. Since coach-log-truth both
/// Edge Function ICBF blocks (ai-proxy and ai-media-proxy) live in
/// `_shared/write_claim_prompt.ts`, so the file must hold EXACTLY two.
List<Set<String>> _promptLists(String path) {
  final text = File(path).readAsStringSync();
  return RegExp(r'Measurement types: ([a-z, ]+?)\.')
      .allMatches(text)
      .map((m) => m.group(1)!.split(',').map((s) => s.trim()).toSet())
      .toList();
}

void main() {
  final dart = kBodyMeasurementSites.toSet();

  test('the Dart registry has no duplicates', () {
    expect(kBodyMeasurementSites.length, dart.length);
  });

  test('Dart constant == TS twin', () {
    final ts = File('supabase/functions/_shared/body_measurement_sites.ts')
        .readAsStringSync();
    final m = RegExp(r'BODY_MEASUREMENT_SITES\s*=\s*\[([^\]]*)\]').firstMatch(ts);
    expect(m, isNotNull);
    final twin = RegExp(r'"([a-z_]+)"')
        .allMatches(m!.group(1)!)
        .map((x) => x.group(1)!)
        .toList();
    expect(twin, kBodyMeasurementSites, reason: 'same tokens in the same order');
  });

  test('Dart constant == live body_measurements columns minus the fixed ones',
      () {
    final schema = jsonDecode(
            File('backups/live_schema_columns.json').readAsStringSync())
        as Map<String, dynamic>;
    final tables = schema['tables'] as Map<String, dynamic>;
    final cols = (tables['body_measurements'] as List).cast<String>().toSet();
    expect(cols.difference(_notSites), dart);
  });

  test('Dart constant == the Edge Function prompt lists (as sets)', () {
    final lists =
        _promptLists('supabase/functions/_shared/write_claim_prompt.ts');
    expect(lists, hasLength(2),
        reason: 'the ai-proxy block and the ai-media-proxy block');
    for (final l in lists) {
      expect(l, dart);
    }
  });

  test('Dart constant == the sites in a pushed payload for a full record', () {
    final legacy = measurementLegacyPayload(
      userId: 'u',
      date: 'd',
      log: {for (final s in kBodyMeasurementSites) s: 1.0},
      createdAt: 't',
    );
    expect(legacy.keys.toSet().difference({..._notSites}), dart);
    final body = measurementMergeSafeBody(legacy)!;
    expect(body.keys.toSet().difference({..._notSites}), dart);
  });
}
