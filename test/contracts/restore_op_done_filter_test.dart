// test/contracts/restore_op_done_filter_test.dart
//
// Contract — closes-diagnose e5b2a9 (Unit E), closes-oi OI-151. A fast
// successful restore/sync op must not write a client_errors row; a SLOW one
// still does (that is the signal restore_op_done exists for); the kill-switch
// restores log-everything.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/restore_telemetry_policy.dart';

void main() {
  test('fast ops are not logged', () {
    expect(
        shouldLogRestoreOpDone(const Duration(milliseconds: 111), alwaysLog: false),
        isFalse);
  });
  test('boundary: 1999 ms not logged, 2000 ms logged', () {
    expect(
        shouldLogRestoreOpDone(const Duration(milliseconds: 1999), alwaysLog: false),
        isFalse);
    expect(
        shouldLogRestoreOpDone(const Duration(milliseconds: 2000), alwaysLog: false),
        isTrue);
  });
  test('MIRROR: a slow op is always logged', () {
    expect(shouldLogRestoreOpDone(const Duration(seconds: 11), alwaysLog: false),
        isTrue);
  });
  test('kill-switch (alwaysLog) logs even a 1 ms op', () {
    expect(shouldLogRestoreOpDone(const Duration(milliseconds: 1), alwaysLog: true),
        isTrue);
  });

  test('wiring: _safeRestoreOp consults the policy before logging restore_op_done', () {
    final src = File('lib/core/services/sync_service.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final i = src.indexOf("'restore_op_done'");
    expect(i, greaterThan(-1), reason: 'the event itself must still exist');
    final lead = src.substring((i - 260).clamp(0, src.length), i);
    expect(lead.contains('shouldLogRestoreOpDone('), isTrue);
    expect(lead.contains('_restoreOpDoneFilterDisabled'), isTrue);
  });

  test('the kill-switch key literal is pinned (a typo would silently disable it)',
      () {
    final src = File('lib/core/services/sync_service.dart').readAsStringSync();
    final i = src.indexOf('bool get _restoreOpDoneFilterDisabled');
    expect(i, greaterThan(-1));
    final body = src.substring(i, (i + 260).clamp(0, src.length));
    expect(body.contains("'disable_restore_op_done_filter'"), isTrue);
  });
}
