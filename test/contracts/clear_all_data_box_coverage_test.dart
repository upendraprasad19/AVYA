import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CONTRACT: every non-seed Hive box getter must be in clearAllData', () {
    final hiveServiceFile = File('lib/core/services/hive_service.dart');
    final userRepoFile = File('lib/shared/repositories/user_repository.dart');

    expect(hiveServiceFile.existsSync(), true,
        reason: 'HiveService file must exist at expected path');
    expect(userRepoFile.existsSync(), true,
        reason: 'UserRepository file must exist at expected path');

    final hiveServiceSrc = hiveServiceFile.readAsStringSync();
    final userRepoSrc = userRepoFile.readAsStringSync();

    final boxNamePattern = RegExp(r'static const String (\w+)BoxName\s*=');
    final allBoxes = boxNamePattern
        .allMatches(hiveServiceSrc)
        .map((m) => m.group(1)!)
        .toSet();

    expect(allBoxes.length, greaterThanOrEqualTo(8),
        reason: 'Should find at least 8 box constants in HiveService');

    final seedBoxes = {'exercise', 'food'};
    final mustBeCleared = allBoxes.difference(seedBoxes);

    for (final boxRoot in mustBeCleared) {
      final pattern = '_hive.${boxRoot}Box.clear()';
      expect(userRepoSrc.contains(pattern), true,
          reason: 'clearAllData must call _hive.${boxRoot}Box.clear() — '
              'box "$boxRoot" found in HiveService but not in clearAllData. '
              'Add to UserRepository.clearAllData() in user_repository.dart.');
    }
  });
}
