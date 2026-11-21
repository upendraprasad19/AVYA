// test/contracts/migration_152_drop_subscription_mirror_test.dart
//
// Pins the TEXT of migration 152 (OI-202, diagnose c7e3b9): the one migration that
// drops the users.subscription_status / subscription_expires_at mirror. The migration
// is applied and immutable, so this guards the file, the ledger entry and the schema
// snapshot against an edit that would make the record lie about what ran.
//
// What each group protects (the reasons are the review findings, not decoration):
//  * ORDER: the private.founder_metrics() rewrite must precede every DROP. A plpgsql/sql
//    function body is not dependency-tracked, so DROP COLUMN would succeed silently and
//    break every founder_metrics() caller at runtime.
//  * pro_expired = ANY subscriptions row and NO live active one, via NOT EXISTS (never
//    NOT IN: a NULL in the subquery makes NOT IN match nothing). A status-only reading
//    gives the same live numbers today, so nothing but this text pins the difference.
//  * REVOKE/GRANT are re-issued: CREATE OR REPLACE keeps the ACL, but a future edit that
//    turns it into DROP + CREATE would hand SECURITY DEFINER execute to PUBLIC.
//  * lock_timeout is a plain SET + RESET, not SET LOCAL: SET LOCAL is a no-op with a
//    WARNING outside a transaction, leaving the ALTER TABLE lock wait unbounded.
//  * The commented rollback restores the orphan row from the snapshot.
//
// Source-grep (presence). The behavioural half is the live dry-run/apply recorded in the
// diagnose-doc and the ledger note; a SQL file cannot be executed from a Dart unit test.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _sqlPath = 'supabase/migrations/152_drop_users_subscription_mirror.sql';

