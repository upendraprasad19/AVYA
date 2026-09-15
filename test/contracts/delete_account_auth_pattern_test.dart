// Regression test for bug e8a1c3 (2026-06-12 live E2E, Obs#10).
//
// Pins the delete-account Edge Function JWT-auth contract: it MUST validate the
// caller by passing the token explicitly to getUser(token) on a SERVICE_ROLE
// client (the pattern the working EFs use), and MUST NOT rebuild the broken
// `createClient(SUPABASE_URL, authHeader.replace("Bearer ","")).auth.getUser()`
// pattern that passed the USER JWT as the supabaseKey and called getUser() with no
// token — which made GoTrue reject EVERY valid user token (401) and rendered the
// DPDP §17 erasure unreachable for all users.
//
// Proven live pre-fix: with the same session token, /auth/v1/user → 200 and
// ai-proxy → 200, but delete-account → 401 (req 84b8f6ad).
//
// The EF runs in Deno, so this is a source-grep with comment-stripping (the fix's
// own comment quotes the OLD broken pattern and would false-positive otherwise) —
// per feedback_source_grep_strip_comments_first.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final raw =
      File('supabase/functions/delete-account/index.ts').readAsStringSync();
  final src = _strip(raw);

  test('e8a1c3 — auth validates the caller via getUser(token) (token passed)', () {
    expect(
      RegExp(r'auth\.getUser\(\s*token\s*\)').hasMatch(src),
      isTrue,
      reason: 'delete-account must validate the caller with getUser(token) — the '
          'token passed explicitly (mirrors daily-snapshot / ai-media-proxy / '
          'assess-body-composition). Without this, a valid token cannot be '
          'validated and the DPDP erasure 401s for everyone.',
    );
  });

  test('e8a1c3 — the auth client uses the SERVICE_ROLE key (a valid apikey)', () {
    expect(
      RegExp(r'createClient\(\s*SUPABASE_URL[^;]*?SERVICE_ROLE').hasMatch(src),
      isTrue,
      reason: 'the auth client must be built with SERVICE_ROLE as the supabaseKey '
          '(a valid apikey), not the user JWT.',
    );
  });

  test('e8a1c3 — the broken user-JWT-as-key + bare getUser() pattern is gone', () {
    expect(
      RegExp(r'createClient\(\s*SUPABASE_URL[^;]*?authHeader\.replace')
          .hasMatch(src),
      isFalse,
      reason: 'must NOT pass authHeader.replace("Bearer ","") (the USER JWT) as the '
          'supabaseKey to createClient — GoTrue rejects a user JWT used as an '
          'apikey, 401-ing every valid token.',
    );
    expect(
      RegExp(r'auth\.getUser\(\s*\)').hasMatch(src),
      isFalse,
      reason: 'must NOT call getUser() with no token argument — it has no token to '
          'validate and returns no user.',
    );
  });

  // d5b2f8 — the SECOND never-run bug, revealed once e8a1c3 let the erasure path
  // execute: the audit insert chained `.catch()` on a PostgREST builder (a thenable
  // with NO .catch method) → TypeError → 500 AFTER the successful delete + the audit
  // row never wrote.
  test('d5b2f8 — audit insert is awaited with an error-check, not .catch() on the builder',
      () {
    expect(
      src.contains('error: auditErr'),
      isTrue,
      reason: 'the account_deletion_log insert must use '
          '`const { error: auditErr } = await admin.from(...).insert(...)` + an '
          'error check, not a builder .catch().',
    );
    final auditBuilderCatch =
        RegExp(r'account_deletion_log[\s\S]{0,500}?\.catch\(', multiLine: true);
    expect(
      auditBuilderCatch.hasMatch(src),
      isFalse,
      reason: 'the account_deletion_log insert must NOT chain `.catch(` on the '
          'PostgREST builder — it has no .catch method → TypeError → 500 after the '
          'account is already deleted, and the DPDP audit row never persists.',
    );
  });
}
