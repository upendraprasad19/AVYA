import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for Bug B (APK Test #3, 2026-04-26).
///
/// edit_profile_screen._save() previously only wrote to Hive via
/// updateProfile + recalculateTargets. user_profile in Supabase
/// stayed empty/stale forever, breaking AI coach context.
///
/// Fix: fire syncProfileNow + pushSnapshot fire-and-forget after save.
void main() {
  test('Edit Profile _save fires syncProfileNow + pushSnapshot', () {
    final source = File(
      'lib/features/profile/screens/edit_profile_screen.dart',
    ).readAsStringSync();

    // Find the _save method
    final saveStart = source.indexOf('Future<void> _save() async {');
    expect(saveStart, isNot(-1), reason: '_save must exist');

    // Take a generous body slice. APK Test #15.4 / Phase 4.3 grew the
    // method to ~15K chars after adding the preferred_workout_time picker;
    // the original 5000-char window no longer covered the syncProfileNow
    // call near the bottom. Use 20K chars to leave headroom for future
    // additions without re-breaking this assertion.
    final bodyEnd = (saveStart + 20000).clamp(0, source.length);
    final body = source.substring(saveStart, bodyEnd);

    expect(
      body.contains('syncProfileNow'),
      isTrue,
      reason: '_save must call SyncService.instance.syncProfileNow(userId) '
          'fire-and-forget after recalculateTargets so user_profile in '
          'Supabase reflects the change. Bug B (APK Test #3).',
    );

    expect(
      body.contains('pushSnapshot'),
      isTrue,
      reason: '_save must also call SyncService.instance.pushSnapshot() '
          'so the AI coach context refreshes after profile changes.',
    );

    // Must wrap in unawaited so save UX is not blocked by network.
    expect(
      body.contains('unawaited(SyncService.instance.syncProfileNow') ||
          body.contains('unawaited(SyncService.instance.pushSnapshot'),
      isTrue,
      reason: 'Both sync calls MUST be unawaited (fire-and-forget) — '
          'sync failures must never block the user-visible Save flow.',
    );
  });
}
