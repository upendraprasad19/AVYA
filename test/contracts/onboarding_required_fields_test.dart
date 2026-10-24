// Source-grep contract for the onboarding-required-fields Postgres backstop.
//
// OI-46 (2026-07-29) — the 9 onboarding-critical user_profile fields were
// only enforced by OnboardingNotifier's client-side route sequence, with no
// Postgres backstop: a corrupted local Hive state (or a future client bug)
// could sync onboarding_completed_at without the fields ever reaching the
// server. Fixed with a state-TRANSITION trigger (migration 112) — fires
// only on the NULL -> non-NULL transition of onboarding_completed_at, not
// on every subsequent update, so legitimate partial-upsert syncs of an
// already-completed profile are unaffected. See sync_profile.dart's
// conditional-field-inclusion upsert (SyncService._hasValue guards) for why
// a blanket NOT NULL would have been wrong here. Behavioral proof of the
// transition-only semantics lives in
// test/sql/oi46_daily_cap_triggers_live_verify.sql (cases 4-6).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('OI-46 onboarding required-fields transition gate', () {
    test('migration 112 (onboarding_required_fields_transition_gate) exists', () {
      expect(
        File('supabase/migrations/112_onboarding_required_fields_transition_gate.sql')
            .existsSync(),
        isTrue,
      );
    });

    test('trigger is a transition gate, not a blanket NOT NULL', () {
      final src = _src(
          'supabase/migrations/112_onboarding_required_fields_transition_gate.sql');
      expect(src.contains('BEFORE INSERT OR UPDATE ON user_profile'), isTrue);
      expect(
        src.contains("TG_OP = 'UPDATE' AND OLD.onboarding_completed_at IS NOT NULL"),
        isTrue,
        reason: 'must short-circuit on already-completed rows so later '
            'unrelated-field edits are never re-validated.',
      );
      for (final field in [
        'date_of_birth',
        'gender',
        'height_cm',
        'current_weight_kg',
        'target_weight_kg',
        'primary_goal',
        'fitness_experience',
        'days_per_week',
        'equipment_access',
      ]) {
        expect(src.contains('NEW.$field IS NULL'), isTrue,
            reason: 'trigger must validate $field on the completion transition.');
      }
      expect(src.contains("USING ERRCODE = 'P0001'"), isTrue);
    });
  });
}
