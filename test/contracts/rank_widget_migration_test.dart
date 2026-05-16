// Regression test for audit 2026-05-16 / E.11 (RankChip + RankInsignia legacy
// widget deletion).
//
// Bug: CLAUDE.md §9 documented `RankChip` + `RankInsignia` as "slated for
// removal", but 5+ live callsites remained for 3 weeks after the canonical
// `WardRankPill` / `WardRankInsignia` shipped (APK Test #6). Founder
// approved Phase D NEEDS_DECISION 1 Option A — migrate callsites + delete
// the legacy files in this batch.
//
// closes-diagnose: 2026-05-16-rank-widget-migration

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Audit-2026-05-16 / E.11 — legacy rank widgets deleted', () {
    test('legacy rank_chip.dart file no longer exists', () {
      final f = File('lib/shared/widgets/wardroom/rank_chip.dart');
      expect(f.existsSync(), isFalse,
          reason:
              'audit-2026-05-16 E.11 deleted the legacy RankChip widget. '
              'Canonical is WardRankPill (composite of WardRankInsignia + '
              'capsname + chevron).');
    });

    test('legacy rank_insignia.dart file no longer exists', () {
      final f = File('lib/shared/widgets/wardroom/rank_insignia.dart');
      expect(f.existsSync(), isFalse,
          reason:
              'audit-2026-05-16 E.11 deleted the legacy RankInsignia widget. '
              'Canonical is WardRankInsignia (CustomPaint, 11 painters '
              'dispatched by rankCode).');
    });

    test('wardroom barrel does not re-export the deleted files', () {
      final src =
          File('lib/shared/widgets/wardroom/wardroom.dart').readAsStringSync();
      expect(src.contains("export 'rank_chip.dart'"), isFalse,
          reason: 'barrel must not export deleted rank_chip.dart');
      expect(src.contains("export 'rank_insignia.dart'"), isFalse,
          reason: 'barrel must not export deleted rank_insignia.dart');
    });

    test('previously-known callsites have migrated to WardRankInsignia', () {
      // The 5 callsites identified in audit Agent 1 F1-N2:
      const paths = [
        'lib/features/profile/widgets/rank_chip_full_width.dart',
        'lib/features/profile/widgets/service_record_section.dart',
        'lib/features/train/screens/phase_roadmap_screen.dart',
      ];
      for (final p in paths) {
        final src = File(p).readAsStringSync();
        // Must NOT contain legacy RankInsignia constructor call.
        // (Allow `WardRankInsignia` and commentary mentions of "RankInsignia".)
        final hasLegacyCtor = RegExp(r'(?<![\w])RankInsignia\s*\(')
            .allMatches(src)
            .map((m) {
          // Reject only if the prefix is NOT `Ward`.
          final start = m.start;
          final preceding = src.substring((start - 4).clamp(0, src.length), start);
          return !preceding.endsWith('Ward');
        }).any((isLegacy) => isLegacy);
        expect(hasLegacyCtor, isFalse,
            reason:
                '$p still constructs the legacy RankInsignia. Migrate to '
                'WardRankInsignia (+ optional `color: AppColors.textMute` '
                'for the "dimmed" variant).');
      }
    });

    test('no remaining import of the deleted files', () {
      // Walk the entire lib/ tree. ZERO files may import the deleted shims.
      final libDir = Directory('lib');
      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        if (src.contains("widgets/wardroom/rank_chip.dart") ||
            src.contains("widgets/wardroom/rank_insignia.dart")) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty,
          reason:
              'No file under lib/ may import the deleted legacy rank '
              'widget files. Offenders: ${offenders.join(", ")}');
    });
  });
}
