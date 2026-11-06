// Contract test — `RankService.evaluateAndPromote` MUST update the local
// Hive profile AFTER the cloud `user_profile.current_rank_code` write,
// then fire `onStateChanged` so Riverpod listeners rebuild.
//
// Closes OI-37 (audit-2026-05-17 Hermes C2). Pre-fix the cloud write
// succeeded but the local Hive profile served the old rank until the
// next SyncService.restoreFromCloudForUser cycle — Profile / Home /
// Rank widgets all read local Hive via `getCurrentRank()`.
//
// Lens L1 (writer/reader drift — rank domain).

import 'dart:io';
import 'package:test/test.dart';

const _servicePath = 'lib/core/services/rank_service.dart';
const _appPath = 'lib/app.dart';

void main() {
  group('OI-37 rank promotion local profile update contract', () {
    test('RankService declares onStateChanged callback', () {
      final src = File(_servicePath).readAsStringSync();
      expect(
        RegExp(r'static\s+void\s+Function\(\)\?\s+onStateChanged')
            .hasMatch(src),
        isTrue,
        reason:
            'RankService must declare `static void Function()? onStateChanged` '
            'so app.dart can wire it to ref.invalidate(userProfileProvider).',
      );
    });

    test('evaluateAndPromote calls UserRepository.updateProfileFields with rank',
        () {
      final src = File(_servicePath).readAsStringSync();
      // Both fields must be written: current_rank_code + achieved_at.
      expect(
        src.contains('UserRepository.instance.updateProfileFields'),
        isTrue,
        reason:
            'RankService must update local Hive via UserRepository.updateProfileFields '
            'after the cloud user_profile update. Without it `getCurrentRank()` '
            'serves the old rank until next sync.',
      );
      expect(src.contains("'current_rank_code'"), isTrue);
      expect(src.contains("'current_rank_achieved_at'"), isTrue);
    });

    test('evaluateAndPromote fires onStateChanged after local write', () {
      final src = File(_servicePath).readAsStringSync();
      expect(
        RegExp(r'onStateChanged\?\.call\s*\(\s*\)').hasMatch(src),
        isTrue,
        reason:
            'RankService.evaluateAndPromote must call onStateChanged?.call() '
            'after the local profile update so Riverpod listeners rebuild.',
      );
    });

    test('app.dart wires RankService.onStateChanged to userProfileProvider', () {
      final src = File(_appPath).readAsStringSync();
      expect(
        RegExp(r'RankService\.onStateChanged\s*=').hasMatch(src),
        isTrue,
        reason:
            'app.dart must assign `RankService.onStateChanged = () => '
            'ref.invalidate(userProfileProvider)` mirroring the '
            'NutritionWriteService pattern.',
      );
      expect(
        src.contains('ref.invalidate(userProfileProvider)'),
        isTrue,
        reason:
            'expected `ref.invalidate(userProfileProvider)` somewhere in '
            'app.dart so the rank-rebuild path lands.',
      );
    });
  });
}
