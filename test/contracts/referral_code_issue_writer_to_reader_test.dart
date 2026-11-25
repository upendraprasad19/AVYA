// SoT concept `referral_code_issue` (OI-348 B2, diagnose c2e8a4).
//
// Writer: public.issue_referral_code() (migration 186), the ONLY writer of referral_codes the client
// reaches. Reader on the client: SupabaseService.getOrCreateReferralCode / regenerateReferralCode ->
// parseIssuedReferralCode -> InviteFriendsSheet.
//
// What this file proves:
//   * the parser (pure, every row shape) and the two entry points through the RPC seam;
//   * the RPC name and the OUT column names the client reads are the ones migration 186 declares
//     (two files, nothing else ties them together);
//   * no client code WRITES referral_codes any more (upsert / insert / update / delete), whatever the
//     chain spelling; the restore's SELECT stays.
// The server behaviour is test/sql/referral_code_issue_live_verify.sql; the sheet's error and Retry
// are test/profile/invite_friends_sheet_issue_failure_test.dart.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

import '../helpers/dart_source_slice.dart';

const _migration = 'supabase/migrations/186_issue_referral_code.sql';

List<File> _dartFilesUnder(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Every `.from('referral_codes')` statement in [src] (comment-stripped) that is not a plain read:
/// it writes (upsert / insert / update / delete) or it is not a `.select(` chain at all (a builder
/// held in a variable and written later: `final t = client.from('referral_codes'); t.upsert(...)`).
List<String> _writingChains(String src) {
  final out = <String>[];
  final from = RegExp(r'''\.from\(\s*['"]referral_codes['"]\s*\)''');
  for (final m in from.allMatches(src)) {
    // The chain runs to the end of the statement.
    final end = src.indexOf(';', m.end);
    final chain = src.substring(m.start, end == -1 ? src.length : end);
    if (RegExp(r'\.(upsert|insert|update|delete)\s*\(').hasMatch(chain) ||
        !RegExp(r'\.select\s*\(').hasMatch(chain)) {
      out.add(chain.replaceAll(RegExp(r'\s+'), ' '));
    }
  }
  return out;
}

/// The only lib/ files allowed to spell the table name as a string literal, and why. A NEW file
/// that names it (a variable-held table name, a helper taking the name) fails the test below and
/// must be reviewed against B2's rule: the client never writes referral_codes.
const _tableNameAllowlist = {
  'lib/core/services/sync/sync_restore_completeness.dart': 'the restore SELECT of the own code',
  'lib/core/services/sync_service.dart': 'the restore bundle key list (single-call restore payload)',
};

void main() {
  tearDown(() => SupabaseService.issueReferralCodeRpcForTest = null);

  group('parseIssuedReferralCode (pure)', () {
    test('one row -> the code and the expiry', () {
      final r = parseIssuedReferralCode([
        {'out_code': 'AVYA-ABCD1234', 'out_expires_at': '2026-12-01T10:00:00+00:00'},
      ]);
      expect(r, isNotNull);
      expect(r!.code, 'AVYA-ABCD1234');
      expect(r.expiresAt, DateTime.utc(2026, 12, 1, 10));
    });

    test('only the first row is read', () {
      final r = parseIssuedReferralCode([
        {'out_code': 'AVYA-FIRST001', 'out_expires_at': '2026-12-01T10:00:00Z'},
        {'out_code': 'AVYA-SECOND01', 'out_expires_at': '2026-12-02T10:00:00Z'},
      ]);
      expect(r!.code, 'AVYA-FIRST001');
    });

    for (final (name, raw) in <(String, dynamic)>[
      ('null', null),
      ('an empty list', <dynamic>[]),
      ('a bare map (not a list)', {'out_code': 'AVYA-ABCD1234', 'out_expires_at': '2026-12-01T10:00:00Z'}),
      ('a row that is not a map', ['AVYA-ABCD1234']),
      ('no out_code', [{'out_expires_at': '2026-12-01T10:00:00Z'}]),
      ('an empty out_code', [{'out_code': '', 'out_expires_at': '2026-12-01T10:00:00Z'}]),
      ('no out_expires_at', [{'out_code': 'AVYA-ABCD1234'}]),
      ('an unreadable date', [{'out_code': 'AVYA-ABCD1234', 'out_expires_at': 'tomorrow'}]),
      ('the COLUMN names instead of the OUT names', [{'code': 'AVYA-ABCD1234', 'expires_at': '2026-12-01T10:00:00Z'}]),
    ]) {
      test('$name -> null', () => expect(parseIssuedReferralCode(raw), isNull));
    }
  });

  group('the two entry points go through the RPC (seam)', () {
    final row = [
      {'out_code': 'AVYA-SEAM0001', 'out_expires_at': '2026-12-01T10:00:00Z'},
    ];

    test('getOrCreateReferralCode returns the issued code', () async {
      var calls = 0;
      SupabaseService.issueReferralCodeRpcForTest = () async {
        calls++;
        return row;
      };
      final r = await SupabaseService.instance.getOrCreateReferralCode();
      expect(r!.code, 'AVYA-SEAM0001');
      expect(calls, 1);
    });

    test('regenerateReferralCode returns the issued code', () async {
      var calls = 0;
      SupabaseService.issueReferralCodeRpcForTest = () async {
        calls++;
        return row;
      };
      final r = await SupabaseService.instance.regenerateReferralCode();
      expect(r!.code, 'AVYA-SEAM0001');
      expect(calls, 1);
    });

    test('a throwing RPC -> null, never an exception', () async {
      SupabaseService.issueReferralCodeRpcForTest = () async => throw StateError('42501');
      expect(await SupabaseService.instance.regenerateReferralCode(), isNull);
      expect(await SupabaseService.instance.getOrCreateReferralCode(), isNull);
    });

    test('an empty answer -> null', () async {
      SupabaseService.issueReferralCodeRpcForTest = () async => <dynamic>[];
      expect(await SupabaseService.instance.regenerateReferralCode(), isNull);
    });
  });

  group('issueReferralCodeVia: the real order (signed-in check, token, RPC with a timeout)', () {
    final row = [
      {'out_code': 'AVYA-ORDER001', 'out_expires_at': '2026-12-01T10:00:00Z'},
    ];

    test('signed out -> null; neither the token refresh nor the RPC runs', () async {
      final events = <String>[];
      final r = await SupabaseService.issueReferralCodeVia(
        isSignedIn: () => false,
        refreshToken: () async => events.add('refresh'),
        rpc: () async {
          events.add('rpc');
          return row;
        },
      );
      expect(r, isNull);
      expect(events, isEmpty);
    });

    test('signed in -> the token is refreshed BEFORE the RPC, then the row is parsed', () async {
      final events = <String>[];
      final r = await SupabaseService.issueReferralCodeVia(
        isSignedIn: () => true,
        refreshToken: () async => events.add('refresh'),
        rpc: () async {
          events.add('rpc');
          return row;
        },
      );
      expect(r!.code, 'AVYA-ORDER001');
      expect(events, ['refresh', 'rpc']);
    });

    test('an RPC that never answers -> null after the timeout', () async {
      final never = Completer<dynamic>();
      final r = await SupabaseService.issueReferralCodeVia(
        isSignedIn: () => true,
        refreshToken: () async {},
        rpc: () => never.future,
        timeout: const Duration(milliseconds: 20),
      );
      expect(r, isNull);
    });

    test('a throwing token refresh -> null, and the RPC never runs', () async {
      var rpcCalls = 0;
      final r = await SupabaseService.issueReferralCodeVia(
        isSignedIn: () => true,
        refreshToken: () async => throw StateError('refresh failed'),
        rpc: () async {
          rpcCalls++;
          return row;
        },
      );
      expect(r, isNull);
      expect(rpcCalls, 0);
    });

    test('a throwing signed-in check -> null, never an exception', () async {
      final r = await SupabaseService.issueReferralCodeVia(
        isSignedIn: () => throw StateError('not initialised'),
        refreshToken: () async {},
        rpc: () async => row,
      );
      expect(r, isNull);
    });
  });

  test('production wiring: the real signed-in check, ensureFreshToken and the issue_referral_code RPC', () {
    final service = stripDartComments(
        File('lib/core/services/supabase_service.dart').readAsStringSync());
    final body = functionBody(service, '_issueReferralCode() {');
    final squashed = body.replaceAll(RegExp(r'\s+'), ' ');
    expect(squashed, contains('isSignedIn: () => currentUser != null,'));
    expect(squashed, contains('refreshToken: ensureFreshToken,'));
    expect(squashed, contains("rpc: () => client.rpc('issue_referral_code'),"));
    // No timeout override on the production call: the 15 s default applies.
    expect(squashed, isNot(contains('timeout:')));
    expect(service.replaceAll(RegExp(r'\s+'), ' '), contains('Duration timeout = const Duration(seconds: 15),'));
  });

  group('client and migration agree (two files)', () {
    late String sql;
    late String service;
    setUpAll(() {
      sql = File(_migration).readAsStringSync();
      service = stripDartComments(
          File('lib/core/services/supabase_service.dart').readAsStringSync());
    });

    test('the client calls the function the migration creates, once', () {
      expect(sql, contains('CREATE OR REPLACE FUNCTION public.issue_referral_code()'));
      expect(countOf(service, ".rpc('issue_referral_code')"), 1);
    });

    test('the OUT names the parser reads are the ones the migration returns', () {
      expect(sql, contains('RETURNS TABLE (out_code text, out_expires_at timestamptz)'));
      final parser = functionBody(service, 'parseIssuedReferralCode(dynamic raw)');
      expect(parser, contains("row['out_code']"));
      expect(parser, contains("row['out_expires_at']"));
    });
  });

  group('no client code writes referral_codes', () {
    test('lib/ has no upsert / insert / update / delete chain on referral_codes', () {
      final hits = <String>[];
      for (final f in _dartFilesUnder('lib')) {
        for (final chain in _writingChains(stripDartComments(f.readAsStringSync()))) {
          hits.add('${f.path}: $chain');
        }
      }
      expect(hits, isEmpty);
    });

    test('the restore still READS referral_codes (the scan is not blind)', () {
      final reads = <String>[];
      for (final f in _dartFilesUnder('lib')) {
        final src = stripDartComments(f.readAsStringSync());
        if (RegExp(r'''\.from\(\s*['"]referral_codes['"]\s*\)''').hasMatch(src)) reads.add(f.path);
      }
      expect(reads, isNotEmpty);
    });

    test('the scan reads every write spelling (controls)', () {
      for (final s in [
        "client.from('referral_codes').upsert({'code': c}, onConflict: 'user_id');",
        'client.from("referral_codes").insert({});',
        "client\n  .from('referral_codes')\n  .update({'code': c})\n  .eq('user_id', u);",
        "client.from( 'referral_codes' ).delete().eq('user_id', u);",
        "final t = client.from('referral_codes'); t.upsert({});",
      ]) {
        expect(_writingChains(s), isNotEmpty, reason: s);
      }
      expect(_writingChains("client.from('referral_codes').select('code').eq('user_id', u);"), isEmpty);
    });

    test('only the allowlisted lib/ files spell the table name as a string literal', () {
      final literal = RegExp(r'''['"]referral_codes['"]''');
      final found = <String>{
        for (final f in _dartFilesUnder('lib'))
          if (literal.hasMatch(stripDartComments(f.readAsStringSync()))) f.path.replaceAll(r'\', '/'),
      };
      expect(found, _tableNameAllowlist.keys.toSet());
    });
  });
}
