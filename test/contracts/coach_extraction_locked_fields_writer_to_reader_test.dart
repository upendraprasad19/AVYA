// coach_extraction_locked_fields (a2b-2, single-owner batch, 2026-09-27)
//
// Two writers to the same three user_profile fields (Edit Profile / onboarding
// injuries vs. daily-snapshot's coach-extraction) get an explicit lock so the
// AI-coach pass can no longer silently overwrite a manual edit — see
// docs/sot_registry.yaml `coach_extraction_locked_fields` for the full design
// rationale and migration 148 for the SQL.
//
// SOURCE-STRUCTURE pins (client wiring — no Supabase client mock exists in
// this suite, confirmed by grep; matches the established pattern for this
// class, e.g. test/contracts/cross_device_progress_optimistic_lock_wiring_test.dart).
// The genuine BEHAVIORAL coverage of the actual lock/skip/conflict-marker
// LOGIC lives in supabase/functions/daily-snapshot/index_test.ts (6 Deno
// tests exercising mergeCoachingNotes directly against a fake-but-realistic
// Postgres-shaped client) + test/profile/edit_profile_coach_extraction_lock_test.dart
// (the pure computeCoachExtractionFieldsToLock helper) + test/ai_coach/coach_memory_model_test.dart
// (the CoachMemory.lockedFieldConflicts round-trip) — this file's job is
// only to pin that those pieces stay WIRED TOGETHER.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('coach_extraction_locked_fields — migration', () {
    final migration = _read(
      'supabase/migrations/148_coach_extraction_locked_fields.sql',
    );

    test('adds the additive-only lock column on user_profile', () {
      expect(
        migration,
        contains(
          'ADD COLUMN IF NOT EXISTS coach_extraction_locked_fields text[] NOT NULL DEFAULT \'{}\'',
        ),
      );
    });

    test('adds the conflict-marker column on coach_memory', () {
      expect(
        migration,
        contains(
          'ADD COLUMN IF NOT EXISTS locked_field_conflicts jsonb NOT NULL DEFAULT \'{}\'::jsonb',
        ),
      );
    });

    test('the RPC is additive-only (UNION over the existing array), never a plain overwrite', () {
      expect(migration, contains('CREATE OR REPLACE FUNCTION public.lock_coach_extraction_fields'));
      expect(
        migration,
        contains('coach_extraction_locked_fields || v_filtered'),
        reason: 'must union onto the EXISTING array, not replace it — a '
            'plain assignment would let one call site silently unlock a '
            'field a different call site had already locked',
      );
    });

    test('SECURITY INVOKER, not DEFINER — the caller\'s own RLS must apply', () {
      final fnIdx = migration.indexOf('CREATE OR REPLACE FUNCTION public.lock_coach_extraction_fields');
      final grantIdx = migration.indexOf('GRANT EXECUTE ON FUNCTION public.lock_coach_extraction_fields');
      final fnBlock = migration.substring(fnIdx, grantIdx);
      expect(fnBlock, contains('SECURITY INVOKER'));
      expect(fnBlock, isNot(contains('SECURITY DEFINER')));
    });

    test('both REVOKE forms are present (Supabase default-privileges trap — see supabase/migrations/CLAUDE.md)', () {
      expect(
        migration,
        contains('REVOKE ALL ON FUNCTION public.lock_coach_extraction_fields(text[]) FROM PUBLIC'),
      );
      expect(
        migration,
        contains('REVOKE EXECUTE ON FUNCTION public.lock_coach_extraction_fields(text[]) FROM anon'),
      );
      expect(
        migration,
        contains('GRANT EXECUTE ON FUNCTION public.lock_coach_extraction_fields(text[]) TO authenticated'),
      );
    });

    test('there is no unlock RPC (deliberate — locking is additive-only by design)', () {
      expect(migration, isNot(contains('unlock_coach_extraction_fields')));
    });

    test('P0 backfill: every EXISTING row is locked on ALL THREE fields at migration-apply time', () {
      expect(
        migration,
        contains(
          "SET coach_extraction_locked_fields = ARRAY['diet_preference', 'lifestyle_activity', 'injuries'];",
        ),
        reason: 'without this backfill, every existing user reads as '
            'unlocked the instant this column exists — the very next '
            'nightly extraction run would silently overwrite any '
            "pre-existing user's genuine diet_preference/lifestyle_activity/"
            'injuries, which is exactly the bug this feature exists to '
            'prevent',
      );
      // The backfill must run BEFORE the RPC is defined (order doesn't
      // strictly matter to Postgres here, but confirms it's not accidentally
      // gated behind something that could skip it).
      final backfillIdx = migration.indexOf('SET coach_extraction_locked_fields = ARRAY');
      final columnIdx = migration.indexOf('ADD COLUMN IF NOT EXISTS coach_extraction_locked_fields');
      expect(columnIdx, greaterThan(-1));
      expect(backfillIdx, greaterThan(columnIdx));
    });

    test('the RPC raises loudly on a missing user_profile row, rather than silently no-op-ing', () {
      expect(migration, contains('RAISE EXCEPTION'));
      expect(migration, contains('IF NOT FOUND THEN'));
      expect(
        migration,
        isNot(contains('INSERT INTO public.user_profile')),
        reason: 'a fallback INSERT here would mask exactly the "called '
            'before the profile row exists" bug class the RAISE is meant '
            'to surface immediately',
      );
    });
  });

  group('coach_extraction_locked_fields — client wiring', () {
    final userRepo = _read('lib/shared/repositories/user_repository.dart');
    final editProfile = _read('lib/features/profile/screens/edit_profile_screen.dart');

    test('UserRepository.lockCoachExtractionFields calls the RPC by name', () {
      expect(userRepo, contains('static Future<void> lockCoachExtractionFields'));
      expect(userRepo, contains("supabase.rpc('lock_coach_extraction_fields'"));
    });

    test('syncOnboardingToSupabase gates the lock call on shouldLockOnboardingInjuries, positioned AFTER the user_profile upsert', () {
      final idx = userRepo.indexOf('static Future<void> syncOnboardingToSupabase');
      final endIdx = userRepo.indexOf(
        'static bool shouldLockOnboardingInjuries',
      );
      final body = userRepo.substring(idx, endIdx);
      expect(body, contains('shouldLockOnboardingInjuries('));
      expect(body, contains("lockCoachExtractionFields(['injuries'])"));
      // Must run AFTER the user_profile upsert (the injuries value being
      // checked comes from the same payload just written).
      final upsertPos = body.indexOf("supabase.from('user_profile').upsert(");
      final lockPos = body.indexOf("lockCoachExtractionFields(['injuries'])");
      expect(upsertPos, greaterThan(-1));
      expect(lockPos, greaterThan(upsertPos));
    });

    test('shouldLockOnboardingInjuries uses listEquals, never a bare != on lists (the reference-equality class)', () {
      final idx = userRepo.indexOf('static bool shouldLockOnboardingInjuries');
      final body = userRepo.substring(idx, idx + 200);
      expect(
        body,
        contains('listEquals('),
        reason: 'List does not override == in Dart — a bare != between two '
            'list literals is reference inequality, always true, which '
            'would lock injuries for 100% of new signups regardless of '
            'whether a real answer was given',
      );
      expect(body, contains("const ['none']"));
    });

    test('syncOnboardingToSupabase strips coach_extraction_locked_fields from the blind-spread profileData payload before upserting', () {
      final idx = userRepo.indexOf('static Future<void> syncOnboardingToSupabase');
      final endIdx = userRepo.indexOf(
        'static Future<void> lockCoachExtractionFields',
      );
      final body = userRepo.substring(idx, endIdx);
      expect(body, contains("remove('coach_extraction_locked_fields')"));
    });

    test('edit_profile_screen._save wires computeCoachExtractionFieldsToLock into the lock RPC call', () {
      expect(editProfile, contains('List<String> computeCoachExtractionFieldsToLock('));
      expect(editProfile, contains('final fieldsToLock = computeCoachExtractionFieldsToLock('));
      expect(
        editProfile,
        contains('unawaited(UserRepository.lockCoachExtractionFields(fieldsToLock))'),
      );
    });

    test('computeCoachExtractionFieldsToLock only names the 3 known lockable fields', () {
      final idx = editProfile.indexOf('List<String> computeCoachExtractionFieldsToLock(');
      final endIdx = editProfile.indexOf('}\n\n/// Pure helper extracted', idx);
      final body = editProfile.substring(idx, endIdx == -1 ? idx + 800 : endIdx);
      expect(body, contains("'diet_preference'"));
      expect(body, contains("'lifestyle_activity'"));
      expect(body, contains("'injuries'"));
    });
  });

  group('coach_extraction_locked_fields — server-side guard + conflict marker', () {
    final dailySnapshot = _read('supabase/functions/daily-snapshot/index.ts');
    final coachMemoryShared = _read('supabase/functions/_shared/coach_memory.ts');

    test('mergeCoachingNotes selects the lock list before deciding what to write', () {
      final idx = dailySnapshot.indexOf('export async function mergeCoachingNotes');
      final endIdx = dailySnapshot.indexOf(
        'function valuesEqualForLockCheck',
      );
      final body = dailySnapshot.substring(idx, endIdx);
      expect(body, contains('coach_extraction_locked_fields'));
      expect(body, contains('lockedFields.has(field)'));
    });

    test('a locked field with a genuine conflict writes to coach_memory.locked_field_conflicts, MERGED over any existing value', () {
      final idx = dailySnapshot.indexOf('export async function mergeCoachingNotes');
      final endIdx = dailySnapshot.indexOf('function valuesEqualForLockCheck');
      final body = dailySnapshot.substring(idx, endIdx);
      expect(body, contains('locked_field_conflicts: { ...existingConflicts, ...conflicts }'));
      expect(
        body,
        isNot(contains('locked_field_conflicts: conflicts }')),
        reason: 'a bare replace (not a spread-merge) would silently erase a '
            'prior conflict recorded for a DIFFERENT field',
      );
    });

    test('injuries array comparison sorts copies rather than comparing by reference (cross-language reference-equality class)', () {
      expect(dailySnapshot, contains('function valuesEqualForLockCheck'));
      expect(dailySnapshot, contains('[...a].sort()'));
      expect(dailySnapshot, contains('[...b].sort()'));
    });

    test('the CoachMemory TS interface declares locked_field_conflicts', () {
      expect(coachMemoryShared, contains('locked_field_conflicts: Record<string, unknown>;'));
    });
  });

  group('coach_extraction_locked_fields — reaches the AI prompt', () {
    test('CoachMemory.toJson (Dart) carries lockedFieldConflicts under the cloud column name', () {
      final model = _read('lib/features/ai_coach/models/coach_memory.dart');
      expect(model, contains('locked_field_conflicts'));
      expect(model, contains('lockedFieldConflicts'));
    });

    test('_getCoachMemoryForContext passes the WHOLE CoachMemory object (toJson()) into the AI snapshot, not a hand-picked field subset', () {
      final builder = _read('lib/features/ai_coach/services/ai_snapshot_builder.dart');
      final idx = builder.indexOf('Map<String, dynamic>? _getCoachMemoryForContext()');
      expect(idx, greaterThan(-1));
      final body = builder.substring(idx, idx + 400);
      expect(
        body,
        contains('return mem.toJson();'),
        reason: 'a hand-picked field list here would silently strand any '
            'FUTURE CoachMemory field (including this one) from the AI '
            'context without a code change on this side',
      );
    });
  });
}
