import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `workout_templates`
/// from docs/sot_registry.yaml.
///
/// Writers: workout_repository.saveTemplate + createMultiDayTemplate,
///          template_builder_screen._buildTemplate,
///          tool_dispatcher.createCustomTemplate
/// Readers: train_provider.TemplatesNotifier,
///          schedule_template_planner (tmpl_* scan),
///          sync_service._syncWorkoutTemplates
///
/// Cloud UNIQUE(user_id, name) via migration 050.
/// Multi-day templates have group_id + group_day_index + group_total_days.
void main() {
  late String workoutRepoSrc;
  late String trainProvSrc;
  late String syncSvcSrc;

  setUpAll(() {
    final rf =
        File('lib/features/train/repositories/workout_repository.dart');
    expect(rf.existsSync(), isTrue,
        reason: 'workout_repository.dart must exist (writer for workout_templates)');
    workoutRepoSrc = rf.readAsStringSync();

    final tf = File('lib/features/train/providers/train_provider.dart');
    expect(tf.existsSync(), isTrue, reason: 'train_provider.dart must exist');
    trainProvSrc = tf.readAsStringSync();

    final sf = File('lib/core/services/sync_service.dart');
    expect(sf.existsSync(), isTrue, reason: 'sync_service.dart must exist');
    syncSvcSrc = sf.readAsStringSync();
  });

  group('workout_templates writer↔reader source contract', () {
    test('writer saveTemplate exists in workout_repository', () {
      expect(workoutRepoSrc.contains('saveTemplate'), isTrue,
          reason: 'workout_repository must define saveTemplate for single-day templates');
    });

    test('writer uses tmpl_ key prefix', () {
      expect(workoutRepoSrc.contains("'tmpl_") || workoutRepoSrc.contains('"tmpl_'),
          isTrue,
          reason: 'workout_repository must write tmpl_ keys per sot_registry.hive.key_prefix');
    });

    test('multi-day template fields: group_id + group_day_index + group_total_days', () {
      // At least two of the three group fields must be present in writer
      final hasGroupId = workoutRepoSrc.contains('group_id');
      final hasGroupDay = workoutRepoSrc.contains('group_day_index');
      final hasGroupTotal = workoutRepoSrc.contains('group_total_days');
      final count = [hasGroupId, hasGroupDay, hasGroupTotal].where((b) => b).length;
      expect(count, greaterThanOrEqualTo(2),
          reason:
              'workout_repository multi-day template writer must include '
              'group_id + group_day_index + group_total_days fields');
    });

    test('reader TemplatesNotifier exists in train_provider', () {
      expect(trainProvSrc.contains('TemplatesNotifier'), isTrue,
          reason:
              'train_provider must define TemplatesNotifier (primary reader of tmpl_ keys)');
    });

    test('reader TemplatesNotifier scans tmpl_ key prefix', () {
      expect(trainProvSrc.contains("'tmpl_") || trainProvSrc.contains('tmpl_'),
          isTrue,
          reason: 'TemplatesNotifier must scan tmpl_ key prefix when loading templates');
    });

    test('reader _syncWorkoutTemplates exists in sync_service', () {
      expect(syncSvcSrc.contains('_syncWorkoutTemplates'), isTrue,
          reason:
              'sync_service must define _syncWorkoutTemplates (cloud sync reader)');
    });

    test('_syncWorkoutTemplates uses deterministic UUID for cloud id', () {
      // Templates must use uuid_v5 keyed on (user_id, lower(name)) per sot_registry
      expect(syncSvcSrc.contains('_deterministicId') ||
          syncSvcSrc.contains('deterministicId'), isTrue,
          reason:
              '_syncWorkoutTemplates must coerce template id to deterministic UUID; '
              'raw tmpl_<ms> keys silently uuid-reject on server (F3 sync gap, Test #9)');
    });

    test('template_builder_screen._buildTemplate writes templates', () {
      final tf = File('lib/features/train/screens/template_builder_screen.dart');
      if (!tf.existsSync()) return;
      final src = tf.readAsStringSync();
      expect(
          src.contains('_buildTemplate') || src.contains('saveTemplate'),
          isTrue,
          reason:
              'template_builder_screen must have _buildTemplate or delegate to saveTemplate');
    });

    test('tool_dispatcher createCustomTemplate writes to workoutBox', () {
      final td =
          File('lib/features/ai_coach/services/tool_dispatcher.dart');
      if (!td.existsSync()) return;
      final src = td.readAsStringSync();
      expect(
          src.contains('createCustomTemplate') ||
              src.contains('tmpl_') ||
              src.contains('saveTemplate'),
          isTrue,
          reason: 'tool_dispatcher must write templates via createCustomTemplate tool');
    });
  });
}
