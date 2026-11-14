// Regression test for audit 2026-05-16 / F3-1.1 (coach_notes upward sync).
//
// Bug: `coach_memory.coach_notes` was 100% NULL in cloud (4/4 rows across all
// users) because the Hive-to-cloud sync method `syncCoachMemoryNow` projected
// 8 muster fields but never `coaching_notes`. The Hive key is `coaching_notes`
// (preserved for back-compat with widgets reading it directly); the cloud
// column is `coach_notes`. With no upward write, AI memory was lost on every
// reinstall — the rolling-context Edge Function couldn't see prior memories.
//
// This test is a source-grep contract test: it scans `sync_coach.dart` for
// the canonical `coaching_notes -> coach_notes` mapping inside the
// `syncCoachMemoryNow` method body. If the mapping is removed or renamed,
// the test fails before the next APK ships.
//
// closes-diagnose: 2026-05-16-coach-notes-upward-sync

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'syncCoachMemoryNow projects coachBox[coaching_notes] -> cloud coach_notes column',
      () {
    final file = File('lib/core/services/sync/sync_coach.dart');
    expect(file.existsSync(), isTrue,
        reason: 'sync_coach.dart must exist at the expected path');
    final src = file.readAsStringSync();

    // Find the syncCoachMemoryNow method body.
    final methodStart = src.indexOf('Future<void> syncCoachMemoryNow(');
    expect(methodStart, isNot(-1),
        reason: 'syncCoachMemoryNow method must exist');
    // Grab a slice large enough to cover the method body (~2 KB is plenty).
    final slice = src.substring(
      methodStart,
      (methodStart + 2500).clamp(0, src.length),
    );

    // The Hive read MUST be `coaching_notes`.
    expect(slice.contains("coach.get('coaching_notes')"), isTrue,
        reason:
            "syncCoachMemoryNow must read Hive key 'coaching_notes' (back-compat). "
            "Hive readers throughout the app use 'coaching_notes' literally; this "
            "key is preserved per docs/architecture/sync.md Hive field-name contract.");

    // The cloud write MUST be `coach_notes`.
    expect(slice.contains("payload['coach_notes']"), isTrue,
        reason:
            "syncCoachMemoryNow must write the cloud column 'coach_notes'. "
            "Without this, AI coach memory is lost on every reinstall.");
  });
}
