// Tech-debt audit 2026-05-20 finding A10 — behavioral contract for
// CoachMemoryService.
//
// Pre-A10 the identity-signal detection + coaching-notes extraction +
// coach_memory backfill all lived inside AiCoachRepository alongside
// the snapshot builder + chat persistence — one 2127-line class. This
// test pins behaviour of the extracted CoachMemoryService.
//
// Run: flutter test test/contracts/coach_memory_service_only_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/models/coach_memory.dart';
import 'package:icanbefitter/features/ai_coach/services/coach_memory_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp =
        Directory.systemTemp.createTempSync('coach_memory_service_').path;
    PathProviderPlatform.instance = _FakePathProvider(tmp);
    Hive.init(tmp);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
  });

  setUp(() async {
    await HiveUserSession.closeAll();
    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.userBox.clear();
    await HiveService.instance.userBox.put('user_id', fakeUserId);
  });

  group('CoachMemoryService — behavioral contract', () {
    test('detectAndPersistIdentitySignals is a no-op on a neutral message',
        () async {
      // A message with no preferred-name signal and no obvious language
      // streak must NOT mint a coach_memory blob.
      await CoachMemoryService.instance
          .detectAndPersistIdentitySignals('what is the time');

      final mem = CoachMemory.readFromBox(HiveService.instance.coachBox);
      expect(mem, isNull,
          reason: 'no signals → no coach_memory write');
    });

    test('extractAndAppendCoachingNotes appends facts from today\'s messages',
        () async {
      final todayIso = DateTime.now().toIso8601String();
      // Seed two messages today — one that triggers the diet heuristic,
      // one that triggers the discomfort heuristic.
      await HiveService.instance.coachBox.put('coach_x', {
        'id': 'coach_x',
        'user_message': 'My knee hurts after squats',
        'ai_response': '',
        'created_at': todayIso,
      });
      await HiveService.instance.coachBox.put('coach_y', {
        'id': 'coach_y',
        'user_message': 'I want to eat more protein',
        'ai_response': '',
        'created_at': todayIso,
      });

      await CoachMemoryService.instance.extractAndAppendCoachingNotes();

      final notes = HiveService.instance.coachBox.get('coaching_notes');
      expect(notes, isA<Map>());
      final notesList = (notes as Map)['notes'] as List;
      expect(notesList, isNotEmpty);
      // At least one of the two heuristics fired.
      final joined = notesList.join(' | ').toLowerCase();
      expect(
        joined.contains('discomfort') ||
            joined.contains('goal update') ||
            joined.contains('diet note'),
        isTrue,
        reason: 'extractor must surface one of the canonical fact types',
      );
    });

    test('extractAndAppendCoachingNotes is a no-op on empty box', () async {
      await CoachMemoryService.instance.extractAndAppendCoachingNotes();
      // No write — the singleton key should not be present.
      expect(HiveService.instance.coachBox.get('coaching_notes'), isNull);
    });

    test('backfillCoachMemoryIfNeeded is idempotent — no-op if coach_memory exists',
        () async {
      // Pre-seed a CoachMemory so the backfill must short-circuit.
      final seeded = CoachMemory(
        userId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        coachNotes: 'pre-existing',
        updatedAt: DateTime.now(),
      );
      await seeded.writeToBox(HiveService.instance.coachBox);

      // Also seed a legacy coaching_notes payload that the backfill would
      // otherwise merge — but it must not, because coach_memory already
      // exists.
      await HiveService.instance.coachBox.put('coaching_notes', {
        'notes': ['legacy 1', 'legacy 2'],
      });

      await CoachMemoryService.instance.backfillCoachMemoryIfNeeded();

      final mem = CoachMemory.readFromBox(HiveService.instance.coachBox);
      expect(mem, isNotNull);
      expect(mem!.coachNotes, 'pre-existing',
          reason: 'backfill must not overwrite an existing CoachMemory');
    });
  });
}
