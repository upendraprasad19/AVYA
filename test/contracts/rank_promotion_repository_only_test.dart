// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-grep contract for audit finding A5 (2026-05-21).
///
/// CLAUDE.md rule #4: "no Supabase from widgets / providers". Every
/// `rank_promotions` read MUST be funnelled through
/// [RankPromotionRepository]. The repository's `.instance` static
/// singleton mirrors [SubmissionsRepository] from Test #11.
///
/// Helper that strips `/* ... */` + `// ...` comments before substring
/// checks (per feedback_source_grep_strip_comments_first.md).
String _stripComments(String src) {
  return src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');
}

void main() {
  group('RankPromotionRepository — A5 audit (CLAUDE.md rule #4)', () {
    test(
      'promotion_history_provider.dart no longer queries rank_promotions directly',
      () async {
        final raw = await File(
          'lib/features/profile/providers/promotion_history_provider.dart',
        ).readAsString();
        final src = _stripComments(raw);

        expect(
          src,
          isNot(contains(".from('rank_promotions')")),
          reason:
              'promotion_history_provider must route through '
              'RankPromotionRepository.getRecent (CLAUDE.md rule #4 / audit A5).',
        );
        expect(
          src,
          contains('RankPromotionRepository.instance.getRecent'),
          reason:
              'promotion_history_provider must call '
              'RankPromotionRepository.instance.getRecent.',
        );
      },
    );

    test(
      'RankPromotionRepository file exists with canonical method',
      () async {
        final file = File(
          'lib/features/profile/repositories/rank_promotion_repository.dart',
        );
        expect(file.existsSync(), isTrue,
            reason:
                'RankPromotionRepository must exist at canonical path.');
        final raw = await file.readAsString();
        final src = _stripComments(raw);

        expect(src, contains('class RankPromotionRepository'),
            reason: 'RankPromotionRepository class must be defined.');
        expect(src,
            contains('static final RankPromotionRepository instance'),
            reason:
                'RankPromotionRepository must expose static `instance` singleton.');
        expect(src, contains('Future<List<PromotionRecord>> getRecent('),
            reason:
                'RankPromotionRepository must expose `getRecent`.');
        expect(src, contains('ErrorTelemetry.recordNonFatal'),
            reason:
                'RankPromotionRepository error paths must call '
                'ErrorTelemetry.recordNonFatal (H-42 telemetry contract).');
      },
    );
  });
}
