import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/migration_cap_reader.dart';

/// F1 parity (audit 2026-06-07): the client free AI-message cap MUST equal the
/// server's `FREE_DAILY_LIMIT`. They had drifted — client declared 15/day + a
/// client-only 30-day trial, while the server enforces 10/day FOREVER (OQ-1).
/// Result: free users saw headroom then got 429'd at message 11, and after 30
/// days were locked out of the coach entirely by a trial the server doesn't have.
/// This pins client==server and the trial's removal so neither can drift again.
///
/// WIDENED 2026-09-04 (b8f4c2). f1a70c's fix pinned the CHAT pair only, and food
/// text drifted the same way in the opposite direction — client + business-rules
/// said 10/day while the trigger allowed 50, a 5x direct-API bypass that lasted
/// four months. The lesson was never "pin this one number"; it was that a parity
/// fix must pin EVERY pair of the class.
///
/// WHERE EACH PAIR LIVES (Gate 9 requires one file per SoT concept, so the
/// enumeration is split by concept rather than kept in a single file):
///   - chat cap       -> here
///   - vision ceiling -> here (it has no SoT concept of its own)
///   - food text cap  -> food_text_analysis_daily_cap_writer_to_reader_test.dart
/// A NEW user-facing limit belongs in one of these, beside its siblings.
///
/// All server caps are resolved via test/helpers/migration_cap_reader.dart,
/// which takes the HIGHEST-numbered migration defining each function. See that
/// file's header for why anything else is stale by construction.
void main() {
  test('client freeAiMessagesPerDay == server FREE_DAILY_LIMIT', () {
    final server = stripDartComments(
        File('supabase/functions/ai-proxy/index.ts').readAsStringSync());

    final sm = RegExp(r'FREE_DAILY_LIMIT\s*=\s*(\d+)').firstMatch(server);
    expect(sm, isNotNull, reason: 'FREE_DAILY_LIMIT not found in ai-proxy/index.ts');

    final clientCap = clientIntConstant('freeAiMessagesPerDay');
    expect(clientCap, isNotNull,
        reason: 'freeAiMessagesPerDay not found in app_constants.dart');
    final serverCap = int.parse(sm!.group(1)!);

    expect(clientCap, serverCap,
        reason: 'Client cap ($clientCap) must equal server FREE_DAILY_LIMIT '
            '($serverCap) — the server is authoritative (OQ-1: 10/day forever).');
    expect(clientCap, 10, reason: 'OQ-1 locks the free AI cap at 10/day.');
  });

  test('server vision ceiling covers the full PRO per-channel allowance', () {
    final mig = latestMigrationDefining('enforce_vision_analysis_daily_limit');
    expect(mig, isNotNull,
        reason: 'No migration defines enforce_vision_analysis_daily_limit.');

    final ceiling = readSingleCeiling(mig!);
    expect(ceiling, isNotNull,
        reason: 'vision cap comparison not found in '
            '${mig.uri.pathSegments.last}.');

    final proScan = clientIntConstant('proScanMealPerDay');
    final proCart = clientIntConstant('proCartAuditorPerDay');
    expect(proScan, isNotNull);
    expect(proCart, isNotNull);
    final proTotal = proScan! + proCart!;

    // scan_meal and cart_auditor share ONE server budget while the client
    // advertises them independently, so the ceiling must cover their SUM.
    // Migration 114 raised 15 -> 20 for exactly this reason, after a compliant
    // PRO user hit a live 429 with headroom still showing in-app ("confirmed
    // live-discoverable, not hypothetical" — 114's own header).
    //
    // THIS ASSERTION IS THE TRIGGER for raising the ceiling. Adding a third
    // vision channel with its own advertised PRO allowance reddens the suite
    // until a new migration raises the shared ceiling to cover the new sum.
    // The founder plan of 2026-09-04 was "we'll increase the max to ~30 when we
    // add one" — an intention with nothing to fire it. Now it fires.
    expect(ceiling, greaterThanOrEqualTo(proTotal),
        reason: 'Vision ceiling ($ceiling, ${mig.uri.pathSegments.last}) is '
            'below the advertised PRO allowance (proScanMealPerDay $proScan + '
            'proCartAuditorPerDay $proCart = $proTotal). A PRO user using both '
            'features to their documented limits would get a 429 while the '
            'in-app counter still shows remaining. Raise the ceiling in a NEW '
            'migration (CREATE OR REPLACE) — do not lower the client numbers '
            'to fit.');

    // Free tier is nowhere near the ceiling (3 + 1 against 20). Asserted so a
    // future free-limit raise cannot quietly cross it either.
    final freeScan = clientIntConstant('freeScanMealPerDay');
    final freeCart = clientIntConstant('freeCartAuditorPerDay');
    expect(freeScan, isNotNull);
    expect(freeCart, isNotNull);
    expect(ceiling, greaterThanOrEqualTo(freeScan! + freeCart!),
        reason: 'Vision ceiling ($ceiling) must also cover the free allowance '
            '(${freeScan + freeCart}).');
  });

  test('the vestigial 30-day trial stays fully removed', () {
    final constants = stripDartComments(
        File('lib/core/constants/app_constants.dart').readAsStringSync());
    expect(constants.contains('freeAiTrialDays'), isFalse,
        reason: 'freeAiTrialDays must stay deleted — the server has no trial (OQ-1).');

    final providerReintroduced = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .any((f) =>
            stripDartComments(f.readAsStringSync()).contains('trialInfoProvider'));
    expect(providerReintroduced, isFalse,
        reason: 'trialInfoProvider must stay removed — it was the 30-day client-only lockout.');
  });
}
