import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F1 parity (audit 2026-06-07): the client free AI-message cap MUST equal the
/// server's `FREE_DAILY_LIMIT`. They had drifted — client declared 15/day + a
/// client-only 30-day trial, while the server enforces 10/day FOREVER (OQ-1).
/// Result: free users saw headroom then got 429'd at message 11, and after 30
/// days were locked out of the coach entirely by a trial the server doesn't have.
/// This pins client==server and the trial's removal so neither can drift again.
void main() {
  String stripComments(String s) {
    final noBlock = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    return noBlock
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i >= 0 ? l.substring(0, i) : l;
        })
        .join('\n');
  }

  test('client freeAiMessagesPerDay == server FREE_DAILY_LIMIT', () {
    final client = stripComments(
        File('lib/core/constants/app_constants.dart').readAsStringSync());
    final server = stripComments(
        File('supabase/functions/ai-proxy/index.ts').readAsStringSync());

    final cm = RegExp(r'freeAiMessagesPerDay\s*=\s*(\d+)').firstMatch(client);
    final sm = RegExp(r'FREE_DAILY_LIMIT\s*=\s*(\d+)').firstMatch(server);

    expect(cm, isNotNull, reason: 'freeAiMessagesPerDay not found in app_constants.dart');
    expect(sm, isNotNull, reason: 'FREE_DAILY_LIMIT not found in ai-proxy/index.ts');

    final clientCap = int.parse(cm!.group(1)!);
    final serverCap = int.parse(sm!.group(1)!);

    expect(clientCap, serverCap,
        reason: 'Client cap ($clientCap) must equal server FREE_DAILY_LIMIT '
            '($serverCap) — the server is authoritative (OQ-1: 10/day forever).');
    expect(clientCap, 10, reason: 'OQ-1 locks the free AI cap at 10/day.');
  });

  test('the vestigial 30-day trial stays fully removed', () {
    final constants = stripComments(
        File('lib/core/constants/app_constants.dart').readAsStringSync());
    expect(constants.contains('freeAiTrialDays'), isFalse,
        reason: 'freeAiTrialDays must stay deleted — the server has no trial (OQ-1).');

    final providerReintroduced = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .any((f) => stripComments(f.readAsStringSync()).contains('trialInfoProvider'));
    expect(providerReintroduced, isFalse,
        reason: 'trialInfoProvider must stay removed — it was the 30-day client-only lockout.');
  });
}
