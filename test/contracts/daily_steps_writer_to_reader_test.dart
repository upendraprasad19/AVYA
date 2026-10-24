// test/contracts/daily_steps_writer_to_reader_test.dart
//
// SoT contract for daily_steps (audit-fixwave 2026-07-02 / F8). Import-only
// (native Health Connect / Fit / Samsung Health); registered so the drift
// audit can see the sync↔restore pair. Comment-stripped.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final health = _strip(
      File('lib/core/services/sync/sync_health.dart').readAsStringSync());

  group('daily_steps sync↔restore contract', () {
    test('_syncStepsLogs upserts the daily_steps table', () {
      expect(health.contains('_syncStepsLogs'), isTrue);
      expect(health.contains("'daily_steps'") ||
          health.contains('"daily_steps"'), isTrue,
          reason: 'steps push targets the daily_steps table');
    });
    test('_restoreStepsLogs restores steps on reinstall', () {
      expect(health.contains('_restoreStepsLogs'), isTrue,
          reason: 'daily_steps must round-trip on restore');
    });
  });
}
