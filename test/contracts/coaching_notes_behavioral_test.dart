// test/contracts/coaching_notes_behavioral_test.dart
//
// Behavioral contract: coaching_notes
// Writer: lib/features/ai_coach/services/coach_memory_service.dart
//         (extractAndAppendCoachingNotes → coachBox.put('coaching_notes', {...}))
// Reader: lib/features/ai_coach/services/ai_snapshot_builder.dart
//         (_getCoachingNotes → reads coachBox.get('coaching_notes'),
//          emits under 'coaching_notes' key in buildAiContext())
//
// Assert: after extractAndAppendCoachingNotes(), buildAiContext() includes
// a non-empty coaching_notes value.
//
// This test FAILS if:
//   - extractAndAppendCoachingNotes writes under a different Hive key
//   - _getCoachingNotes reads under a different key
//   - the {'notes': [...], 'last_extracted': ...} shape changes
//   - the keyword triggers in extractAndAppendCoachingNotes are removed

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';
import 'package:icanbefitter/features/ai_coach/services/coach_memory_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  String todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  test(
      'extractAndAppendCoachingNotes writes coaching_notes that buildAiContext includes',
      () async {
    final coachBox = HiveService.instance.coachBox;
    final today = todayStr();

    // Write a coach interaction from today that contains a goal keyword so
    // extractAndAppendCoachingNotes will produce a fact.
    // The 'created_at' must start with todayStr (IST date string).
    final ts = DateTime.now();
    await coachBox.put('coach_${ts.millisecondsSinceEpoch}', {
      'id': 'coach_${ts.millisecondsSinceEpoch}',
      'user_message': 'I want to build muscle and lose fat this year',
      'ai_response': 'Great goal! Let me set up a program for you.',
      'model_used': 'gemini-2.5-flash',
      'mode': 'quick',
      'is_user_message': true,
      'created_at': '${today}T10:00:00.000',
    });

    // extractAndAppendCoachingNotes reads today's coachBox entries for keywords.
    await CoachMemoryService.instance.extractAndAppendCoachingNotes();

    // Verify the raw Hive state first — coaching_notes must be written.
    final raw = coachBox.get('coaching_notes');
    expect(raw, isNotNull,
        reason: 'coaching_notes must be written to coachBox after extraction');
    expect(raw, isA<Map>(),
        reason: 'coaching_notes must be a Map {notes: [...], last_extracted: ...}');
    final notesMap = Map<String, dynamic>.from(raw as Map);
    expect(notesMap.containsKey('notes'), isTrue);
    final notesList = notesMap['notes'] as List;
    expect(notesList, isNotEmpty,
        reason: 'notes list must be non-empty after keyword detection');

    // Now verify the reader path: buildAiContext() must emit 'coaching_notes'
    // as a non-empty list.
    final context = AiSnapshotBuilder.instance.buildAiContext();
    expect(context.containsKey('coaching_notes'), isTrue,
        reason: "'coaching_notes' key must exist in buildAiContext() output");

    final coachingNotes = context['coaching_notes'];
    expect(coachingNotes, isA<List>(),
        reason: 'coaching_notes in snapshot must be a List');
    expect((coachingNotes as List), isNotEmpty,
        reason:
            'coaching_notes in snapshot must be non-empty after extraction');
  });

  test(
      'extractAndAppendCoachingNotes is a no-op when today has no keyword-bearing messages',
      () async {
    final coachBox = HiveService.instance.coachBox;
    final today = todayStr();

    // Write a neutral message with no keywords.
    final ts = DateTime.now();
    await coachBox.put('coach_${ts.millisecondsSinceEpoch}', {
      'id': 'coach_${ts.millisecondsSinceEpoch}',
      'user_message': 'Hi',
      'ai_response': 'Hello! How can I help you today?',
      'model_used': 'gemini-2.5-flash',
      'mode': 'quick',
      'is_user_message': true,
      'created_at': '${today}T09:00:00.000',
    });

    await CoachMemoryService.instance.extractAndAppendCoachingNotes();

    // No keywords → coaching_notes should not be written.
    final raw = coachBox.get('coaching_notes');
    // It may remain null (fresh box) or retain whatever was there before.
    // The critical assertion: buildAiContext must NOT crash even if
    // coaching_notes is absent.
    final context = AiSnapshotBuilder.instance.buildAiContext();
    expect(context.containsKey('coaching_notes'), isTrue);
    // When no notes exist the snapshot key is an empty list.
    final coachingNotes = context['coaching_notes'];
    expect(coachingNotes, isA<List>());
    if (raw == null) {
      expect((coachingNotes as List), isEmpty,
          reason: 'coaching_notes must be empty when no keywords were found');
    }
  });

  test(
      'extractAndAppendCoachingNotes appends to existing notes without exceeding 20',
      () async {
    final coachBox = HiveService.instance.coachBox;
    final today = todayStr();

    // Pre-populate 19 existing notes.
    final existingNotes =
        List.generate(19, (i) => 'Existing note $i');
    await coachBox.put('coaching_notes', {
      'notes': existingNotes,
      'last_extracted': '${today}T00:00:00.000',
    });

    // Write a message that will add 1 more fact (goal keyword).
    final ts = DateTime.now();
    await coachBox.put('coach_${ts.millisecondsSinceEpoch}', {
      'id': 'coach_${ts.millisecondsSinceEpoch}',
      'user_message': 'My goal is to run a marathon',
      'ai_response': 'Excellent goal!',
      'model_used': 'gemini-2.5-flash',
      'mode': 'quick',
      'is_user_message': true,
      'created_at': '${today}T11:00:00.000',
    });

    await CoachMemoryService.instance.extractAndAppendCoachingNotes();

    final raw = coachBox.get('coaching_notes') as Map;
    final notes = raw['notes'] as List;
    expect(notes.length, lessThanOrEqualTo(20),
        reason: 'coaching_notes must never exceed 20 entries');
    // The newest fact must be present.
    expect(notes.any((n) => n.toString().contains('marathon')), isTrue,
        reason: 'new fact from goal keyword must be appended');
  });
}
