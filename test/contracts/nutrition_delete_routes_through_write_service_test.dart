// Contract test — `DeleteNutritionLogNotifier.deleteFoodLog` MUST route
// through `NutritionWriteService.deleteLog` (not write to Hive directly).
//
// Closes OI-36 (audit-2026-05-17 Hermes C1). Pre-fix the notifier wrote
// `recent_deletes` audit + called `box.delete(logId)` bypassing the
// canonical writer entirely. The recent_deletes audit-log behavior now
// lives inside `NutritionWriteService.deleteLog` so every consumer of
// the canonical writer gets it uniformly.
//
// Lens L1 (writer/reader drift, 10th instance — see
// `feedback_writer_reader_field_drift_recurring.md`).

import 'dart:io';
import 'package:test/test.dart';

const _providerPath = 'lib/features/nutrition/providers/nutrition_provider.dart';
const _servicePath = 'lib/core/services/nutrition_write_service.dart';

void main() {
  group('OI-36 nutrition delete routes through NutritionWriteService', () {
    test('DeleteNutritionLogNotifier.deleteFoodLog calls NutritionWriteService.deleteLog',
        () {
      final src = File(_providerPath).readAsStringSync();

      // Find the deleteFoodLog method body via brace scan.
      final methodStart = RegExp(
        r'Future<void>\s+deleteFoodLog\s*\([^)]*\)\s*async\s*\{',
      ).firstMatch(src);
      expect(methodStart, isNotNull,
          reason: 'deleteFoodLog method declaration not found');
      // Brace-balance the body.
      int depth = 1;
      final start = methodStart!.end;
      int? end;
      for (int i = start; i < src.length; i++) {
        if (src[i] == '{') depth++;
        if (src[i] == '}') {
          depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
      }
      expect(end, isNotNull, reason: 'deleteFoodLog body brace-balance failed');
      final rawBody = src.substring(start, end!);
      // Strip Dart line + block comments before checking for forbidden
      // patterns — the OI-36 fix quotes the OLD pattern (`box.delete(logId)`)
      // inside a comment block for historical context, which would falsely
      // match a naive grep. Match same comment-stripping discipline as
      // verify_payment_notes_user_id_required_test.dart.
      final body = rawBody
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .replaceAll(RegExp(r'//[^\n]*'), '');

      expect(
        body.contains('NutritionWriteService.instance.deleteLog'),
        isTrue,
        reason:
            'deleteFoodLog must call NutritionWriteService.instance.deleteLog. '
            'Direct `box.delete` is forbidden — that bypasses mutex, audit '
            'log, undo stash, sync trigger, telemetry, and provider '
            'invalidation.',
      );

      // Forbid direct nutritionBox.delete inside this method body.
      final directDelete = RegExp(r'box\.delete\s*\(');
      expect(
        directDelete.hasMatch(body),
        isFalse,
        reason:
            'deleteFoodLog must NOT call `box.delete(...)` directly. Route '
            'through NutritionWriteService.deleteLog so the canonical writer '
            'owns the mutation.',
      );

      // Forbid direct recent_deletes write — that lives inside the
      // WriteService now.
      final directAudit = RegExp(
        "box\\.put\\s*\\(\\s*['\"]recent_deletes['\"]",
      );
      expect(
        directAudit.hasMatch(body),
        isFalse,
        reason:
            'deleteFoodLog must NOT write `recent_deletes` directly. The '
            'audit-log behavior lives inside NutritionWriteService.deleteLog '
            '(controlled by `writeAuditLog: true` parameter).',
      );
    });

    test('NutritionWriteService.deleteLog accepts writeAuditLog parameter', () {
      final src = File(_servicePath).readAsStringSync();
      final sigRegex = RegExp(
        r'Future<WriteResult>\s+deleteLog\s*\(\s*\{[^}]*writeAuditLog[^}]*\}',
        dotAll: true,
      );
      expect(
        sigRegex.hasMatch(src),
        isTrue,
        reason:
            'NutritionWriteService.deleteLog must accept `writeAuditLog: bool` '
            'parameter (default true). Caller may opt out for non-food '
            'nutritionBox keys.',
      );
    });

    test('recent_deletes audit write lives inside NutritionWriteService', () {
      final src = File(_servicePath).readAsStringSync();
      expect(
        src.contains("'recent_deletes'"),
        isTrue,
        reason:
            'recent_deletes write must live inside NutritionWriteService '
            '(it was moved from nutrition_provider.dart per OI-36).',
      );
    });
  });
}
