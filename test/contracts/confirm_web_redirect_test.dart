import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression test for diagnose (this batch): the signup-confirmation email
/// link (`/confirm?token_hash=...`) 404/dead-ends on the web for anyone
/// without the app installed.
///
/// Root cause: the app uses Flutter's default HashUrlStrategy (no
/// `setUrlStrategy` anywhere — see `lib/features/admin/CLAUDE.md:114` for the
/// identical `/admin` precedent), so a bare path only resolves once Vercel
/// redirects it to the `/#/...` fragment GoRouter actually reads. `/admin`
/// has that redirect; `/confirm` — added by the 2026-09-16 email-confirm-ux
/// batch — never got one. Without it, Vercel's SPA catch-all `rewrites` rule
/// serves `index.html` with the bare path still in the URL bar, GoRouter's
/// hash strategy sees no fragment, falls back to `initialLocation`, and the
/// `token_hash` query param (which lives in `location.search`, not the hash)
/// is never read — `verifyOTP` never runs, the email is never confirmed.
///
/// This is a static-config fix (`vercel.json`) with no `flutter test`-level
/// way to exercise real Vercel redirect behavior — see the diagnose-doc's
/// `touched_layers_checked` tier 11 note. This test pins PRESENCE and SHAPE
/// of the config (parsed as real JSON, not string-contains) so the entry
/// cannot be silently dropped or malformed again; it cannot prove Vercel
/// actually honors it, which only a live deploy can (§4 multi-tier protocol
/// tier 11 — verify via a live GET after deploy).
void main() {
  late Map<String, dynamic> vercelConfig;

  setUpAll(() {
    final root = Directory.current.path;
    final raw = File('$root/vercel.json').readAsStringSync();
    vercelConfig = jsonDecode(raw) as Map<String, dynamic>;
  });

  List<Map<String, dynamic>> redirects() =>
      (vercelConfig['redirects'] as List).cast<Map<String, dynamic>>();

  group('vercel.json redirects', () {
    test('redirects /confirm to the hash route GoRouter reads', () {
      final entry = redirects().where((r) => r['source'] == '/confirm');
      expect(
        entry,
        isNotEmpty,
        reason:
            'no /confirm redirect — a bare-path /confirm link 404s/dead-ends '
            'for anyone without the app installed (HashUrlStrategy needs the '
            'fragment form)',
      );
      expect(entry.single['destination'], '/#/confirm');
    });

    test('redirects /confirm/ (trailing slash) the same way /admin/ does',
        () {
      final entry = redirects().where((r) => r['source'] == '/confirm/');
      expect(entry, isNotEmpty);
      expect(entry.single['destination'], '/#/confirm');
    });

    test('does not remove the existing /admin redirect (diagnose b3f9a1)',
        () {
      final entry = redirects().where((r) => r['source'] == '/admin');
      expect(
        entry,
        isNotEmpty,
        reason:
            '/admin redirect must survive — lib/features/admin/CLAUDE.md:114 '
            'explicitly warns against removing it',
      );
      expect(entry.single['destination'], '/#/admin');
    });

    test('SPA catch-all rewrite still excludes .well-known/ (assetlinks.json)',
        () {
      final rewrites =
          (vercelConfig['rewrites'] as List).cast<Map<String, dynamic>>();
      final catchAll = rewrites.single['source'] as String;
      expect(
        catchAll,
        contains(r'.well-known'),
        reason:
            'the catch-all rewrite must keep excluding .well-known/ or it '
            'swallows assetlinks.json and silently breaks Android App Links '
            'too — see lib/features/auth/CLAUDE.md pitfall row',
      );
    });
  });

  group('app_router.dart /confirm route', () {
    test('reads token_hash from the query string GoRouter parses out of the '
        'hash fragment', () {
      final root = Directory.current.path;
      final appRouter =
          File('$root/lib/core/router/app_router.dart').readAsStringSync();
      expect(appRouter, contains("path: '/confirm'"));
      expect(
        appRouter,
        contains("state.uri.queryParameters['token_hash']"),
        reason:
            'the redirect only helps if the route on the other side of the '
            'hash still reads token_hash the same way',
      );
    });
  });
}