/// Drops `/* */` block comments and `--` line comments and collapses whitespace so assertions are layout-proof.
String _code(String sql) => sql
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
    .split('\n')
    .map((l) {
      final i = l.indexOf('--');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n')
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase();

void main() {
  late String raw;
  late String code;

  setUpAll(() {
    raw = File(_sqlPath).readAsStringSync();
    code = _code(raw);
  });

  int at(String needle) => code.indexOf(needle);

  group('order', () {
    test('the founder_metrics rewrite precedes every drop', () {
      final rewrite = at('create or replace function private.founder_metrics()');
      expect(rewrite, greaterThanOrEqualTo(0), reason: 'rewrite missing');
      for (final drop in [
        'drop trigger if exists trg_subscription_update_user',
        'drop function if exists public.update_user_subscription_status()',
        'drop function if exists public.extend_subscription(uuid, integer)',
        'alter table public.users drop column if exists subscription_status',
        'alter table public.users drop column if exists subscription_expires_at',
      ]) {
        final i = at(drop);
        expect(i, greaterThanOrEqualTo(0), reason: 'missing: $drop');
        expect(rewrite, lessThan(i),
            reason: 'the rewrite must come BEFORE "$drop"');
      }
    });

    test('the writers (trigger + functions) are dropped before the columns', () {
      final firstColumnDrop =
          at('alter table public.users drop column if exists subscription_status');
      for (final w in [
        'drop trigger if exists trg_subscription_update_user',
        'drop function if exists public.update_user_subscription_status()',
        'drop function if exists public.extend_subscription(uuid, integer)',
      ]) {
        expect(at(w), lessThan(firstColumnDrop), reason: w);
      }
    });
  });

  group('founder_metrics body', () {
    late String body;
    setUpAll(() {
      final start = code.indexOf('create or replace function private.founder_metrics()');
      final end = code.indexOf(r'$function$;', start);
      body = code.substring(start, end);
    });

    test('reads neither dropped column', () {
      expect(body.contains('subscription_status'), isFalse);
      expect(body.contains('subscription_expires_at'), isFalse);
    });

    test('pro_expired is any-status-row AND NOT EXISTS live active (never NOT IN)', () {
      expect(
        body,
        contains("exists (select 1 from public.subscriptions s where s.user_id = u.id) "
            "and not exists (select 1 from public.subscriptions s where s.user_id = u.id "
            "and s.status = 'active' and s.end_date > now())"),
      );
      expect(body.contains('not in'), isFalse,
          reason: 'NOT IN over a nullable subquery matches nothing');
    });

    test('pro_active uses the single PRO predicate', () {
      expect(
        body,
        contains("(select count(*) from u where exists (select 1 from public.subscriptions s "
            "where s.user_id = u.id and s.status = 'active' and s.end_date > now()))::bigint"),
      );
    });

    test('free_users is total minus users with any subscriptions row', () {
      expect(
        body,
        contains("((select count(*) from u) - (select count(*) from u where exists "
            "(select 1 from public.subscriptions s where s.user_id = u.id)) )::bigint"),
      );
    });

    test('the unchanged columns keep their exact expressions', () {
      for (final expr in [
        '(select count(*) from u)::bigint,',
        "(select count(*) from u where created_at >= (date_trunc('day', now() at time zone 'asia/kolkata') "
            "at time zone 'asia/kolkata'))::bigint,",
        "(select count(*) from u where created_at >= now() - interval '7 days')::bigint,",
        "(select count(*) from u where created_at >= now() - interval '30 days')::bigint,",
        "(select count(distinct user_id) from public.subscriptions where status = 'active')::bigint,",
        "(select count(*) from u where last_active_at >= now() - interval '7 days')::bigint,",
      ]) {
        expect(body, contains(expr));
      }
    });

    test('excludes soft-deleted users and pins the search_path', () {
      expect(body,
          contains('with u as ( select * from public.users where is_deleted is not true )'));
      expect(body, contains("set search_path to 'public', 'private'"));
      expect(body, contains('security definer'));
    });
  });

  group('privileges', () {
    test('REVOKE from PUBLIC/anon/authenticated then GRANT to service_role, after the create', () {
      final create = at('create or replace function private.founder_metrics()');
      final revoke = at('revoke all on function private.founder_metrics() '
          'from public, anon, authenticated;');
      final grant =
          at('grant execute on function private.founder_metrics() to service_role;');
      expect(revoke, greaterThan(create), reason: 'the full REVOKE statement (with ;) is missing');
      expect(grant, greaterThan(revoke), reason: 'the full GRANT statement (with ;) is missing');
    });

    test('service_role is the ONLY grantee of a SECURITY DEFINER function', () {
      final grants = RegExp(r'grant [^;]*? on function private\.founder_metrics\(\) to ([^;]*);')
          .allMatches(code)
          .toList();
      expect(grants, hasLength(1));
      expect(grants.single.group(1)!.trim(), 'service_role',
          reason: 'a widened grantee list opens a SECURITY DEFINER function');
    });
  });

  group('lock bound', () {
    test("plain SET lock_timeout = '5s' (not SET LOCAL) and a closing RESET", () {
      expect(code, contains("set lock_timeout = '5s'"));
      expect(code.contains('set local lock_timeout'), isFalse);
      expect(at('reset lock_timeout'),
          greaterThan(at('alter table public.users drop column if exists subscription_expires_at')));
    });
  });

  group('rollback block', () {
    late String rollback;
    late String rollbackCode;
    setUpAll(() {
      rollback = raw.substring(raw.indexOf('-- ROLLBACK (inline'));
      // Un-comment: drop the leading "-- " so the reverse DDL reads as code.
      rollbackCode = rollback
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^--\s?'), ''))
          .join('\n')
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();
    });

    test('restores the orphan row from the snapshot', () {
      expect(raw, contains('-- UPDATE public.users SET subscription_status = \'pro\''));
      expect(raw, contains('4d27a40b-ce2b-48e6-8485-f6f5a1b85863'));
    });

    test('carries no transaction control of its own', () {
      // plpgsql bodies hold a bare "BEGIN" and "END;"; only BEGIN/COMMIT/START TRANSACTION + ";" is control.
      expect(
          RegExp(r'^--\s*(BEGIN|COMMIT|START\s+TRANSACTION)\s*;',
                  multiLine: true, caseSensitive: false)
              .hasMatch(rollback),
          isFalse);
    });

    test('re-creates the columns, both writers, the trigger and the 093 founder_metrics body', () {
      for (final piece in [
        'alter table public.users add column if not exists subscription_status text default \'free\';',
        'alter table public.users add column if not exists subscription_expires_at timestamptz;',
        'create or replace function public.update_user_subscription_status()',
        'greatest(coalesce(subscription_expires_at, new.end_date), new.end_date)',
        'create trigger trg_subscription_update_user after insert or update on public.subscriptions',
        "for each row when (new.status = 'active') execute function public.update_user_subscription_status();",
        'create or replace function public.extend_subscription(p_user_id uuid, p_days integer)',
        "set end_date = end_date + (p_days || ' days')::interval",
        'create or replace function private.founder_metrics()',
        "from u where subscription_status = 'pro' and (subscription_expires_at is null or subscription_expires_at > now())",
        "from u where coalesce(subscription_status, 'free') = 'free'",
      ]) {
        expect(rollbackCode, contains(piece.toLowerCase()), reason: 'rollback lost: $piece');
      }
    });
  });

  group('records', () {
    test('ledger entry has a real cloud version and matches the file slug', () {
      final ledger = jsonDecode(File('backups/applied_migrations.json').readAsStringSync())
          as List<dynamic>;
      final e = ledger.cast<Map<String, dynamic>>().singleWhere((m) => m['migration'] == '152');
      expect(e['slug'], 'drop_users_subscription_mirror');
      expect(e['cloud_version'], matches(RegExp(r'^\d{14}$')),
          reason: 'a live-apply-<date> placeholder is not a version');
      expect(e['diagnose'], 'c7e3b9');
    });

    test('the live schema snapshot no longer lists either column on users', () {
      final snap = jsonDecode(File('backups/live_schema_columns.json').readAsStringSync())
          as Map<String, dynamic>;
      final users = ((snap['tables'] as Map<String, dynamic>)['users'] as List).cast<String>();
      expect(users.contains('subscription_status'), isFalse);
      expect(users.contains('subscription_expires_at'), isFalse);
      expect(users.contains('is_deleted'), isTrue, reason: 'snapshot must still be a real users list');
    });
  });
}
