import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

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

    final sf = loadSyncServiceSource();
    expect(sf.existsSync(), isTrue, reason: 'sync_service.dart must exist');
    syncSvcSrc = sf.readAsStringSync();
  });

  group('workout_templates writer↔reader source contract', () {
    test('writer saveTemplate exists in workout_repository', () {
      expect(workoutRepoSrc.contains('saveTemplate'), isTrue,
          reason: 'workout_repository must define saveTemplate for single-day templates');
    });

    test('writer mints template identity via newTemplateKey (OI-252)', () {
      // OI-252 (2026-09-27) replaced the literal 'tmpl_<ms+i>' key formula
      // with a client-minted UUID v4 via WorkoutWriteService.newTemplateKey()
      // — every create call site (including this AI multi-day loop) routes
      // through it now, so the key prefix itself never appears as a source
      // literal here any more (it lives inside templateKeyFor()).
      expect(workoutRepoSrc.contains('newTemplateKey'), isTrue,
          reason: 'workout_repository must mint template identity via '
              'WorkoutWriteService.instance.newTemplateKey() per '
              'sot_registry.hive.key_formula');
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

    test('reader TemplatesNotifier filters by type field, mints new '
        'identities via newTemplateKey (OI-252)', () {
      // Per sot_registry: "Key prefix scan NOT used because the legacy
      // tmpl_<name_hash> key is preserved alongside the modern key for
      // back-compat" — TemplatesNotifier.build has always filtered by the
      // `type` field, not a key-prefix scan; OI-252 additionally routes
      // template creation through the shared identity minter.
      expect(trainProvSrc.contains("== 'template'"), isTrue,
          reason: "TemplatesNotifier.build must filter workoutBox values "
              "by w['type'] == 'template'");
      expect(trainProvSrc.contains('newTemplateKey'), isTrue,
          reason: 'TemplatesNotifier.saveTemplate must mint identity via '
              'WorkoutWriteService.instance.newTemplateKey()');
    });

    test('reader _syncWorkoutTemplates exists in sync_service', () {
      expect(syncSvcSrc.contains('_syncWorkoutTemplates'), isTrue,
          reason:
              'sync_service must define _syncWorkoutTemplates (cloud sync reader)');
    });

    test('_syncWorkoutTemplates upserts by the client-minted id, NOT a '
        'name-derived/deterministic one (OI-252)', () {
      // OI-252 (2026-09-27) superseded the deterministic-UUID-keyed-on-name
      // scheme — that WAS the root cause of bug A (delete-then-recreate
      // resurrection): a name-derived identity meant a locally-deleted row
      // and its live replacement collided on the SAME cloud id. The cloud
      // id is now `cloudIdFromKey(key)` (the client-minted uuid baked into
      // the Hive key itself), upserted with onConflict: 'id'. Scoped to the
      // method body specifically — `_deterministicId` legitimately still
      // exists elsewhere in this concatenated source for OTHER concepts
      // (streaks, coach, nutrition), so a whole-file `contains` check would
      // pass regardless of what this method actually does.
      final start = syncSvcSrc.indexOf('Future<void> _syncWorkoutTemplates(');
      expect(start, greaterThan(-1),
          reason: '_syncWorkoutTemplates must exist');
      final nextMethod = syncSvcSrc.indexOf('\n  Future<', start + 1);
      final body = nextMethod > start
          ? syncSvcSrc.substring(start, nextMethod)
          : syncSvcSrc.substring(start);
      expect(body.contains('cloudIdFromKey'), isTrue,
          reason: '_syncWorkoutTemplates must derive the cloud id from the '
              'client-minted key via cloudIdFromKey, not re-derive one');
      expect(body.contains('_deterministicId'), isFalse,
          reason: 'the old name-derived deterministic-UUID scheme must not '
              'reappear in this method — it is the exact shape that let a '
              'delete and its same-named replacement collide on one id');
      expect(body.contains("onConflict: 'id'"), isTrue,
          reason: 'the upsert must target the id directly, not '
              "onConflict: 'user_id,name' (the old name-based lookup)");
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
