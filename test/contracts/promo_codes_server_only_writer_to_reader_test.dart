// test/contracts/promo_codes_server_only_writer_to_reader_test.dart
//
// Migration 163 (promo_codes_server_only_access; OI-406, diagnose a6c2e9). Before it, the public anon key could
// list every active promo code with its discount: migration 20260330_create_promo_codes.sql created the policy
// "Anyone can read active promo codes" and the platform's default grants gave anon and authenticated every table
// privilege. 163 drops that policy and revokes every privilege from PUBLIC, anon and authenticated; only the
// payment Edge Functions read the table, through the service role.
//
// WHAT THIS FILE IS, AND IS NOT. SOURCE pins on the migration text and on who names the table. They prove the
// rule is WRITTEN. What the live catalog DOES is test/sql/promo_codes_no_client_access_live_verify.sql (16 cases,
// one aborting transaction; its SUMMARY line counts them).
//
// THE DRAFT. Gate 14 (scripts/check_migrations_applied.dart) fails any .sql in supabase/migrations/ that has no
// ledger entry, so the file is drafted under docs/plans/ until its live apply and then moved with `git mv`.
// Exactly ONE of the two paths must exist; the pins read whichever does.
//
// Groups: 1 the statements (whole, not clauses); 2 the header and the inline rollback; 3 the dropped policy is
// the one that exists; 4 the tier guards; 5 no client reader; 6 the Edge Function readers use the service role;
// 7 no later migration re-opens the table; 8 the rehearsal is the live verify plus exactly the migration.
//
// Run: flutter test test/contracts/promo_codes_server_only_writer_to_reader_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/migration_cap_reader.dart';

const _finalPath = 'supabase/migrations/163_promo_codes_server_only_access.sql';
const _draftPath = 'docs/plans/promo-codes-server-only/163_promo_codes_server_only_access.sql.draft';
const _createPath = 'supabase/migrations/20260330_create_promo_codes.sql';
const _policyName = 'Anyone can read active promo codes';
const _verifyPath = 'test/sql/promo_codes_no_client_access_live_verify.sql';
const _rehearsalPath = 'test/sql/promo_codes_server_only_rehearsal.sql';

/// The migration's text, from whichever of the two paths exists (exactly one must).
String _migrationText() {
  final present = [_finalPath, _draftPath].where((p) => File(p).existsSync()).toList();
  expect(present.length, 1,
      reason: 'exactly one of $_finalPath and $_draftPath must exist, found $present');
  return File(present.single).readAsStringSync();
}

/// TypeScript with block and line comments removed (`(?<!:)` keeps the `//` of a URL).
String _tsCode(String ts) =>
    ts.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

