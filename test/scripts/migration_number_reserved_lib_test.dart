// test/scripts/migration_number_reserved_lib_test.dart
//
// PURE tests for scripts/migration_number_reserved_lib.dart (OI-263). The e2e counterpart
// (check_migration_number_reserved_e2e_test.dart) proves the gate binary calls this and reads git
// correctly; this file proves the rules.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/migration_number_reserved_lib.dart';

ReservationVerdict _eval(
  List<String> added, {
  Set<String> main = const {'001_a.sql', '002_b.sql', '003_c.sql'},
  Set<String> ledger = const {'001', '002', '003'},
  Set<int>? reserved = const {},
}) =>
    evaluateReservations(
      addedPaths: added,
      originMainNames: main,
      ledgerIdsOnOriginMain: ledger,
      reserved: reserved,
    );

void main() {
  group('allocatedMigrationPath — the FULL-path allocation grammar', () {
    test('accepts a top-level NNN_ and NNNx_ file', () {
      expect(allocatedMigrationPath.hasMatch('supabase/migrations/152_x.sql'), isTrue);
      expect(allocatedMigrationPath.hasMatch('supabase/migrations/050b_x.sql'), isTrue);
    });
    test('rejects the 041_chunks/ subdirectory (a basename-only parser reads it as migration 041)', () {
      expect(allocatedMigrationPath.hasMatch('supabase/migrations/041_chunks/041_01_rows.sql'), isFalse);
    });
    test('rejects timestamp-scheme files, wrong dirs, wrong extensions and 2/4-digit prefixes', () {
      for (final p in [
        'supabase/migrations/20260328000001_video_renders.sql',
        'supabase/migrations/20260330_create_promo_codes.sql',
        'other/152_x.sql',
        'supabase/migrations/152_x.md',
        'supabase/migrations/15_x.sql',
        'supabase/migrations/1520_x.sql',
        'supabase/migrations/152x.sql',
      ]) {
        expect(allocatedMigrationPath.hasMatch(p), isFalse, reason: p);
      }
    });
  });

  group('allocatedToken', () {
    test('returns the text before the first underscore', () {
      expect(allocatedToken('152_x_y.sql'), '152');
      expect(allocatedToken('050b_x.sql'), '050b');
    });
    test('null for anything outside the grammar', () {
      expect(allocatedToken('20260328000001_x.sql'), isNull);
      expect(allocatedToken('CLAUDE.md'), isNull);
      expect(allocatedToken('all_migrations_combined.sql'), isNull);
    });
  });

  group('reservationNumbers', () {
    test('parses for-each-ref and ls-remote lines; ignores leading zeros and junk', () {
      const out = 'refs/remotes/origin/mig/152\n'
          'abc123\trefs/heads/mig/9\n'
          'refs/remotes/origin/mig/007\n'
          'refs/remotes/origin/mig/x\n'
          'refs/remotes/origin/mig/4x\n'
          'refs/remotes/origin/oi/40\n'
          'refs/remotes/origin/main\n';
      expect(reservationNumbers(out), {152, 9});
    });
  });

  group('evaluateReservations', () {
    test('a new file whose number is reserved passes', () {
      final v = _eval(['supabase/migrations/004_new.sql'], reserved: {4});
      expect(v.violations, isEmpty);
      expect(v.notes, isEmpty);
    });

    test('a new file with NO reservation FAILS and says how to fix it', () {
      final v = _eval(['supabase/migrations/004_new.sql'], reserved: {5});
      expect(v.violations, hasLength(1));
      expect(v.violations.single, contains('mig/4'));
      expect(v.violations.single, contains('mint_migration.sh'));
    });

    test('a file already on origin/main is PUBLISHED and skipped (merge of main into a branch)', () {
      final v = _eval(['supabase/migrations/002_b.sql'], reserved: {});
      expect(v.violations, isEmpty);
    });

    test('same number as a DIFFERENT file on origin/main FAILS even when reserved', () {
      final v = _eval(['supabase/migrations/002_other.sql'], reserved: {2});
      expect(v.violations, hasLength(1));
      expect(v.violations.single, contains('002_b.sql'));
      expect(v.violations.single, contains('already taken'));
    });

    test('145/146 are grandfathered for the collision check (four applied, immutable files)', () {
      final v = _eval(
        ['supabase/migrations/145_alert_sql_job_failures.sql'],
        main: {'145_workout_templates_stable_delete.sql'},
        reserved: {145},
      );
      expect(v.violations, isEmpty);
    });

    test('unknown reservations (offline) => a NOTE and NO violation — skipped, never "passed"', () {
      final v = _eval(['supabase/migrations/004_new.sql'], reserved: null);
      expect(v.violations, isEmpty);
      expect(v.notes.single, contains('SKIPPED'));
    });

    test('out-of-scope files are ignored entirely: chunk dir, timestamp scheme, non-migrations', () {
      final v = _eval([
        'supabase/migrations/041_chunks/041_09_more.sql',
        'supabase/migrations/20261001000001_x.sql',
        'docs/notes.md',
      ], reserved: {});
      expect(v.violations, isEmpty);
    });

    group('letter-suffix follow-ups (050b, 068b precedents)', () {
      test('base published on origin/main => passes without any mig/ reservation for the suffix', () {
        final v = _eval(['supabase/migrations/002b_followup.sql'], reserved: {});
        expect(v.violations, isEmpty);
      });
      test('base known only from origin/main FILES (ledger has no entry for it) => passes (B-pass B7d)', () {
        final v = _eval(['supabase/migrations/002b_followup.sql'], main: {'002_b.sql'}, ledger: <String>{}, reserved: {});
        expect(v.violations, isEmpty);
      });
      test('base known only from the ledger => passes', () {
        final v = _eval(['supabase/migrations/120b_followup.sql'],
            main: {'001_a.sql'}, ledger: {'120'}, reserved: {});
        expect(v.violations, isEmpty);
      });
      test('base reserved but not yet published => passes', () {
        final v = _eval(['supabase/migrations/090b_followup.sql'], reserved: {90});
        expect(v.violations, isEmpty);
      });
      test('base neither published nor reserved => FAILS', () {
        final v = _eval(['supabase/migrations/090b_followup.sql'], reserved: {});
        expect(v.violations, hasLength(1));
        expect(v.violations.single, contains('090'));
      });
      test('two branches both adding the SAME suffix token: a different file already on main FAILS', () {
        final v = _eval(['supabase/migrations/002b_mine.sql'],
            main: {'002_b.sql', '002b_theirs.sql'}, reserved: {2});
        expect(v.violations, hasLength(1));
        expect(v.violations.single, contains('002b_theirs.sql'));
      });
      test('base unknown and reservations unreadable => NOTE, not a pass and not a fail', () {
        final v = _eval(['supabase/migrations/090b_followup.sql'], reserved: null);
        expect(v.violations, isEmpty);
        expect(v.notes, hasLength(1));
      });
    });

    test('several files are each judged independently', () {
      final v = _eval([
        'supabase/migrations/004_ok.sql',
        'supabase/migrations/005_missing.sql',
      ], reserved: {4});
      expect(v.violations, hasLength(1));
      expect(v.violations.single, contains('005_missing.sql'));
    });
  });
}
