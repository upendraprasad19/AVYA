import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/migration_cap_reader.dart';

/// F1 parity (audit 2026-06-07): the client free AI-message cap MUST equal the
/// server's chat cap (then `FREE_DAILY_LIMIT`, now `_shared/ai_limits.ts`). They had drifted — client declared 15/day + a
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
/// The numbers live in ONE TypeScript file (`_shared/ai_limits.ts`); the
/// migration literals are the enforcement; `AppConstants` is the client. Part B
/// (migration 153) changed all three at once: chat free 7 / PRO 20, vision
/// free 4 / PRO 20, PRO media 10 images / 5 videos.
int _tsInt(String src, String name) {
  final m = RegExp('export const $name\\s*=\\s*(\\d+);').firstMatch(src);
  expect(m, isNotNull, reason: '$name not found in _shared/ai_limits.ts');
  return int.parse(m!.group(1)!);
}

void main() {
  final limits = stripDartComments(
      File('supabase/functions/_shared/ai_limits.ts').readAsStringSync());

  test('chat: client free/PRO caps == ai_limits.ts == the live trigger literals', () {
    final mig = latestMigrationDefining('enforce_chat_app_daily_limit');
    expect(mig, isNotNull,
        reason: 'No migration defines enforce_chat_app_daily_limit.');
    final cap = readProFreeCap(mig!, 'enforce_chat_app_daily_limit');
    expect(cap, isNotNull,
        reason: 'daily_cap := CASE WHEN is_pro THEN <pro> ELSE <free> END not '
            'found in ${mig.uri.pathSegments.last} (the VARIABLE form is required '
            'so this reader and the parity tests can parse it).');

    final freeClient = clientIntConstant('freeAiMessagesPerDay');
    final proClient = clientIntConstant('proAiMessagesPerDay');
    expect(freeClient, isNotNull);
    expect(proClient, isNotNull);

    expect(freeClient, cap!.free,
        reason: 'Client free cap ($freeClient) must equal the trigger '
            '(${cap.free}, ${mig.uri.pathSegments.last}) — the server is authoritative.');
    expect(proClient, cap.pro,
        reason: 'Client PRO cap ($proClient) must equal the trigger (${cap.pro}).');
    expect(_tsInt(limits, 'FREE_CHAT_DAILY_CAP'), cap.free);
    expect(_tsInt(limits, 'PRO_CHAT_DAILY_CAP'), cap.pro);
    expect(cap.free, 7, reason: 'Founder 2026-10-01: free chat 7/day, forever (OQ-1: no trial).');
    expect(cap.pro, 20, reason: 'Founder 2026-10-01: PRO chat 20/day (25 is a later decision).');

    // ai-proxy derives its 429 cap from ai_limits.ts (chatCapFor); the old
    // FREE_DAILY_LIMIT alias had no reader left and is gone — a typed number
    // there would be a fourth copy.
    final server = stripDartComments(
        File('supabase/functions/ai-proxy/index.ts').readAsStringSync());
    expect(server.contains('FREE_DAILY_LIMIT'), isFalse,
        reason: 'the dead FREE_DAILY_LIMIT alias is back in ai-proxy.');
    expect(RegExp(r'limit:\s*chatCapFor\(refusedTier\)').hasMatch(server), isTrue,
        reason: 'the chat 429 body must take its limit from chatCapFor(tier).');
  });

  test('chat: only the pending RESERVATION row spends a unit (PRO media rows do not)', () {
    final mig = latestMigrationDefining('enforce_chat_app_daily_limit')!;
    final block = functionBlock(
        mig.readAsStringSync(), 'enforce_chat_app_daily_limit')!;
    expect(
        RegExp(r"NEW\.channel\s+IS\s+DISTINCT\s+FROM\s+'app'\s+OR\s+NEW\.model_used\s+IS\s+DISTINCT\s+FROM\s+'pending'")
            .hasMatch(block),
        isTrue,
        reason: 'The chat trigger must skip every non-reservation channel-app '
            'row; ai-media-proxy writes PRO media rows on channel app with a '
            'real label and they must not burn chat units.');
  });

  test('vision: free/PRO caps == ai_limits.ts == trigger; client per-feature caps fit under them', () {
    final mig = latestMigrationDefining('enforce_vision_analysis_daily_limit');
    expect(mig, isNotNull,
        reason: 'No migration defines enforce_vision_analysis_daily_limit.');
    final cap = readProFreeCap(mig!, 'enforce_vision_analysis_daily_limit');
    expect(cap, isNotNull,
        reason: 'daily_cap := CASE WHEN is_pro THEN <pro> ELSE <free> END not '
            'found in ${mig.uri.pathSegments.last}.');

    expect(_tsInt(limits, 'FREE_VISION_DAILY_CAP'), cap!.free);
    expect(_tsInt(limits, 'PRO_VISION_DAILY_CAP'), cap.pro);

    // scan_meal and cart_auditor share ONE server budget while the client
    // advertises them independently, so each tier's cap must cover the SUM of
    // that tier's advertised per-feature allowances (migration 114 raised
    // 15 -> 20 after a compliant PRO user hit a live 429 with headroom showing).
    // This compares against NAMED constants; a third vision channel fires it
    // only once its own constant is added to the sums below.
    final proSum = clientIntConstant('proScanMealPerDay')! +
        clientIntConstant('proCartAuditorPerDay')!;
    final freeSum = clientIntConstant('freeScanMealPerDay')! +
        clientIntConstant('freeCartAuditorPerDay')!;
    expect(cap.pro, greaterThanOrEqualTo(proSum),
        reason: 'PRO vision cap (${cap.pro}) is below the advertised PRO '
            'allowance ($proSum). Raise it in a NEW migration — do not lower '
            'the client numbers to fit.');
    expect(cap.free, greaterThanOrEqualTo(freeSum),
        reason: 'Free vision cap (${cap.free}) is below the advertised free '
            'allowance ($freeSum).');
    expect(cap.free, 4);
    expect(cap.pro, 20);
  });

  test('PRO media caps: ai-media-proxy literals == ai_limits.ts (10 images / 5 videos)', () {
    final media = stripDartComments(
        File('supabase/functions/ai-media-proxy/index.ts').readAsStringSync());
    final img = RegExp(r'const PRO_IMAGE_DAILY_CAP\s*=\s*(\d+);').firstMatch(media);
    final vid = RegExp(r'const PRO_VIDEO_DAILY_CAP\s*=\s*(\d+);').firstMatch(media);
    expect(img, isNotNull);
    expect(vid, isNotNull);
    expect(int.parse(img!.group(1)!), _tsInt(limits, 'PRO_IMAGE_DAILY_CAP'));
    expect(int.parse(vid!.group(1)!), _tsInt(limits, 'PRO_VIDEO_DAILY_CAP'));
    expect(_tsInt(limits, 'PRO_IMAGE_DAILY_CAP'), 10);
    expect(_tsInt(limits, 'PRO_VIDEO_DAILY_CAP'), 5);
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
