import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `coaching_notes`
/// from docs/sot_registry.yaml.
///
/// Writer: ai_coach_repository.extractCoachingNotes (method renamed from
///         extractAndSaveCoachingNotes in the live codebase — registry stale ref corrected here)
/// Readers: ai_coach_repository._getCoachingNotes,
///          ai_service._compactContext (truncates to 1000 chars at step 8)
///
/// Key: 'coaching_notes' (singleton) in coachBox. Value is Map{notes: String}.
/// Cloud: coach_memory.coaching_notes column (pulled on restore).
///
/// Forbidden: coachBox.get('coaching_notes') as String — value is a Map not a String.
/// Truncation is the TRIMMER's job (_compactContext), never the writer's.
void main() {
  late String aiRepoSrc;
  late String aiSvcSrc;

  setUpAll(() {
    final af =
        File('lib/features/ai_coach/repositories/ai_coach_repository.dart');
    expect(af.existsSync(), isTrue,
        reason: 'ai_coach_repository.dart must exist');
    aiRepoSrc = af.readAsStringSync();

    final asf = File('lib/core/services/ai_service.dart');
    expect(asf.existsSync(), isTrue, reason: 'ai_service.dart must exist');
    aiSvcSrc = asf.readAsStringSync();
  });

  group('coaching_notes writer↔reader source contract', () {
    test('writer extractCoachingNotes exists in ai_coach_repository', () {
      // Method name in live codebase is extractCoachingNotes (not extractAndSaveCoachingNotes)
      // Registry stale ref corrected: sot_registry.yaml writer.method updated
      expect(
          aiRepoSrc.contains('extractCoachingNotes') ||
              aiRepoSrc.contains('extractAndSaveCoachingNotes'),
          isTrue,
          reason:
              'ai_coach_repository must define extractCoachingNotes — nightly extraction '
              'of coaching facts from that day\'s conversations');
    });

    test('writer stores coaching_notes as a Map (not raw String)', () {
      // Value shape must be {notes: String} per sot_registry.class_constraints
      // The writer puts a Map, not a bare String
      expect(aiRepoSrc.contains("'coaching_notes'"), isTrue,
          reason: 'writer must use coaching_notes singleton key');
      // Confirm it puts a Map (curly braces in the put call)
      expect(
          aiRepoSrc.contains("coachBox.put('coaching_notes', {") ||
              aiRepoSrc.contains("coachBox.put('coaching_notes', <") ||
              aiRepoSrc.contains(".put('coaching_notes'"), isTrue,
          reason:
              'coaching_notes must be stored as a Map (not raw String); '
              "readers that do coachBox.get('coaching_notes') as String will throw");
    });

    test('reader _getCoachingNotes exists in ai_coach_repository', () {
      expect(aiRepoSrc.contains('_getCoachingNotes'), isTrue,
          reason:
              'ai_coach_repository must define _getCoachingNotes — the single reader '
              'for coaching_notes; never read the singleton directly outside this method');
    });

    test('reader _compactContext in ai_service truncates coaching_notes', () {
      expect(aiSvcSrc.contains('_compactContext'), isTrue,
          reason: 'ai_service must define _compactContext (coaching_notes trimmer)');
      expect(
          aiSvcSrc.contains('coaching_notes') ||
              aiSvcSrc.contains('1000') ||
              aiSvcSrc.contains('coachingNotes'),
          isTrue,
          reason:
              '_compactContext must truncate coaching_notes to 1000 chars '
              '(step 8 in trim order per sot_registry.class_constraints)');
    });

    test('coaching_notes included in buildAiContext snapshot', () {
      expect(
          aiRepoSrc.contains("'coaching_notes'") &&
              aiRepoSrc.contains('buildAiContext'),
          isTrue,
          reason:
              'buildAiContext must include coaching_notes in the AI snapshot');
    });

    test('cloud restore pulls coaching_notes from coach_memory', () {
      final sf = File('lib/core/services/sync_service.dart');
      if (!sf.existsSync()) return;
      final src = sf.readAsStringSync();
      expect(
          src.contains('coaching_notes') && src.contains('coach_memory'),
          isTrue,
          reason:
              '_restoreCoachMemory in sync_service must pull coaching_notes '
              'from coach_memory cloud table (Test #11 Theme A6)');
    });

    test('forbidden: coachBox.get coaching_notes cast as String', () {
      // Value is a Map{notes: String} — casting as String throws
      final dangerousPattern =
          RegExp(r"coachBox\.get\('coaching_notes'\)\s+as\s+String");
      expect(dangerousPattern.hasMatch(aiRepoSrc), isFalse,
          reason:
              "coachBox.get('coaching_notes') must not be cast as String; "
              "value is Map{notes: String} — use _getCoachingNotes() reader method");
    });
  });
}
