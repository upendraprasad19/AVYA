// Regression contract for c7d4f1 (community-review RLS-context, 2026-06-13 Unit 2).
//
// The COMMUNITY REVIEW queue was ALWAYS empty: the two readers did a cross-user read
// of user_custom_foods / user_custom_exercises (`.neq('user_id', me)`), which own-only
// SELECT RLS (auth.uid()=user_id) blocks → 0 rows → "No items to review", and the
// community-vote → auto-promotion pipeline was inert. Fix: a scoped service-role Edge
// Function `get-community-review-items` (anonymized projection, BYPASSRLS) that the two
// readers route through; tighten community_reviews SELECT world-read → own-only
// (migration 092); delete the dead community_review_sheet.dart; telemeter both _load
// catches (the new failure mode can be non-2xx).
//
// Source-grep (the EF runs in Deno; the client FunctionException flow is integration-heavy),
// comment-stripped so the bug-describing comments cannot satisfy the assertions.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  final ef = _strip(File('supabase/functions/get-community-review-items/index.ts')
      .readAsStringSync());
  final repo = _strip(
      File('lib/shared/repositories/submissions_repository.dart')
          .readAsStringSync());
  final migration = _strip(
      File('supabase/migrations/092_community_reviews_select_own_only.sql')
          .readAsStringSync());
  final screen = _strip(
      File('lib/features/profile/screens/submissions_screen.dart')
          .readAsStringSync());

  group('c7d4f1 — get-community-review-items EF is a pure service-role reader', () {
    test('does NOT bake the user JWT into global.headers (the RLS-context bug)', () {
      expect(
        RegExp(r'global\s*:\s*\{\s*headers\s*:\s*\{\s*Authorization').hasMatch(ef),
        isFalse,
        reason: 'a user JWT in global.headers would make PostgREST run as '
            '`authenticated` → own-only RLS would block the cross-user read. '
            'Must be a pure service-role client.',
      );
    });

    test('builds a pure service-role client and authenticates via getUser(token)', () {
      expect(ef.contains('createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)'),
          isTrue,
          reason: 'pure service-role client (BYPASSRLS) — no global headers');
      expect(ef.contains('getUser(token)'), isTrue,
          reason: 'authenticate the caller via getUser(token); derive caller id '
              'from the verified JWT, never from a client-supplied id');
    });

    test('filters .neq("user_id", caller) server-side on BOTH tables', () {
      expect(RegExp(r'\.neq\("user_id"').allMatches(ef).length,
          greaterThanOrEqualTo(2),
          reason: 'exclude the caller\'s own submissions on food AND exercise');
    });

    test('anonymizes: NO select() projection includes user_id', () {
      final selects = RegExp(r'\.select\(\s*"([^"]*)"', dotAll: true)
          .allMatches(ef)
          .map((m) => m.group(1)!)
          .toList();
      expect(selects.length, greaterThanOrEqualTo(2),
          reason: 'one select per kind (food + exercise)');
      for (final s in selects) {
        expect(s.contains('user_id'), isFalse,
            reason: 'submitter user_id must be stripped from the response '
                '(the UI never renders it); the .neq filter on user_id is '
                'separate from the projection. Offending select: "$s"');
      }
    });
  });

  group('c7d4f1 — the client reads route through the EF (no direct cross-user read)', () {
    test('both pending-review readers call callFunction(get-community-review-items)', () {
      expect(
        RegExp(r"callFunction\(\s*'get-community-review-items'")
            .allMatches(repo)
            .length,
        greaterThanOrEqualTo(2),
        reason: 'fetchPendingFoodReviews + fetchPendingExerciseReviews both route '
            'through callFunction (fresh-token + service-role EF)',
      );
    });

    test('no client-side cross-user .neq(user_id) read remains', () {
      expect(repo.contains(".neq('user_id'"), isFalse,
          reason: 'the cross-user pending-review read moved server-side into the '
              'EF; a client .neq(user_id) on user_custom_* is RLS-blocked (own-only)');
    });
  });

  group('c7d4f1 — migration 092 tightens community_reviews SELECT to own-only', () {
    test('drops the world-read SELECT policy by its exact name', () {
      expect(
        migration.contains('DROP POLICY IF EXISTS "Users can read all reviews"'),
        isTrue,
        reason: 'the live policy name is "Users can read all reviews" (qual=true); '
            'a wrong name makes the DROP a silent no-op',
      );
    });

    test('creates an own-only SELECT policy (auth.uid() = reviewer_id)', () {
      expect(migration.contains('FOR SELECT'), isTrue);
      expect(RegExp(r'auth\.uid\(\)\s*=\s*reviewer_id').hasMatch(migration), isTrue,
          reason: 'own-only read closes the vote-graph de-anonymization');
    });
  });

  group('c7d4f1 — dead code removed + telemetry wired', () {
    test('the dead community_review_sheet.dart is deleted', () {
      expect(File('lib/shared/widgets/community_review_sheet.dart').existsSync(),
          isFalse,
          reason: 'the unused, RLS-broken, rule-#4-violating bottom sheet was a '
              'latent reintroduction trap — removed');
    });

    test('submissions_screen telemeters both _load catches (no silent drop)', () {
      expect(screen.contains('error_telemetry'), isTrue,
          reason: 'import the telemetry helper');
      expect(RegExp(r'recordNonFatal').allMatches(screen).length,
          greaterThanOrEqualTo(3),
          reason: '_CommunityReviewBody._load, _MySubmissionsBody._load AND '
              '_vote catches must recordNonFatal — the EF/insert can fail '
              'non-2xx (incl. a duplicate-vote 23505), and a catch (_) would be '
              'a server-silent drop');
    });
  });
}