/// Comment-stripped and whitespace-squashed.
String _squash(String sql) => stripSqlComments(sql).replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  group('1 the statements', () {
    test('the executable body is exactly the DROP POLICY and the REVOKE, nothing else', () {
      expect(
        _squash(_migrationText()),
        'DROP POLICY IF EXISTS "$_policyName" ON public.promo_codes; '
        'REVOKE ALL ON TABLE public.promo_codes FROM PUBLIC, anon, authenticated;',
      );
    });
  });

  group('2 the header and the inline rollback', () {
    test('the four tags: Destructive yes, rollback inline, diagnose a6c2e9', () {
      final head = _migrationText().split('\n').take(4).toList();
      expect(head[0], startsWith('-- Intent: '));
      expect(head[1], startsWith('-- Destructive?: yes '));
      expect(head[2], startsWith('-- Rollback strategy: inline '));
      expect(head[3], '-- Linked diagnose-doc: a6c2e9');
    });

    test('the commented rollback restores the captured policy and grant', () {
      final rollback = _migrationText().split('-- ROLLBACK').last.replaceAll(RegExp(r'--\s*'), '');
      final squashed = rollback.replaceAll(RegExp(r'\s+'), ' ');
      expect(squashed,
          contains('CREATE POLICY "$_policyName" ON public.promo_codes FOR SELECT USING (is_active = true);'));
      expect(squashed, contains('GRANT ALL ON TABLE public.promo_codes TO anon, authenticated;'));
    });
  });

  group('3 the dropped policy is the one that exists', () {
    test('DROP POLICY IF EXISTS names the policy migration 20260330 created (a typo would be a silent no-op)', () {
      final create = _squash(File(_createPath).readAsStringSync());
      expect(create, contains('CREATE POLICY "$_policyName" ON promo_codes FOR SELECT USING (is_active = true);'));
      expect(_squash(_migrationText()), contains('DROP POLICY IF EXISTS "$_policyName" ON public.promo_codes;'));
    });
  });

  group('4 the tier guards', () {
    test('no "security definer" text and no "rls" in the slug (either would make the file catastrophic)', () {
      expect(RegExp(r'security\s+definer', caseSensitive: false).hasMatch(_migrationText()), isFalse);
      expect(_finalPath.split('/').last.contains('rls'), isFalse);
    });
  });

  group('5 no client reader', () {
    test('no file under lib/ or web/ names promo_codes', () {
      final hits = <String>[];
      for (final root in ['lib', 'web']) {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;
        // Every file, not an extension list (B-pass F12): a .mjs, .jsx or .tsx reader counts too.
        for (final f in dir.listSync(recursive: true).whereType<File>()) {
          final String text;
          try {
            text = f.readAsStringSync();
          } on FileSystemException {
            continue; // binary asset
          }
          if (text.contains('promo_codes')) hits.add(f.path);
        }
      }
      expect(hits, isEmpty, reason: 'a client reader would now get 42501: $hits');
    });
  });

  group('6 the Edge Function readers use the service role', () {
    test('every function that names promo_codes builds EVERY client with the service-role key, in code', () {
      // B-pass F1: a whole-text contains() was satisfied by a header comment, and by a module constant kept
      // while a call site switched to another key. So: comments stripped, every createClient( call's second
      // argument must be the service-role key, the constant must come from the service-role env var, and no
      // anon key may appear in code.
      final readers = <String>[];
      for (final f in Directory('supabase/functions').listSync(recursive: true).whereType<File>()) {
        final p = f.path.replaceAll('\\', '/');
        if (!p.endsWith('/index.ts')) continue;
        final code = _tsCode(f.readAsStringSync());
        if (!code.contains('promo_codes')) continue;
        readers.add(p);
        final calls = RegExp(r'createClient\(\s*([^,]+?)\s*,\s*([^,)]+?)\s*[,)]').allMatches(code).toList();
        expect(calls, isNotEmpty, reason: '$p names promo_codes but builds no client');
        for (final c in calls) {
          expect(c.group(2), anyOf('SUPABASE_SERVICE_ROLE_KEY', 'Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!'),
              reason: '$p: createClient(${c.group(1)}, ${c.group(2)}) is not the service-role client');
        }
        if (calls.any((c) => c.group(2) == 'SUPABASE_SERVICE_ROLE_KEY')) {
          expect(
              RegExp(r'SUPABASE_SERVICE_ROLE_KEY\s*=\s*Deno\.env\.get\(\s*"SUPABASE_SERVICE_ROLE_KEY"\s*\)')
                  .hasMatch(code),
              isTrue,
              reason: '$p: SUPABASE_SERVICE_ROLE_KEY is not read from the service-role env var');
        }
        expect(code.contains('SUPABASE_ANON_KEY'), isFalse, reason: '$p uses the anon key in code');
      }
      readers.sort();
      expect(readers, [
        'supabase/functions/create-razorpay-order/index.ts',
        'supabase/functions/razorpay-webhook/index.ts',
        'supabase/functions/validate-promo/index.ts',
        'supabase/functions/verify-payment/index.ts',
      ]);
    });
  });

  group('7 no later migration re-opens the table', () {
    test('no other migration grants promo_codes to a client role or creates a policy on it', () {
      // B-pass F2 (measured): the first version missed ON ALL TABLES IN SCHEMA, a comma list with
      // promo_codes second, and quoted identifiers. Each shape below is a real way to re-open the table.
      const client = r'\bTO\s[^;]*\b(anon|authenticated|PUBLIC)\b';
      final reopen = RegExp(
        r'(GRANT\s[^;]*\bON\s+(TABLE\s+)?[^;]*\bpromo_codes\b[^;]*' + client + r')'
        r'|(GRANT\s[^;]*\bON\s+ALL\s+TABLES\s+IN\s+SCHEMA\s+"?public"?[^;]*' + client + r')'
        r'|(CREATE\s+POLICY\s[^;]*\bON\s+("?public"?\.)?"?promo_codes"?[\s;])',
        caseSensitive: false,
      );
      final hits = <String>[];
      for (final f in Directory('supabase/migrations').listSync(recursive: true).whereType<File>()) {
        final p = f.path.replaceAll('\\', '/');
        if (!p.endsWith('.sql') || p == _createPath) continue;
        if (reopen.hasMatch(stripSqlComments(f.readAsStringSync()))) hits.add(p);
      }
      expect(hits, isEmpty);
    });
  });

  group('8 the rehearsal is the live verify plus exactly the migration', () {
    // B-pass F8: the dry run is ONE aborting statement (no explicit BEGIN/ROLLBACK that the RAISE would skip).
    // It must not drift from the verify it reuses, nor from the migration it rehearses.
    String doBlock(String path) {
      final text = File(path).readAsStringSync();
      final start = text.indexOf(r'DO $v$');
      expect(start, greaterThanOrEqualTo(0), reason: '$path has no DO block');
      return text.substring(start);
    }

    test('the rehearsal block equals the verify block with a prelude after the first BEGIN, and nothing else', () {
      final verify = doBlock(_verifyPath);
      final rehearsal = doBlock(_rehearsalPath);
      const anchor = '  v_case    text;\nBEGIN\n';
      expect(verify.split(anchor).length, 2);
      final at = verify.indexOf(anchor) + anchor.length;
      expect(rehearsal.startsWith(verify.substring(0, at)), isTrue, reason: 'the DECLARE part differs');
      final rest = verify.substring(at);
      expect(rehearsal.endsWith(rest), isTrue, reason: 'the checks differ from the live verify');
      final prelude = rehearsal.substring(at, rehearsal.length - rest.length);
      final executed = RegExp(r"EXECUTE '([^']*(?:''[^']*)*)';")
          .allMatches(stripSqlComments(prelude))
          .map((m) => '${m.group(1)!.replaceAll("''", "'")};')
          .join(' ');
      expect(executed, _squash(_migrationText()),
          reason: 'the rehearsal must run exactly the migration statements');
      expect(stripSqlComments(prelude).replaceAll(RegExp(r"EXECUTE '([^']*(?:''[^']*)*)';"), '').trim(), isEmpty,
          reason: 'the prelude runs nothing but the migration');
    });

    test('neither file opens or ends a transaction itself', () {
      for (final path in [_verifyPath, _rehearsalPath]) {
        final code = stripSqlComments(File(path).readAsStringSync()).toUpperCase();
        expect(RegExp(r'^\s*(BEGIN|START\s+TRANSACTION|COMMIT|ROLLBACK)\s*;', multiLine: true).hasMatch(code), isFalse,
            reason: '$path must stay one aborting statement');
      }
    });
  });
}
