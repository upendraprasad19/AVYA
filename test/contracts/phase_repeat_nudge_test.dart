// ⑧ 8-B / UNIT 3-a2 — the low-adherence "you repeated — step it up?" nudge,
// PRODUCTION behavioral test (account behavioral_test_path; SoT concept
// `phase_repeat_nudge`). Pins the writer→reader contract that a source-grep
// CANNOT (Gate-18's reader-manifest detector does not see MigratedKey.read/write
// — feedback_source_grep_false_confidence):
//
//   - WRITER: advanceProPhaseIfExpired sets `phase_repeat_nudge_pending` (true)
//     via MigratedKey on an actual repeat. Modelled here by a direct
//     MigratedKey.write under an open session.
//   - READER: phaseRepeatNudgeProvider surfaces it; the flag SURVIVES a rebuild
//     (reading must not clear it) and is cleared ONLY by the explicit dismiss.
//   - USER-SCOPED: written under user A, invisible to user B (no cross-account
//     leak — the codified expiry-banner P0 class).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';

String _strip(String s) {
  final noBlock = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('phase_repeat_nudge (⑧ 3-a2) writer→reader', () {
    const userA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    const userB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('repeat_nudge');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
    });

    tearDownAll(() async {
      await Hive.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      await HiveUserSession.openForUser(userA);
      await MigratedKey.write('phase_repeat_nudge_pending', false); // reset
    });

    test('set → provider reads true; SURVIVES a rebuild; dismiss clears it',
        () async {
      await MigratedKey.write('phase_repeat_nudge_pending', true);

      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(phaseRepeatNudgeProvider), isTrue,
          reason: 'the flag the advance set surfaces the nudge on Home');

      // A rebuild (invalidation) must re-read the SAME flag — reading it must
      // NOT clear it (P1-C: clear only on explicit dismiss, never in build).
      c.invalidate(phaseRepeatNudgeProvider);
      expect(c.read(phaseRepeatNudgeProvider), isTrue,
          reason: 'the nudge must persist across Home rebuilds until dismiss');

      // Explicit dismiss clears it AND persists false to the user store.
      c.read(phaseRepeatNudgeProvider.notifier).dismiss();
      expect(c.read(phaseRepeatNudgeProvider), isFalse);
      c.invalidate(phaseRepeatNudgeProvider);
      expect(c.read(phaseRepeatNudgeProvider), isFalse,
          reason: 'dismiss persisted false — the nudge does not resurrect');
    });

    test('user-scoped: user A\'s nudge does not leak to user B', () async {
      await MigratedKey.write('phase_repeat_nudge_pending', true); // under A

      final cA = ProviderContainer();
      addTearDown(cA.dispose);
      expect(cA.read(phaseRepeatNudgeProvider), isTrue);

      // Switch the Hive session owner to B — B's userBox never held the flag.
      await HiveUserSession.openForUser(userB);
      final cB = ProviderContainer();
      addTearDown(cB.dispose);
      expect(cB.read(phaseRepeatNudgeProvider), isFalse,
          reason: 'MigratedKey is user-scoped (userBox) — no cross-account leak '
              '(the codified expiry-banner P0 class)');
    });

    // The load-bearing cross-account WRITE gate (P1-A). The null-owner runtime
    // state (uid non-null but currentOwnerFullId null) is impractical to
    // simulate behaviorally, so this pins the codified belt against SILENT
    // REMOVAL (comment-stripped so the explanatory comment naming the accessor
    // cannot satisfy it). Removing the gate re-opens the device-shared configBox
    // leak MigratedKey.write falls back to when the owner is null.
    test('the nudge write is gated on currentOwnerFullId != null', () {
      final src = _strip(
          File('lib/shared/services/pro_phase_advance.dart').readAsStringSync());
      expect(
        RegExp(r'result\.repeated\s*&&\s*HiveUserSession\.currentOwnerFullId\s*!=\s*null')
            .hasMatch(src),
        isTrue,
        reason: 'the phase_repeat_nudge_pending write must stay owner-gated',
      );
    });
  });
}
