// test/scripts/check_hive_first_pattern_lib_test.dart
//
// Unit tests for the pure predicate behind scripts/check_hive_first_pattern.dart
// (Fitness App's Rule-2 equivalent). Mutation-proven (rule 24).

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/check_hive_first_pattern.dart';

void main() {
  group('isAllowedPath', () {
    test('allows lib/core/services/', () {
      expect(isAllowedPath('lib/core/services/sync/sync_workout.dart'), isTrue);
    });

    test('allows lib/shared/repositories/', () {
      expect(isAllowedPath('lib/shared/repositories/user_repository.dart'), isTrue);
    });

    test('allows lib/features/<any-feature>/repositories/', () {
      expect(
        isAllowedPath('lib/features/train/repositories/workout_repository.dart'),
        isTrue,
      );
      expect(
        isAllowedPath('lib/features/profile/repositories/referral_repository.dart'),
        isTrue,
      );
    });

    test('rejects a widget file', () {
      expect(
        isAllowedPath('lib/features/home/widgets/weight_log_sheet.dart'),
        isFalse,
      );
    });

    test('rejects a screen file', () {
      expect(isAllowedPath('lib/features/profile/screens/profile/screen.dart'), isFalse);
    });

    test('rejects a provider file', () {
      expect(isAllowedPath('lib/features/train/providers/train_provider.dart'), isFalse);
    });

    // MIRROR CASE: a "services" dir that is NOT lib/core/services/ (a feature's
    // OWN services dir) is a distinct, narrower thing -- rule 4 names the
    // repository layer specifically, and a feature-local services/ file (e.g.
    // profile_write_service.dart) is a WriteService, not itself the repository
    // this gate is verifying against. Confirm the allowlist does not
    // accidentally widen to any "services" segment anywhere in the path.
    test('does NOT allow a feature-local services/ dir merely by name', () {
      expect(
        isAllowedPath('lib/features/profile/services/profile_write_service.dart'),
        isFalse,
      );
    });

    test('handles backslash-separated Windows paths', () {
      expect(
        isAllowedPath(r'lib\core\services\sync\sync_health.dart'),
        isTrue,
      );
    });
  });

  group('stripLineComments', () {
    test('removes a // line comment but keeps the line', () {
      final result = stripLineComments("supabase.from('x'); // old note");
      expect(result, "supabase.from('x'); ");
    });

    test('does not strip :// inside a URL', () {
      final result = stripLineComments("final url = 'https://example.com';");
      expect(result, contains('https://example.com'));
    });

    test('removes a single-line /* */ block', () {
      final result = stripLineComments('supabase.from(/* table */ "x")');
      expect(result, 'supabase.from( "x")');
    });

    test('preserves line count (newline-preserving)', () {
      final result = stripLineComments('a\n// comment\nb');
      expect(result.split('\n'), ['a', '', 'b']);
    });
  });

  group('findViolations', () {
    test('no violations when every direct call lives in an allowed dir', () {
      final files = {
        'lib/core/services/sync/sync_workout.dart':
            "await _supabase.client.from('workout_logs').upsert({});",
        'lib/shared/repositories/user_repository.dart':
            "await supabase.from('users').upsert({});",
      };
      expect(findViolations(files), isEmpty);
    });

    test('flags a direct call in a widget', () {
      final files = {
        'lib/features/home/widgets/weight_log_sheet.dart':
            "await supabase.from('weight_logs').insert({});",
      };
      final violations = findViolations(files);
      expect(violations, hasLength(1));
      expect(violations.first.file, 'lib/features/home/widgets/weight_log_sheet.dart');
      expect(violations.first.line, 1);
    });

    test('flags a direct .client.from( call in a provider', () {
      final files = {
        'lib/features/train/providers/train_provider.dart':
            "final row = await SupabaseService.instance.client.from('t').select();",
      };
      expect(findViolations(files), hasLength(1));
    });

    test('reports the correct 1-indexed line number for a multi-line file', () {
      final files = {
        'lib/features/home/widgets/x.dart': 'line one\nline two\n'
            "await supabase.from('t').select();\nline four",
      };
      final violations = findViolations(files);
      expect(violations.single.line, 3);
    });

    test('does not flag a commented-out example call', () {
      final files = {
        'lib/features/home/widgets/x.dart':
            "// example: supabase.from('t').select();",
      };
      expect(findViolations(files), isEmpty);
    });

    // MUTATION-PROOF TARGET: does the regex over-match a generic .from()
    // constructor (Map.from, List.from) that has NOTHING to do with Supabase?
    // This is the exact false-positive class the header's live-tree
    // verification found and ruled out for the real codebase -- confirm the
    // pure predicate agrees on a fabricated case too.
    test('does not flag Map.from() / List.from() -- generic Dart constructors', () {
      final files = {
        'lib/features/home/widgets/x.dart':
            "final m = Map<String, dynamic>.from(raw);\n"
            "final l = List<int>.from(other);",
      };
      expect(findViolations(files), isEmpty);
    });

    test('does not scan an allowed-path file even if it has a violation-shaped line', () {
      final files = {
        'lib/core/services/x.dart': "await supabase.from('t').select();",
      };
      expect(findViolations(files), isEmpty);
    });

    // REGRESSION (round-1 review, P2-5, 2026-09-23): a live grep of the real
    // codebase found `supa.from(` as a third real alias (rank_service.dart:
    // `await supa.from('rank_promotions').upsert(...)` -- a bare variable
    // named `supa`, verified via Read before writing this test, not guessed),
    // alongside `supabase.from(` and `client.from(`. The original regex only
    // covered 2 of 3 -- this pins the widened alias set against both the
    // real call site's shape (allowed, inside lib/core/services/) and a
    // fabricated violation (outside any allowed dir).
    test('flags a direct supa.from( call outside an allowed dir', () {
      final files = {
        'lib/features/home/widgets/x.dart':
            "final row = await supa.from('ranks').select();",
      };
      final violations = findViolations(files);
      expect(violations, hasLength(1));
      expect(violations.first.file, 'lib/features/home/widgets/x.dart');
    });

    test('does not flag supa.from( inside lib/core/services/ -- mirrors rank_service.dart', () {
      final files = {
        'lib/core/services/rank_service.dart':
            "await supa.from('rank_promotions').upsert(toInsert);",
      };
      expect(findViolations(files), isEmpty);
    });
  });
}
