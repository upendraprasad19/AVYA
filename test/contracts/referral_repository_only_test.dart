// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-grep contract for audit finding A5 (2026-05-21).
///
/// CLAUDE.md rule #4: "no Supabase from widgets / providers". Every
/// referral_redemptions read + every redeem-referral Edge Function
/// invocation MUST be funnelled through
/// [ReferralRepository]. The repository's `.instance` static singleton
/// mirrors [SubmissionsRepository] from Test #11.
///
/// Pinned callers:
///   - lib/features/profile/providers/referral_eligibility_provider.dart
///   - lib/features/profile/screens/apply_referral_sheet.dart
///
/// Helper that strips `/* ... */` + `// ...` comments before substring
/// checks (per feedback_source_grep_strip_comments_first.md — comments
/// quoting the old anti-pattern would otherwise produce false-positive
/// failures here).
String _stripComments(String src) {
  return src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');
}

void main() {
  group('ReferralRepository — A5 audit (CLAUDE.md rule #4)', () {
    test(
      'apply_referral_sheet.dart no longer invokes redeem-referral directly',
      () async {
        final raw = await File(
          'lib/features/profile/screens/apply_referral_sheet.dart',
        ).readAsString();
        final src = _stripComments(raw);

        // The anti-pattern: Supabase.instance.client.functions.invoke(
        expect(
          src,
          isNot(contains('Supabase.instance.client.functions.invoke')),
          reason:
              'apply_referral_sheet must route through ReferralRepository.redeem '
              '(CLAUDE.md rule #4 / audit A5).',
        );
        // It should NOT import supabase_flutter at all anymore.
        expect(
          src,
          isNot(contains("import 'package:supabase_flutter/supabase_flutter.dart'")),
          reason:
              'apply_referral_sheet does not need supabase_flutter directly after A5.',
        );
        // It MUST import the repository.
        expect(
          src,
          contains(
            "import 'package:icanbefitter/features/profile/repositories/referral_repository.dart'",
          ),
          reason:
              'apply_referral_sheet must import ReferralRepository.',
        );
        // It MUST call the repository.
        expect(
          src,
          contains('ReferralRepository.instance.redeem'),
          reason:
              'apply_referral_sheet must call ReferralRepository.instance.redeem.',
        );
      },
    );

    test(
      'referral_eligibility_provider.dart no longer queries referral_redemptions directly',
      () async {
        final raw = await File(
          'lib/features/profile/providers/referral_eligibility_provider.dart',
        ).readAsString();
        final src = _stripComments(raw);

        expect(
          src,
          isNot(contains(".from('referral_redemptions')")),
          reason:
              'referral_eligibility_provider must route through '
              'ReferralRepository.hasRedeemed (CLAUDE.md rule #4 / audit A5).',
        );
        expect(
          src,
          contains('ReferralRepository.instance.hasRedeemed'),
          reason:
              'referral_eligibility_provider must call '
              'ReferralRepository.instance.hasRedeemed.',
        );
      },
    );

    test(
      'ReferralRepository file exists with canonical methods',
      () async {
        final file = File(
          'lib/features/profile/repositories/referral_repository.dart',
        );
        expect(file.existsSync(), isTrue,
            reason: 'ReferralRepository must exist at canonical path.');
        final raw = await file.readAsString();
        final src = _stripComments(raw);

        expect(src, contains('class ReferralRepository'),
            reason: 'ReferralRepository class must be defined.');
        expect(src, contains('static final ReferralRepository instance'),
            reason:
                'ReferralRepository must expose static `instance` singleton.');
        expect(src, contains('Future<bool> hasRedeemed('),
            reason: 'ReferralRepository must expose `hasRedeemed`.');
        expect(src, contains('Future<RedemptionResult> redeem('),
            reason: 'ReferralRepository must expose `redeem`.');
        expect(src, contains('ErrorTelemetry.recordNonFatal'),
            reason:
                'ReferralRepository error paths must call ErrorTelemetry.recordNonFatal '
                '(H-42 telemetry contract).');
      },
    );
  });
}
